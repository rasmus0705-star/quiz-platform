-- =====================================================================
-- 001_sikkerhed_og_runder.sql          (kør i Supabase → SQL Editor)
--
-- Hvad den gør:
--   1. Lukker de åbne læse-rettigheder (teams/submissions/customers m.fl.)
--   2. Indfører "runder" (genaktivering = ny runde, gamle resultater gemmes)
--   3. Server-side PIN-hash (bcrypt) + migrering af gamle SHA-256 ved login
--   4. Nye RPC'er: scoreboard, start af hold, status, foto-godkendelse m.m.
--   5. Beskytter quizzes mod at kunder ændrer status/ejer direkte
--
-- Kan køres flere gange (idempotent). Hvis Supabase spørger om RLS på en
-- ny tabel: vælg "Run and enable RLS".
-- Kør hele filen i ét hug. Tag derefter 'Del 9' til sidst.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ---------------------------------------------------------------------
-- DEL 1: Luk åbne rettigheder
-- ---------------------------------------------------------------------
-- Disse policies lod alle med anon-nøglen (offentlig i config.js) læse
-- hele tabellerne - inkl. hold-tokens, andres svar og kunders PIN-hash.
DROP POLICY IF EXISTS anon_kan_slaa_email_op  ON quiz.customers;
DROP POLICY IF EXISTS anon_read_submissions   ON quiz.submissions;
DROP POLICY IF EXISTS anon_read_teams         ON quiz.teams;
DROP POLICY IF EXISTS anon_read_quizzes       ON quiz.quizzes;
DROP POLICY IF EXISTS anon_read_stops         ON quiz.stops;
DROP POLICY IF EXISTS anon_read_activities    ON quiz.activities;

-- Overflødige (pin_session_stops dækker allerede) og afhænger af sessions-læsning
DROP POLICY IF EXISTS kunde_kan_laese_stop     ON quiz.stops;
DROP POLICY IF EXISTS kunde_kan_opdatere_stop  ON quiz.stops;
DROP POLICY IF EXISTS kunde_kan_oprette_stop   ON quiz.stops;
DROP POLICY IF EXISTS kunde_kan_slette_stop    ON quiz.stops;

-- Session-id'er er login-nøgler: må aldrig kunne læses direkte
REVOKE SELECT ON quiz.sessions FROM anon;
ALTER TABLE quiz.sessions ENABLE ROW LEVEL SECURITY;

-- Gammel PIN-pr.-quiz er afløst af PIN pr. kunde
UPDATE quiz.quizzes SET pin_hash = NULL, pin_expires_at = NULL
 WHERE pin_hash IS NOT NULL OR pin_expires_at IS NOT NULL;

-- Realtime på submissions er ikke længere nødvendig (scoreboard bruger RPC)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication_tables
              WHERE pubname = 'supabase_realtime' AND schemaname = 'quiz' AND tablename = 'submissions') THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE quiz.submissions;
  END IF;
END $$;

-- Billed-bucket: kun billeder, max 5 MB
UPDATE storage.buckets
   SET file_size_limit = 5242880,
       allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/gif']
 WHERE id = 'quiz-uploads';

ALTER TABLE quiz.stops ALTER COLUMN radius_m SET DEFAULT 15;

-- ---------------------------------------------------------------------
-- DEL 2: Runder + foto-status
-- ---------------------------------------------------------------------
ALTER TABLE quiz.quizzes     ADD COLUMN IF NOT EXISTS round_no int NOT NULL DEFAULT 1;
ALTER TABLE quiz.submissions ADD COLUMN IF NOT EXISTS round_no int NOT NULL DEFAULT 1;
ALTER TABLE quiz.submissions ADD COLUMN IF NOT EXISTS status   text NOT NULL DEFAULT 'ok';
ALTER TABLE quiz.submissions DROP CONSTRAINT IF EXISTS submissions_status_check;
ALTER TABLE quiz.submissions ADD CONSTRAINT submissions_status_check
  CHECK (status IN ('ok','pending','rejected'));

