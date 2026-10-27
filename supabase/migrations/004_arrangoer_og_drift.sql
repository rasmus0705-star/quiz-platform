-- =====================================================================
-- 004_arrangoer_og_drift.sql                (kør i Supabase → SQL Editor)
-- Kræver 001, 002 og 003. Kan genkøres.
--
--   1. Live-kort: arrangøren kan se holdenes seneste position
--   2. Afsløring: skjul rangliste for offentligheden, indtil quizmasteren afslører vinderen
--   3. Planlagt åbning/lukning af et løb
--   4. Bestillinger: offentlig bestil-formular + admin-håndtering
--   5. Kunde kan selv skifte PIN
--   6. Admin: statistik, fejl, eksport (backup), slet kunde
--   7. Grænser pr. kunde/løb (misbrugsbeskyttelse)
-- =====================================================================

-- ---------------------------------------------------------------------
-- DEL 0: nye kolonner
-- ---------------------------------------------------------------------
-- Oprettes også i 003; her igen, så 004 kan køres alene, og "column data_purged_at does not exist" aldrig opstår
ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS data_purged_at      timestamptz;
ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS delete_after        timestamptz;
ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS hide_results        boolean NOT NULL DEFAULT false;
ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS results_revealed_at timestamptz;
ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS opens_at            timestamptz;
ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS closes_at           timestamptz;