-- Fjern evt. gammel unik begrænsning på (team_id, activity_id) - ellers kan
-- et hold ikke svare igen i runde 2
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.conname
      FROM pg_constraint c
     WHERE c.conrelid = 'quiz.submissions'::regclass AND c.contype = 'u'
       AND (SELECT array_agg(a.attname::text ORDER BY a.attname)
              FROM pg_attribute a
             WHERE a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)) = ARRAY['activity_id','team_id']
  LOOP
    EXECUTE format('ALTER TABLE quiz.submissions DROP CONSTRAINT %I', r.conname);
  END LOOP;

  FOR r IN
    SELECT i.indexrelid::regclass::text AS idx
      FROM pg_index i
     WHERE i.indrelid = 'quiz.submissions'::regclass AND i.indisunique AND NOT i.indisprimary
       AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
       AND (SELECT array_agg(a.attname::text ORDER BY a.attname)
              FROM pg_attribute a
             WHERE a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey::int2[])) = ARRAY['activity_id','team_id']
  LOOP
    EXECUTE format('DROP INDEX %s', r.idx);
  END LOOP;
END $$;

-- ét svar pr. hold pr. opgave pr. runde
CREATE UNIQUE INDEX IF NOT EXISTS submissions_team_activity_round_uq
  ON quiz.submissions (team_id, activity_id, round_no);

-- Starttid pr. hold pr. runde (bruges til tid på scoreboard)
CREATE TABLE IF NOT EXISTS quiz.team_runs (
  team_id    uuid        NOT NULL REFERENCES quiz.teams(id) ON DELETE CASCADE,
  round_no   int         NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (team_id, round_no)
);
ALTER TABLE quiz.team_runs ENABLE ROW LEVEL SECURITY;   -- kun via RPC

-- ---------------------------------------------------------------------
-- DEL 3: Beskyt quizzes mod direkte ændring af status/ejer/runde
--        (status skifter via set_quiz_status, så runder og krav passer)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION quiz.guard_quiz_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF current_setting('quiz.bypass_guard', true) = '1' THEN RETURN NEW; END IF;
  IF session_user IN ('postgres', 'supabase_admin') THEN RETURN NEW; END IF;      -- SQL Editor
  IF quiz.check_session_is_admin() OR auth.role() IN ('authenticated', 'service_role') THEN
    RETURN NEW;
  END IF;
  IF NEW.status       IS DISTINCT FROM OLD.status
  OR NEW.customer_id  IS DISTINCT FROM OLD.customer_id
  OR NEW.owner_id     IS DISTINCT FROM OLD.owner_id
  OR NEW.round_no     IS DISTINCT FROM OLD.round_no
  OR NEW.paid_at      IS DISTINCT FROM OLD.paid_at
  OR NEW.delete_after IS DISTINCT FROM OLD.delete_after THEN
    RAISE EXCEPTION 'Ikke tilladt: status, kunde og betaling kan kun ændres af systemet/admin';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_guard_quiz_update ON quiz.quizzes;
CREATE TRIGGER trg_guard_quiz_update
  BEFORE UPDATE ON quiz.quizzes
  FOR EACH ROW EXECUTE FUNCTION quiz.guard_quiz_update();