-- Afbryd test: fjerner testholdet og alt dets data (genoptag = åbn testholdets link igen; "Test løbet" starter altid forfra)
CREATE OR REPLACE FUNCTION quiz.end_test_team(p_quiz_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_ids uuid[];
BEGIN
  IF NOT (quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  SELECT COALESCE(array_agg(id), '{}'::uuid[]) INTO v_ids FROM quiz.teams WHERE quiz_id = p_quiz_id AND name = '🧪 Testhold';
  DELETE FROM quiz.team_positions WHERE team_id = ANY (v_ids);
  DELETE FROM quiz.submissions    WHERE team_id = ANY (v_ids);
  DELETE FROM quiz.teams          WHERE id      = ANY (v_ids);
END $$;

-- Kunden sletter sit eget løb (kun kladde eller afsluttet – aldrig et løb der kører).
-- Fotos i Storage skal ryddes FØR via purge-data; databasen kan ikke slette filer.
CREATE OR REPLACE FUNCTION quiz.delete_my_quiz(p_quiz_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_status text;
BEGIN
  IF NOT (quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  SELECT status INTO v_status FROM quiz.quizzes WHERE id = p_quiz_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Løbet findes ikke'; END IF;
  IF v_status = 'aktiv' THEN RAISE EXCEPTION 'Afslut løbet, før du sletter det'; END IF;
  PERFORM quiz.delete_quiz_cascade(p_quiz_id);
END $$;

-- ---------------------------------------------------------------------
-- DEL 8: Foto-opgaver uden rigtigt svar – quizmasteren giver point (0..max)
-- ---------------------------------------------------------------------
ALTER TABLE quiz.submissions ADD COLUMN IF NOT EXISTS judged_at timestamptz;

-- Foto-opgaver kan nu også være 'skjul' (kun quizmasteren ser billedet)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'quiz.activities'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ~* 'approval'
  LOOP EXECUTE format('ALTER TABLE quiz.activities DROP CONSTRAINT %I', r.conname); END LOOP;
  ALTER TABLE quiz.activities ADD CONSTRAINT activities_approval_check
    CHECK (approval IS NULL OR approval IN ('auto','manuel','vis_kun','skjul'));
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'approval-begrænsning uændret: %', SQLERRM;
END $$;

-- Afløser review_submission for foto: god/afvist ELLER en karakter. p_points = NULL → afvist.
CREATE OR REPLACE FUNCTION quiz.score_submission(p_submission_id uuid, p_points int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_quiz uuid; v_max int;
BEGIN
  SELECT s.quiz_id, a.points INTO v_quiz, v_max
    FROM quiz.submissions sb
    JOIN quiz.activities a ON a.id = sb.activity_id
    JOIN quiz.stops s      ON s.id = a.stop_id
   WHERE sb.id = p_submission_id;
  IF v_quiz IS NULL THEN RAISE EXCEPTION 'Besvarelsen findes ikke'; END IF;
  IF NOT (quiz.check_session(v_quiz) OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  IF p_points IS NULL THEN
    UPDATE quiz.submissions SET status = 'rejected', is_correct = false, points = 0, judged_at = now() WHERE id = p_submission_id;
  ELSE
    IF p_points < 0 OR p_points > GREATEST(v_max, 0) THEN RAISE EXCEPTION 'Point skal være mellem 0 og %', GREATEST(v_max, 0); END IF;
    UPDATE quiz.submissions SET status = 'ok', is_correct = (p_points > 0), points = p_points, judged_at = now() WHERE id = p_submission_id;
  END IF;
END $$;

-- Alle holdets fotos i runden – til bedømmelse og til fotovæggen
CREATE OR REPLACE FUNCTION quiz.get_photo_wall(p_quiz_id uuid, p_round int DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_q quiz.quizzes; v_r int; v_mgr boolean;
BEGIN
  SELECT * INTO v_q FROM quiz.quizzes WHERE id = p_quiz_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_mgr := quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated';
  v_r := LEAST(GREATEST(COALESCE(p_round, v_q.round_no), 1), v_q.round_no);
  RETURN jsonb_build_object('round', v_r, 'manager', v_mgr,
    'photos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', sb.id, 'team', t.name, 'question', a.question, 'stop', st.name,
                                          'url', sb.answer #>> '{}', 'points', sb.points, 'max', a.points,
                                          'status', sb.status, 'judged', sb.judged_at IS NOT NULL, 'at', sb.created_at)
               ORDER BY sb.created_at)
        FROM quiz.submissions sb
        JOIN quiz.activities a ON a.id = sb.activity_id
        JOIN quiz.stops st     ON st.id = a.stop_id
        JOIN quiz.teams t      ON t.id = sb.team_id
       WHERE st.quiz_id = p_quiz_id AND sb.round_no = v_r AND a.type = 'foto'
         AND t.name <> '🧪 Testhold'
         AND (sb.answer #>> '{}') LIKE 'https://%'
         AND (v_mgr OR (sb.status = 'ok' AND a.approval <> 'skjul'))), '[]'::jsonb));
END $$;

-- ---------------------------------------------------------------------
-- DEL 9: Skabelon-løb (færdige løb kunden kan kopiere)
-- ---------------------------------------------------------------------
ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS is_template  boolean NOT NULL DEFAULT false;
ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS template_tag text;
CREATE INDEX IF NOT EXISTS quizzes_template ON quiz.quizzes (is_template) WHERE is_template;

-- Skabeloner ejes af admin (customer_id IS NULL) og kan ses af alle kunder
CREATE OR REPLACE FUNCTION quiz.list_templates()
RETURNS TABLE(id uuid, title text, description text, theme text, template_tag text, stops int, activities int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT q.id, q.title, q.description, q.theme, q.template_tag,
         (SELECT count(*)::int FROM quiz.stops s WHERE s.quiz_id = q.id),
         (SELECT count(*)::int FROM quiz.activities a JOIN quiz.stops s ON s.id = a.stop_id WHERE s.quiz_id = q.id)
    FROM quiz.quizzes q
   WHERE q.is_template
   ORDER BY q.template_tag NULLS LAST, q.title;
$$;

-- Kunden tager en kopi af en skabelon. Kopien bliver kundens egen kladde (aldrig selv en skabelon).
CREATE OR REPLACE FUNCTION quiz.copy_template(p_template_id uuid, p_title text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_src quiz.quizzes; v_new uuid := gen_random_uuid(); v_cust uuid; s record; a record; v_ns uuid; v_na uuid;
BEGIN
  SELECT customer_id INTO v_cust FROM quiz.sessions WHERE id = quiz.get_session_id() AND expires_at > now();
  IF v_cust IS NULL AND NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Du skal være logget ind';
  END IF;
  SELECT * INTO v_src FROM quiz.quizzes WHERE id = p_template_id AND is_template;
  IF NOT FOUND THEN RAISE EXCEPTION 'Skabelonen findes ikke'; END IF;

  INSERT INTO quiz.quizzes (id, title, description, status, stop_order, customer_id, mode, timer_min, theme, theme_texts, hide_results)
  VALUES (v_new, COALESCE(NULLIF(btrim(p_title), ''), v_src.title), v_src.description, 'kladde', v_src.stop_order,
          v_cust, v_src.mode, v_src.timer_min, v_src.theme, v_src.theme_texts, v_src.hide_results);

  FOR s IN SELECT * FROM quiz.stops WHERE quiz_id = p_template_id ORDER BY sort, created_at, id LOOP
    INSERT INTO quiz.stops (quiz_id, name, lat, lng, radius_m, sort)
    VALUES (v_new, s.name, s.lat, s.lng, s.radius_m, s.sort) RETURNING id INTO v_ns;
    FOR a IN SELECT * FROM quiz.activities WHERE stop_id = s.id ORDER BY sort NULLS LAST, id LOOP
      INSERT INTO quiz.activities (stop_id, sort, type, question, options, points, time_limit_s, hint, media_url, approval)
      VALUES (v_ns, a.sort, a.type, a.question, a.options, a.points, a.time_limit_s, a.hint, a.media_url, a.approval)
      RETURNING id INTO v_na;
      INSERT INTO quiz.answer_keys (activity_id, correct, tolerance)
      SELECT v_na, k.correct, k.tolerance FROM quiz.answer_keys k WHERE k.activity_id = a.id;
    END LOOP;
  END LOOP;
  RETURN v_new;
END $$;

-- Admin gør et løb til skabelon (eller fjerner mærket igen)
CREATE OR REPLACE FUNCTION quiz.set_template(p_quiz_id uuid, p_is boolean, p_tag text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  IF p_tag IS NOT NULL AND p_tag !~ '^.{0,40}$' THEN RAISE EXCEPTION 'Mærkat er for langt'; END IF;
  PERFORM set_config('quiz.bypass_guard', '1', true);
  UPDATE quiz.quizzes SET is_template = p_is, template_tag = nullif(btrim(coalesce(p_tag, '')), '') WHERE id = p_quiz_id;
  PERFORM set_config('quiz.bypass_guard', '0', true);
END $$;

-- Skabeloner må ikke tælle med i kundens løb-liste eller i grænsen på 100
CREATE OR REPLACE FUNCTION quiz.trg_quota() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_quiz uuid;
BEGIN
  IF TG_TABLE_NAME = 'quizzes' THEN
    IF NEW.customer_id IS NOT NULL AND (SELECT count(*) FROM quiz.quizzes WHERE customer_id = NEW.customer_id AND NOT is_template) >= 100 THEN
      RAISE EXCEPTION 'Du har nået grænsen på 100 løb – slet gamle løb eller kontakt os';
    END IF;
  ELSIF TG_TABLE_NAME = 'teams' THEN
    IF NEW.name <> '🧪 Testhold' AND (SELECT count(*) FROM quiz.teams WHERE quiz_id = NEW.quiz_id AND name <> '🧪 Testhold') >= 200 THEN
      RAISE EXCEPTION 'Et løb kan have højst 200 hold';
    END IF;
  ELSIF TG_TABLE_NAME = 'stops' THEN
    IF (SELECT count(*) FROM quiz.stops WHERE quiz_id = NEW.quiz_id) >= 100 THEN
      RAISE EXCEPTION 'Et løb kan have højst 100 poster';
    END IF;
  ELSIF TG_TABLE_NAME = 'activities' THEN
    SELECT quiz_id INTO v_quiz FROM quiz.stops WHERE id = NEW.stop_id;
    IF (SELECT count(*) FROM quiz.activities a JOIN quiz.stops s ON s.id = a.stop_id WHERE s.quiz_id = v_quiz) >= 300 THEN
      RAISE EXCEPTION 'Et løb kan have højst 300 opgaver';
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- ---------------------------------------------------------------------
-- DEL 1: Live-kort (kun quizmaster/admin) – seneste position pr. hold
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION quiz.get_team_positions(p_quiz_id uuid)
RETURNS TABLE(team_name text, lat float8, lng float8, accuracy_m int, recorded_at timestamptz, answered int, total int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_round int; v_total int;
BEGIN
  IF NOT (quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  SELECT qz.round_no INTO v_round FROM quiz.quizzes qz WHERE qz.id = p_quiz_id;
  SELECT count(*)::int INTO v_total
    FROM quiz.activities a JOIN quiz.stops s ON s.id = a.stop_id WHERE s.quiz_id = p_quiz_id;
  RETURN QUERY
    SELECT t.name, p.lat, p.lng, p.accuracy_m, p.recorded_at,
           (SELECT count(*)::int FROM quiz.submissions sb WHERE sb.team_id = t.id AND sb.round_no = v_round),
           v_total
      FROM quiz.teams t
      JOIN quiz.team_positions p ON p.team_id = t.id
     WHERE t.quiz_id = p_quiz_id AND t.name <> '🧪 Testhold'
       AND p.recorded_at > now() - interval '12 hours'
     ORDER BY t.name;
END $$;

-- ---------------------------------------------------------------------
-- DEL 2: Afsløring af vinderen
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION quiz.get_scoreboard(p_quiz_id uuid, p_round int DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE
  v_q quiz.quizzes; v_r int; v_stops int; v_acts int; v_teams jsonb; v_photos jsonb; v_mgr boolean; v_hidden boolean;
BEGIN
  SELECT * INTO v_q FROM quiz.quizzes
   WHERE id = p_quiz_id AND status IN ('testing','aktiv','arkiveret');
  IF NOT FOUND THEN RETURN NULL; END IF;
  -- Skjult-tilstand: offentligheden får hverken point, rækkefølge eller tid – kun holdnavne og fremdrift. Quizmasteren ser altid alt.
  v_mgr := quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated';
  v_hidden := v_q.hide_results AND v_q.results_revealed_at IS NULL AND NOT v_mgr;

  v_r := LEAST(GREATEST(COALESCE(p_round, v_q.round_no), 1), v_q.round_no);
  SELECT count(*)::int INTO v_stops FROM quiz.stops WHERE quiz_id = v_q.id;
  SELECT count(*)::int INTO v_acts
    FROM quiz.activities a JOIN quiz.stops s ON s.id = a.stop_id WHERE s.quiz_id = v_q.id;

  SELECT COALESCE(jsonb_agg(
           CASE WHEN v_hidden
                THEN jsonb_build_object('name', x.name, 'answered', x.answered, 'finished', x.finished)
                ELSE jsonb_build_object('name', x.name, 'points', x.points, 'correct', x.correct,
                                        'answered', x.answered, 'finished', x.finished,
                                        'duration_s', x.duration_s) END
           ORDER BY (CASE WHEN v_hidden THEN 0 ELSE x.points END) DESC,
                    (CASE WHEN v_hidden THEN false ELSE x.finished END) DESC,
                    (CASE WHEN v_hidden THEN NULL ELSE x.duration_s END) ASC NULLS LAST, x.name),
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
    'theme', v_q.theme,
    'round', v_r,
    'rounds', (SELECT COALESCE(jsonb_agg(g), '[]'::jsonb) FROM generate_series(1, v_q.round_no) g),
    'stops', v_stops, 'activities', v_acts,
    'hide_results', v_q.hide_results, 'revealed', v_q.results_revealed_at IS NOT NULL, 'results_hidden', v_hidden,
    'teams', v_teams, 'photos', v_photos);
END $$;

-- Ny runde nulstiller afsløringen
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
  UPDATE quiz.quizzes
     SET status = p_status, round_no = v_round,
         -- GDPR: afsluttede løb slettes automatisk efter 90 dage; genaktivering stopper uret
         delete_after   = CASE WHEN p_status = 'arkiveret' THEN now() + interval '90 days'
                               WHEN p_status = 'aktiv'     THEN NULL ELSE delete_after END,
         data_purged_at = CASE WHEN p_status = 'aktiv'     THEN NULL ELSE data_purged_at END,
         results_revealed_at = CASE WHEN p_status = 'aktiv' THEN NULL ELSE results_revealed_at END
   WHERE id = v_q.id;
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

-- Quizmasteren afslører (true) eller skjuler igen (false)
CREATE OR REPLACE FUNCTION quiz.reveal_results(p_quiz_id uuid, p_reveal boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF NOT (quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  UPDATE quiz.quizzes SET results_revealed_at = CASE WHEN p_reveal THEN now() ELSE NULL END WHERE id = p_quiz_id;
END $$;

-- ---------------------------------------------------------------------
-- DEL 3: Planlagt åbning/lukning – holdets svar afvises uden for tidsrummet (testhold undtaget)
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS quiz.get_team_by_token(text);
CREATE FUNCTION quiz.get_team_by_token(p_token text)
RETURNS TABLE(team_id uuid, team_name text, quiz_id uuid, points int,
              quiz_title text, quiz_description text, quiz_status text,
              stop_order text, round_no int, started_at timestamptz, is_test boolean,
              quiz_theme text, quiz_theme_texts jsonb,
              quiz_opens_at timestamptz, quiz_closes_at timestamptz, server_now timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT t.id, t.name, t.quiz_id,
         COALESCE((SELECT SUM(s.points) FROM quiz.submissions s
                    WHERE s.team_id = t.id AND s.round_no = q.round_no AND s.status = 'ok'), 0)::int,
         q.title, q.description, q.status, q.stop_order, q.round_no,
         (SELECT tr.started_at FROM quiz.team_runs tr
           WHERE tr.team_id = t.id AND tr.round_no = q.round_no),
         (t.name = '🧪 Testhold'),
         q.theme, q.theme_texts, q.opens_at, q.closes_at, now()
    FROM quiz.teams t JOIN quiz.quizzes q ON q.id = t.quiz_id
   WHERE t.token = p_token;
$$;

CREATE OR REPLACE FUNCTION quiz.trg_submission_window() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_open timestamptz; v_close timestamptz; v_name text;
BEGIN
  SELECT q.opens_at, q.closes_at, t.name INTO v_open, v_close, v_name
    FROM quiz.teams t JOIN quiz.quizzes q ON q.id = t.quiz_id WHERE t.id = NEW.team_id;
  IF v_name IS DISTINCT FROM '🧪 Testhold' THEN
    IF v_open  IS NOT NULL AND now() < v_open  THEN RAISE EXCEPTION 'Løbet er ikke åbnet endnu'; END IF;
    IF v_close IS NOT NULL AND now() > v_close THEN RAISE EXCEPTION 'Løbet er lukket'; END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_submission_window ON quiz.submissions;
CREATE TRIGGER trg_submission_window BEFORE INSERT ON quiz.submissions
  FOR EACH ROW EXECUTE FUNCTION quiz.trg_submission_window();

-- ---------------------------------------------------------------------
-- DEL 4: Bestillinger
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS quiz.orders (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  org_name      text NOT NULL,
  contact_name  text NOT NULL,
  email         text NOT NULL,
  phone         text,
  event_type    text,
  expected_date date,
  message       text,
  plan          text NOT NULL DEFAULT 'start',
  amount_dkk    int  NOT NULL DEFAULT 0,
  status        text NOT NULL DEFAULT 'ny' CHECK (status IN ('ny','oprettet','afvist')),
  customer_id   uuid REFERENCES quiz.customers(id) ON DELETE SET NULL,
  consent_at    timestamptz NOT NULL,
  notes         text
);
ALTER TABLE quiz.orders ENABLE ROW LEVEL SECURITY;           -- kun via RPC
CREATE INDEX IF NOT EXISTS orders_email_time ON quiz.orders (lower(email), created_at);

-- Offentlig bestilling. p_website er en skjult "honningkrukke": udfyldes den, er det en robot → vi lader som om det lykkedes.
CREATE OR REPLACE FUNCTION quiz.submit_order(
  p_org text, p_name text, p_email text, p_phone text, p_event_type text,
  p_expected date, p_message text, p_consent boolean, p_website text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_mail text := lower(btrim(coalesce(p_email, '')));
BEGIN
  IF coalesce(btrim(p_website), '') <> '' THEN RETURN jsonb_build_object('ok', true); END IF;
  IF p_consent IS NOT TRUE THEN RAISE EXCEPTION 'Du skal acceptere behandlingen af dine oplysninger'; END IF;
  IF length(btrim(coalesce(p_org, ''))) < 2 OR length(p_org) > 120      THEN RAISE EXCEPTION 'Skriv navnet på foreningen eller virksomheden'; END IF;
  IF length(btrim(coalesce(p_name, ''))) < 2 OR length(p_name) > 120    THEN RAISE EXCEPTION 'Skriv dit navn'; END IF;
  IF v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' OR length(v_mail) > 200 THEN RAISE EXCEPTION 'Skriv en gyldig e-mailadresse'; END IF;
  IF length(coalesce(p_message, '')) > 2000 OR length(coalesce(p_phone, '')) > 40 OR length(coalesce(p_event_type, '')) > 80 THEN RAISE EXCEPTION 'En af teksterne er for lang'; END IF;
  IF (SELECT count(*) FROM quiz.orders WHERE lower(email) = v_mail AND created_at > now() - interval '24 hours') >= 3 THEN
    RAISE EXCEPTION 'Du har allerede sendt flere bestillinger i dag – vi vender tilbage hurtigst muligt';
  END IF;
  IF (SELECT count(*) FROM quiz.orders WHERE created_at > now() - interval '1 hour') >= 30 THEN
    RAISE EXCEPTION 'Der er travlt lige nu – prøv igen om lidt';
  END IF;
  INSERT INTO quiz.orders (org_name, contact_name, email, phone, event_type, expected_date, message, consent_at)
  VALUES (btrim(p_org), btrim(p_name), v_mail, nullif(btrim(p_phone), ''), nullif(btrim(p_event_type), ''), p_expected, nullif(btrim(p_message), ''), now());
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION quiz.list_orders() RETURNS SETOF quiz.orders
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  RETURN QUERY SELECT * FROM quiz.orders ORDER BY created_at DESC LIMIT 200;
END $$;

CREATE OR REPLACE FUNCTION quiz.set_order_status(p_order_id uuid, p_status text, p_notes text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  IF p_status NOT IN ('ny','oprettet','afvist') THEN RAISE EXCEPTION 'Ugyldig status'; END IF;
  UPDATE quiz.orders SET status = p_status, notes = COALESCE(p_notes, notes) WHERE id = p_order_id;
END $$;

-- Opretter en kunde ud fra en bestilling (kan kaldes igen uden at lave dubletter)
CREATE OR REPLACE FUNCTION quiz.create_customer_from_order(p_order_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE o quiz.orders; v_c uuid;
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  SELECT * INTO o FROM quiz.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Bestillingen findes ikke'; END IF;
  IF o.customer_id IS NOT NULL THEN RETURN o.customer_id; END IF;
  INSERT INTO quiz.customers (name, email, phone, company, notes)
  VALUES (o.contact_name, o.email, o.phone, o.org_name, 'Oprettet fra bestilling ' || to_char(o.created_at, 'YYYY-MM-DD') ||
          COALESCE(E'\n' || o.event_type, '') || COALESCE(E'\n' || o.message, ''))
  RETURNING id INTO v_c;
  UPDATE quiz.orders SET customer_id = v_c, status = 'oprettet' WHERE id = p_order_id;
  RETURN v_c;
END $$;

-- ---------------------------------------------------------------------
-- DEL 5: Kunden skifter selv PIN (true = skiftet, false = forkert nuværende PIN)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION quiz.change_my_pin(p_old text, p_new text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_sid uuid := quiz.get_session_id(); v_c uuid;
BEGIN
  SELECT customer_id INTO v_c FROM quiz.sessions
   WHERE id = v_sid AND expires_at > now() AND is_admin = false AND customer_id IS NOT NULL;
  IF v_c IS NULL THEN RAISE EXCEPTION 'Du er ikke logget ind som kunde'; END IF;
  IF p_new IS NULL OR p_new !~ '^[0-9]{6,8}$' THEN RAISE EXCEPTION 'Ny PIN skal være 6-8 cifre'; END IF;
  IF (SELECT count(*) FROM quiz.login_attempts WHERE target = 'chpin:' || v_c::text AND NOT success
        AND created_at > now() - interval '10 minutes') >= 5 THEN
    RAISE EXCEPTION 'For mange forkerte forsøg – vent lidt og prøv igen';
  END IF;
  IF NOT quiz.verify_customer_pin(v_c, coalesce(p_old, '')) THEN
    INSERT INTO quiz.login_attempts (target, success) VALUES ('chpin:' || v_c::text, false);
    RETURN false;
  END IF;
  UPDATE quiz.customers SET pin_hash = extensions.crypt(p_new, extensions.gen_salt('bf')) WHERE id = v_c;
  DELETE FROM quiz.sessions WHERE customer_id = v_c AND id <> v_sid;      -- andre enheder logges ud; denne beholdes
  RETURN true;
END $$;

-- ---------------------------------------------------------------------
-- DEL 6: Admin-værktøjer
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION quiz.admin_stats() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_bytes bigint; v_files bigint; v_err24 int; v_ord int;
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  BEGIN
    EXECUTE $q$ SELECT COALESCE(sum((metadata->>'size')::bigint), 0), count(*) FROM storage.objects WHERE bucket_id = 'quiz-uploads' $q$ INTO v_bytes, v_files;
  EXCEPTION WHEN OTHERS THEN v_bytes := NULL; v_files := NULL; END;
  BEGIN
    EXECUTE $q$ SELECT count(*)::int FROM quiz.errors WHERE created_at > now() - interval '24 hours' $q$ INTO v_err24;
  EXCEPTION WHEN OTHERS THEN v_err24 := NULL; END;
  SELECT count(*)::int INTO v_ord FROM quiz.orders WHERE status = 'ny';
  RETURN jsonb_build_object(
    'customers', (SELECT count(*) FROM quiz.customers),
    'quizzes',   (SELECT count(*) FROM quiz.quizzes),
    'quizzes_live', (SELECT count(*) FROM quiz.quizzes WHERE status = 'aktiv'),
    'teams',     (SELECT count(*) FROM quiz.teams WHERE name <> '🧪 Testhold'),
    'answers_30d', (SELECT count(*) FROM quiz.submissions WHERE created_at > now() - interval '30 days'),
    'orders_new', v_ord, 'errors_24h', v_err24,
    'storage_bytes', v_bytes, 'storage_files', v_files);
END $$;

CREATE OR REPLACE FUNCTION quiz.admin_recent_errors(p_limit int DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v jsonb;
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  BEGIN
    EXECUTE $q$ SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) FROM (SELECT * FROM quiz.errors ORDER BY 1 DESC LIMIT $1) e $q$
      INTO v USING LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  EXCEPTION WHEN undefined_table THEN v := '[]'::jsonb; END;
  RETURN v;
END $$;

-- Backup du selv kan gemme: kunder, løb, stop, opgaver og fasit. Aldrig PIN-hash eller deltagerdata.
CREATE OR REPLACE FUNCTION quiz.admin_export_all() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  RETURN jsonb_build_object(
    'exported_at', now(), 'format', 1,
    'customers',   (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'email', email, 'phone', phone, 'company', company, 'notes', notes, 'created_at', created_at)), '[]'::jsonb) FROM quiz.customers),
    'quizzes',     (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'customer_id', customer_id, 'title', title, 'description', description, 'status', status, 'stop_order', stop_order, 'theme', theme, 'theme_texts', theme_texts, 'hide_results', hide_results, 'opens_at', opens_at, 'closes_at', closes_at, 'created_at', created_at)), '[]'::jsonb) FROM quiz.quizzes),
    'stops',       (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'quiz_id', quiz_id, 'name', name, 'lat', lat, 'lng', lng, 'radius_m', radius_m, 'sort', sort, 'unlock_code', unlock_code)), '[]'::jsonb) FROM quiz.stops),
    'activities',  (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]'::jsonb) FROM quiz.activities a),
    'answer_keys', (SELECT COALESCE(jsonb_agg(to_jsonb(k)), '[]'::jsonb) FROM quiz.answer_keys k));
END $$;

-- Sletter en kunde og alle kundens løb. Fotos i Storage fjernes først af siden via purge-data (databasen kan ikke slette filer).
CREATE OR REPLACE FUNCTION quiz.delete_customer_cascade(p_customer_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE r record;
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN RAISE EXCEPTION 'Adgang nægtet'; END IF;
  FOR r IN SELECT id FROM quiz.quizzes WHERE customer_id = p_customer_id LOOP
    PERFORM quiz.delete_quiz_cascade(r.id);
  END LOOP;
  DELETE FROM quiz.orders    WHERE customer_id = p_customer_id;
  DELETE FROM quiz.sessions  WHERE customer_id = p_customer_id;
  DELETE FROM quiz.customers WHERE id = p_customer_id;
END $$;

-- ---------------------------------------------------------------------
-- DEL 7: Grænser (misbrugsbeskyttelse – rummelige nok til rigtig brug)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION quiz.trg_quota() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_quiz uuid;
BEGIN
  IF TG_TABLE_NAME = 'quizzes' THEN
    IF NEW.customer_id IS NOT NULL AND (SELECT count(*) FROM quiz.quizzes WHERE customer_id = NEW.customer_id) >= 100 THEN
      RAISE EXCEPTION 'Du har nået grænsen på 100 løb – slet gamle løb eller kontakt os';
    END IF;
  ELSIF TG_TABLE_NAME = 'teams' THEN
    IF NEW.name <> '🧪 Testhold' AND (SELECT count(*) FROM quiz.teams WHERE quiz_id = NEW.quiz_id AND name <> '🧪 Testhold') >= 200 THEN
      RAISE EXCEPTION 'Et løb kan have højst 200 hold';
    END IF;
  ELSIF TG_TABLE_NAME = 'stops' THEN
    IF (SELECT count(*) FROM quiz.stops WHERE quiz_id = NEW.quiz_id) >= 100 THEN
      RAISE EXCEPTION 'Et løb kan have højst 100 poster';
    END IF;
  ELSIF TG_TABLE_NAME = 'activities' THEN
    SELECT quiz_id INTO v_quiz FROM quiz.stops WHERE id = NEW.stop_id;
    IF (SELECT count(*) FROM quiz.activities a JOIN quiz.stops s ON s.id = a.stop_id WHERE s.quiz_id = v_quiz) >= 300 THEN
      RAISE EXCEPTION 'Et løb kan have højst 300 opgaver';
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_quota ON quiz.quizzes;    CREATE TRIGGER trg_quota BEFORE INSERT ON quiz.quizzes    FOR EACH ROW EXECUTE FUNCTION quiz.trg_quota();
DROP TRIGGER IF EXISTS trg_quota ON quiz.teams;      CREATE TRIGGER trg_quota BEFORE INSERT ON quiz.teams      FOR EACH ROW EXECUTE FUNCTION quiz.trg_quota();
DROP TRIGGER IF EXISTS trg_quota ON quiz.stops;      CREATE TRIGGER trg_quota BEFORE INSERT ON quiz.stops      FOR EACH ROW EXECUTE FUNCTION quiz.trg_quota();
DROP TRIGGER IF EXISTS trg_quota ON quiz.activities; CREATE TRIGGER trg_quota BEFORE INSERT ON quiz.activities FOR EACH ROW EXECUTE FUNCTION quiz.trg_quota();

-- Oprydning: + afviste bestillinger efter 90 dage (service role, som før)
CREATE OR REPLACE FUNCTION quiz.cleanup_housekeeping()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE n_att int := 0; n_ses int := 0; n_unl int := 0; n_err int := 0; n_ord int := 0;
BEGIN
  DELETE FROM quiz.login_attempts  WHERE created_at < now() - interval '7 days';   GET DIAGNOSTICS n_att = ROW_COUNT;
  DELETE FROM quiz.sessions        WHERE expires_at < now() - interval '1 day';    GET DIAGNOSTICS n_ses = ROW_COUNT;
  DELETE FROM quiz.unlock_attempts WHERE at < now() - interval '30 days';          GET DIAGNOSTICS n_unl = ROW_COUNT;
  BEGIN
    DELETE FROM quiz.errors WHERE created_at < now() - interval '30 days';         GET DIAGNOSTICS n_err = ROW_COUNT;
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
  END;
  DELETE FROM quiz.orders WHERE status = 'afvist' AND created_at < now() - interval '90 days'; GET DIAGNOSTICS n_ord = ROW_COUNT;
  RETURN jsonb_build_object('orders', n_ord, 'login_attempts', n_att, 'sessions', n_ses, 'unlock_attempts', n_unl, 'errors', n_err);
END $$;

REVOKE EXECUTE ON FUNCTION quiz.cleanup_housekeeping() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION quiz.cleanup_housekeeping() TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA quiz TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA quiz TO service_role;