-- ---------------------------------------------------------------------
-- DEL 4: PIN pr. kunde - server-side bcrypt
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION quiz.set_customer_pin(p_customer_id uuid, p_pin text, p_expires timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  IF p_pin IS NULL OR p_pin !~ '^[0-9]{6,8}$' THEN
    RAISE EXCEPTION 'PIN skal være 6-8 cifre';
  END IF;
  UPDATE quiz.customers
     SET pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf')),
         pin_expires_at = p_expires
   WHERE id = p_customer_id;
  -- ny PIN = gamle logins ugyldige
  DELETE FROM quiz.sessions WHERE customer_id = p_customer_id;
END $$;

-- Kaldes KUN af Edge Function (service role). Understøtter gamle SHA-256 hashes
-- og opgraderer dem til bcrypt ved første vellykkede login.
CREATE OR REPLACE FUNCTION quiz.verify_customer_pin(p_customer_id uuid, p_pin text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE h text;
BEGIN
  SELECT pin_hash INTO h FROM quiz.customers WHERE id = p_customer_id;
  IF h IS NULL THEN RETURN false; END IF;
  IF h LIKE '$2%' THEN
    RETURN h = extensions.crypt(p_pin, h);
  END IF;
  IF h = encode(extensions.digest(p_pin, 'sha256'), 'hex') THEN
    UPDATE quiz.customers SET pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf'))
     WHERE id = p_customer_id;
    RETURN true;
  END IF;
  RETURN false;
END $$;
REVOKE EXECUTE ON FUNCTION quiz.verify_customer_pin(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION quiz.verify_customer_pin(uuid, text) TO service_role;

-- "Find mit login" på forsiden (erstatter den åbne customers-policy)
CREATE OR REPLACE FUNCTION quiz.find_login(p_email text)
RETURNS TABLE(customer_id uuid, customer_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT c.id, c.name FROM quiz.customers c
   WHERE lower(c.email) = lower(trim(p_email)) AND c.pin_hash IS NOT NULL
   LIMIT 1;
$$;

-- Kundens eget navn (kunder må ikke læse customers-tabellen)
CREATE OR REPLACE FUNCTION quiz.get_my_customer()
RETURNS TABLE(customer_id uuid, customer_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT c.id, c.name
    FROM quiz.sessions s JOIN quiz.customers c ON c.id = s.customer_id
   WHERE s.id = quiz.get_session_id() AND s.expires_at > now();
$$;

CREATE OR REPLACE FUNCTION quiz.end_session()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = quiz, public AS $$
  DELETE FROM quiz.sessions WHERE id = quiz.get_session_id();
$$;

-- ---------------------------------------------------------------------
-- DEL 5: Spiller-RPC'er (hold-token er "adgangskortet")
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS quiz.get_team_by_token(text);
CREATE FUNCTION quiz.get_team_by_token(p_token text)
RETURNS TABLE(team_id uuid, team_name text, quiz_id uuid, points int,
              quiz_title text, quiz_description text, quiz_status text,
              stop_order text, round_no int, started_at timestamptz, is_test boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT t.id, t.name, t.quiz_id,
         COALESCE((SELECT SUM(s.points) FROM quiz.submissions s
                    WHERE s.team_id = t.id AND s.round_no = q.round_no AND s.status = 'ok'), 0)::int,
         q.title, q.description, q.status, q.stop_order, q.round_no,
         (SELECT tr.started_at FROM quiz.team_runs tr
           WHERE tr.team_id = t.id AND tr.round_no = q.round_no),
         (t.name = '🧪 Testhold')
    FROM quiz.teams t JOIN quiz.quizzes q ON q.id = t.quiz_id
   WHERE t.token = p_token;
$$;

DROP FUNCTION IF EXISTS quiz.get_team_submissions(text);
CREATE FUNCTION quiz.get_team_submissions(p_token text)
RETURNS TABLE(activity_id uuid, is_correct boolean, points int, status text, submitted_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT sub.activity_id, sub.is_correct, sub.points, sub.status, sub.created_at
    FROM quiz.submissions sub
    JOIN quiz.teams   t ON t.id = sub.team_id
    JOIN quiz.quizzes q ON q.id = t.quiz_id
   WHERE t.token = p_token AND sub.round_no = q.round_no
   ORDER BY sub.created_at;
$$;

-- Stop + opgaver. I LÅST rækkefølge sendes kun stop til og med det aktuelle -
-- fremtidige stop (og deres spørgsmål) kan ikke hentes på forhånd.
-- Kladde-quizzer kan kun åbnes af testholdet.
DROP FUNCTION IF EXISTS quiz.get_quiz_stops(text);
CREATE FUNCTION quiz.get_quiz_stops(p_token text)
RETURNS TABLE(stop_id uuid, stop_name text, sort int, lat double precision, lng double precision,
              radius_m int, activity_id uuid, activity_type text, activity_question text,
              activity_media_url text, activity_options jsonb, activity_points int,
              activity_approval text, quiz_mode text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  WITH me AS (
    SELECT t.id AS team_id, t.quiz_id, q.stop_order, q.round_no
      FROM quiz.teams t JOIN quiz.quizzes q ON q.id = t.quiz_id
     WHERE t.token = p_token
       AND (q.status IN ('testing','aktiv') OR t.name = '🧪 Testhold')
  ),
  ordered AS (
    SELECT s.id, s.name, s.lat, s.lng, s.radius_m,
           (ROW_NUMBER() OVER (ORDER BY s.sort, s.created_at, s.id) - 1)::int AS ord
      FROM quiz.stops s
     WHERE s.quiz_id = (SELECT quiz_id FROM me)
  ),
  state AS (
    SELECT o.ord,
           NOT EXISTS (
             SELECT 1 FROM quiz.activities a
              WHERE a.stop_id = o.id
                AND NOT EXISTS (SELECT 1 FROM quiz.submissions sub, me
                                 WHERE sub.activity_id = a.id
                                   AND sub.team_id = me.team_id
                                   AND sub.round_no = me.round_no)
           ) AS done
      FROM ordered o
  ),
  cutoff AS (
    SELECT COALESCE(MIN(ord) FILTER (WHERE NOT done), 2147483647) AS first_open FROM state
  )
  SELECT o.id, o.name, o.ord, o.lat, o.lng, o.radius_m,
         a.id, a.type, a.question, a.media_url, a.options, a.points, a.approval,
         me.stop_order
    FROM me, cutoff, ordered o
    LEFT JOIN quiz.activities a ON a.stop_id = o.id
   WHERE me.stop_order <> 'laast' OR o.ord <= cutoff.first_open
   ORDER BY o.ord, a.sort NULLS LAST, a.id;
$$;

CREATE OR REPLACE FUNCTION quiz.start_team_run(p_token text)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_team uuid; v_round int; v_started timestamptz;
BEGIN
  SELECT t.id, q.round_no INTO v_team, v_round
    FROM quiz.teams t JOIN quiz.quizzes q ON q.id = t.quiz_id
   WHERE t.token = p_token AND (q.status IN ('testing','aktiv') OR t.name = '🧪 Testhold');
  IF v_team IS NULL THEN RETURN NULL; END IF;
  INSERT INTO quiz.team_runs (team_id, round_no) VALUES (v_team, v_round) ON CONFLICT DO NOTHING;
  SELECT started_at INTO v_started FROM quiz.team_runs WHERE team_id = v_team AND round_no = v_round;
  RETURN v_started;
END $$;

-- ---------------------------------------------------------------------
-- DEL 6: Scoreboard (offentligt, men kun det der må ses)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION quiz.get_scoreboard(p_quiz_id uuid, p_round int DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE
  v_q quiz.quizzes; v_r int; v_stops int; v_acts int; v_teams jsonb; v_photos jsonb;
BEGIN
  SELECT * INTO v_q FROM quiz.quizzes
   WHERE id = p_quiz_id AND status IN ('testing','aktiv','arkiveret');
  IF NOT FOUND THEN RETURN NULL; END IF;

  v_r := LEAST(GREATEST(COALESCE(p_round, v_q.round_no), 1), v_q.round_no);
  SELECT count(*)::int INTO v_stops FROM quiz.stops WHERE quiz_id = v_q.id;
  SELECT count(*)::int INTO v_acts
    FROM quiz.activities a JOIN quiz.stops s ON s.id = a.stop_id WHERE s.quiz_id = v_q.id;

  SELECT COALESCE(jsonb_agg(
           jsonb_build_object('name', x.name, 'points', x.points, 'correct', x.correct,
                              'answered', x.answered, 'finished', x.finished,
                              'duration_s', x.duration_s)
           ORDER BY x.points DESC, x.finished DESC, x.duration_s ASC NULLS LAST, x.name),
         '[]'::jsonb)
    INTO v_teams
    FROM (
      SELECT t.name,
             COALESCE(SUM(s.points) FILTER (WHERE s.status = 'ok'), 0)::int AS points,
             (COUNT(*) FILTER (WHERE s.status = 'ok' AND s.is_correct))::int AS correct,
             COUNT(s.id)::int AS answered,
             (v_acts > 0 AND COUNT(s.id) >= v_acts) AS finished,
             CASE WHEN COUNT(s.id) > 0 THEN
               EXTRACT(EPOCH FROM (MAX(s.created_at) - COALESCE(tr.started_at, MIN(s.created_at))))::int
             END AS duration_s
        FROM quiz.teams t
        LEFT JOIN quiz.submissions s ON s.team_id = t.id AND s.round_no = v_r
        LEFT JOIN quiz.team_runs  tr ON tr.team_id = t.id AND tr.round_no = v_r
       WHERE t.quiz_id = v_q.id AND t.name <> '🧪 Testhold'
       GROUP BY t.id, t.name, tr.started_at
    ) x;

  SELECT COALESCE(jsonb_agg(
           jsonb_build_object('team', t.name, 'url', s.answer #>> '{}',
                              'question', a.question, 'at', s.created_at)
           ORDER BY s.created_at DESC), '[]'::jsonb)
    INTO v_photos
    FROM quiz.submissions s
    JOIN quiz.teams      t  ON t.id = s.team_id
    JOIN quiz.activities a  ON a.id = s.activity_id
    JOIN quiz.stops      st ON st.id = a.stop_id
   WHERE st.quiz_id = v_q.id AND s.round_no = v_r AND a.type = 'foto'
     AND s.status = 'ok' AND t.name <> '🧪 Testhold';

  RETURN jsonb_build_object(
    'quiz', jsonb_build_object('id', v_q.id, 'title', v_q.title, 'status', v_q.status,
                               'round_no', v_q.round_no),
    'round', v_r,
    'rounds', (SELECT COALESCE(jsonb_agg(g), '[]'::jsonb) FROM generate_series(1, v_q.round_no) g),
    'stops', v_stops, 'activities', v_acts,
    'teams', v_teams, 'photos', v_photos);
END $$;

-- ---------------------------------------------------------------------
-- DEL 7: Quizmaster-RPC'er (admin eller kunde der ejer løbet)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION quiz.set_quiz_status(p_quiz_id uuid, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE
  v_q quiz.quizzes; v_admin boolean; v_teams int; v_acts int; v_missing int; v_round int;
  v_ids uuid[];
BEGIN
  IF NOT (quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  v_admin := quiz.check_session_is_admin() OR auth.role() = 'authenticated';

  IF p_status NOT IN ('kladde','testing','aktiv','arkiveret') THEN
    RAISE EXCEPTION 'Ugyldig status';
  END IF;
  IF NOT v_admin AND p_status NOT IN ('aktiv','arkiveret') THEN
    RAISE EXCEPTION 'Kun admin kan sætte denne status';
  END IF;

  SELECT * INTO v_q FROM quiz.quizzes WHERE id = p_quiz_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Løb ikke fundet'; END IF;
  IF v_q.status = p_status THEN
    RETURN jsonb_build_object('status', v_q.status, 'round_no', v_q.round_no);
  END IF;

  IF p_status = 'aktiv' THEN
    SELECT count(*)::int INTO v_teams FROM quiz.teams
     WHERE quiz_id = v_q.id AND name <> '🧪 Testhold';
    SELECT count(*)::int INTO v_acts FROM quiz.activities a
      JOIN quiz.stops s ON s.id = a.stop_id WHERE s.quiz_id = v_q.id;
    SELECT count(*)::int INTO v_missing FROM quiz.activities a
      JOIN quiz.stops s ON s.id = a.stop_id
     WHERE s.quiz_id = v_q.id AND a.type IN ('mc','tekst','tal')
       AND NOT EXISTS (SELECT 1 FROM quiz.answer_keys k WHERE k.activity_id = a.id);
    IF v_acts = 0    THEN RAISE EXCEPTION 'Tilføj mindst ét stop med en opgave først'; END IF;
    IF v_teams = 0   THEN RAISE EXCEPTION 'Opret mindst ét hold først'; END IF;
    IF v_missing > 0 THEN RAISE EXCEPTION '% opgave(r) mangler en fasit - ret dem først', v_missing; END IF;
  END IF;

  v_round := v_q.round_no;
  IF p_status = 'aktiv' AND v_q.status = 'arkiveret' THEN
    v_round := v_q.round_no + 1;            -- genaktivering = ny runde
  END IF;

  PERFORM set_config('quiz.bypass_guard', '1', true);
  UPDATE quiz.quizzes SET status = p_status, round_no = v_round WHERE id = v_q.id;
  PERFORM set_config('quiz.bypass_guard', '0', true);

  IF p_status = 'aktiv' THEN                -- ryd testhold når det går live
    SELECT COALESCE(array_agg(id), '{}'::uuid[]) INTO v_ids
      FROM quiz.teams WHERE quiz_id = v_q.id AND name = '🧪 Testhold';
    DELETE FROM quiz.team_positions WHERE team_id = ANY (v_ids);
    DELETE FROM quiz.submissions    WHERE team_id = ANY (v_ids);
    DELETE FROM quiz.teams          WHERE id      = ANY (v_ids);
  END IF;

  RETURN jsonb_build_object('status', p_status, 'round_no', v_round);
END $$;

CREATE OR REPLACE FUNCTION quiz.create_test_team(p_quiz_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_token text; v_ids uuid[];
BEGIN
  IF NOT (quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  SELECT COALESCE(array_agg(id), '{}'::uuid[]) INTO v_ids
    FROM quiz.teams WHERE quiz_id = p_quiz_id AND name = '🧪 Testhold';
  DELETE FROM quiz.team_positions WHERE team_id = ANY (v_ids);
  DELETE FROM quiz.submissions    WHERE team_id = ANY (v_ids);
  DELETE FROM quiz.teams          WHERE id      = ANY (v_ids);
  v_token := 'test-' || substr(md5(random()::text || clock_timestamp()::text), 1, 12);
  INSERT INTO quiz.teams (quiz_id, name, token) VALUES (p_quiz_id, '🧪 Testhold', v_token);
  RETURN v_token;
END $$;

CREATE OR REPLACE FUNCTION quiz.get_pending_photos(p_quiz_id uuid)
RETURNS TABLE(submission_id uuid, team_name text, url text, question text, points int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF NOT (quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  RETURN QUERY
    SELECT s.id, t.name, s.answer #>> '{}', a.question, a.points
      FROM quiz.submissions s
      JOIN quiz.teams      t  ON t.id  = s.team_id
      JOIN quiz.activities a  ON a.id  = s.activity_id
      JOIN quiz.stops      st ON st.id = a.stop_id
      JOIN quiz.quizzes    qz ON qz.id = st.quiz_id
     WHERE st.quiz_id = p_quiz_id AND s.round_no = qz.round_no AND s.status = 'pending'
     ORDER BY s.created_at;
END $$;

CREATE OR REPLACE FUNCTION quiz.review_submission(p_submission_id uuid, p_approve boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_quiz uuid; v_points int;
BEGIN
  SELECT st.quiz_id, a.points INTO v_quiz, v_points
    FROM quiz.submissions s
    JOIN quiz.activities a  ON a.id  = s.activity_id
    JOIN quiz.stops      st ON st.id = a.stop_id
   WHERE s.id = p_submission_id;
  IF v_quiz IS NULL THEN RAISE EXCEPTION 'Besvarelse ikke fundet'; END IF;
  IF NOT (quiz.check_session(v_quiz) OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  IF p_approve THEN
    UPDATE quiz.submissions SET status = 'ok', is_correct = true, points = COALESCE(v_points, 0)
     WHERE id = p_submission_id;
  ELSE
    UPDATE quiz.submissions SET status = 'rejected', is_correct = false, points = 0
     WHERE id = p_submission_id;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- DEL 8: Rettigheder til Edge Functions (service role)
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA quiz TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA quiz TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA quiz TO service_role;

-- ---------------------------------------------------------------------
-- DEL 9 (valgfri kontrol): kør bagefter og se at listen er kort
-- ---------------------------------------------------------------------
-- SELECT tablename, policyname, roles FROM pg_policies
--  WHERE schemaname = 'quiz' AND 'anon' = ANY (roles) ORDER BY tablename;
-- Forventet: kun 'errors' (anon_insert_errors) - alt andet er lukket.
