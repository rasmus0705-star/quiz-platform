-- =====================================================================
-- 003_temaer_og_gdpr.sql                    (kør i Supabase → SQL Editor)
-- Kræver 001 og 002. Kan genkøres.
--
--   1. Temaer: quizzes.theme følger med til spiller, scoreboard og resultater
--   2. GDPR-opbevaring: afsluttede løb får delete_after (90 dage); deltagerdata
--      (hold, svar, positioner, oplåsninger, fotos) slettes automatisk af Edge Function
--      'purge-data' – eller med det samme når en quizmaster beder om det
--   3. Oprydning: gamle fejllogs, loginforsøg og udløbne sessioner
-- =====================================================================

-- ---------------------------------------------------------------------
-- DEL 1: Temaer
-- ---------------------------------------------------------------------
ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS data_purged_at timestamptz;   -- bruges af GDPR-sletning (del 2)

-- Fjern evt. gammel CHECK på theme (ellers kan nye tema-id'er ikke gemmes), og indfør kun et formatkrav
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'quiz.quizzes'::regclass AND contype = 'c'
       AND pg_get_constraintdef(oid) ~* '\mtheme\M' AND pg_get_constraintdef(oid) !~* 'theme_texts'
       AND conname <> 'quizzes_theme_format'
  LOOP
    EXECUTE format('ALTER TABLE quiz.quizzes DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;
UPDATE quiz.quizzes SET theme = 'standard' WHERE theme IS NOT NULL AND theme !~ '^[a-z0-9_-]{1,30}$';
ALTER TABLE quiz.quizzes DROP CONSTRAINT IF EXISTS quizzes_theme_format;
ALTER TABLE quiz.quizzes ADD CONSTRAINT quizzes_theme_format CHECK (theme IS NULL OR theme ~ '^[a-z0-9_-]{1,30}$');

-- Spilleren får temaet med (nye kolonner sidst, så eksisterende kode læser videre uændret)
DROP FUNCTION IF EXISTS quiz.get_team_by_token(text);
CREATE FUNCTION quiz.get_team_by_token(p_token text)
RETURNS TABLE(team_id uuid, team_name text, quiz_id uuid, points int,
              quiz_title text, quiz_description text, quiz_status text,
              stop_order text, round_no int, started_at timestamptz, is_test boolean,
              quiz_theme text, quiz_theme_texts jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT t.id, t.name, t.quiz_id,
         COALESCE((SELECT SUM(s.points) FROM quiz.submissions s
                    WHERE s.team_id = t.id AND s.round_no = q.round_no AND s.status = 'ok'), 0)::int,
         q.title, q.description, q.status, q.stop_order, q.round_no,
         (SELECT tr.started_at FROM quiz.team_runs tr
           WHERE tr.team_id = t.id AND tr.round_no = q.round_no),
         (t.name = '🧪 Testhold'),
         q.theme, q.theme_texts
    FROM quiz.teams t JOIN quiz.quizzes q ON q.id = t.quiz_id
   WHERE t.token = p_token;
$$;

-- Scoreboard, resultater og løbsstatus (samme funktioner som før + tema/opbevaring)
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
    'theme', v_q.theme,
    'round', v_r,
    'rounds', (SELECT COALESCE(jsonb_agg(g), '[]'::jsonb) FROM generate_series(1, v_q.round_no) g),
    'stops', v_stops, 'activities', v_acts,
    'teams', v_teams, 'photos', v_photos);
END $$;

CREATE OR REPLACE FUNCTION quiz.get_results(p_quiz_id uuid, p_round int DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE
  v_q quiz.quizzes; v_r int; v_cust text; v_stops int; v_acts int; v_max int; v_teams jsonb;
BEGIN
  IF NOT (quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  SELECT * INTO v_q FROM quiz.quizzes WHERE id = p_quiz_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Løb ikke fundet'; END IF;

  v_r := LEAST(GREATEST(COALESCE(p_round, v_q.round_no), 1), v_q.round_no);
  SELECT c.name INTO v_cust FROM quiz.customers c WHERE c.id = v_q.customer_id;
  SELECT count(*)::int INTO v_stops FROM quiz.stops WHERE quiz_id = v_q.id;
  SELECT count(*)::int, COALESCE(SUM(a.points) FILTER (WHERE a.type <> 'info'), 0)::int
    INTO v_acts, v_max
    FROM quiz.activities a JOIN quiz.stops s ON s.id = a.stop_id WHERE s.quiz_id = v_q.id;

  SELECT COALESCE(jsonb_agg(
           jsonb_build_object('name', x.name, 'points', x.points, 'correct', x.correct,
                              'answered', x.answered, 'finished', x.finished,
                              'duration_s', x.duration_s, 'answers', x.answers)
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
             END AS duration_s,
             (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                        'stop', st.name, 'stop_no', st.ord, 'question', a.question, 'type', a.type,
                        'answer', s2.answer #>> '{}', 'correct', s2.is_correct, 'points', s2.points,
                        'status', s2.status, 'at', s2.created_at)
                      ORDER BY st.ord, a.sort NULLS LAST), '[]'::jsonb)
                FROM quiz.submissions s2
                JOIN quiz.activities a ON a.id = s2.activity_id
                JOIN (SELECT id, name, (ROW_NUMBER() OVER (ORDER BY sort, created_at, id))::int AS ord
                        FROM quiz.stops WHERE quiz_id = v_q.id) st ON st.id = a.stop_id
               WHERE s2.team_id = t.id AND s2.round_no = v_r AND a.type <> 'info') AS answers
        FROM quiz.teams t
        LEFT JOIN quiz.submissions s  ON s.team_id = t.id AND s.round_no = v_r
        LEFT JOIN quiz.team_runs   tr ON tr.team_id = t.id AND tr.round_no = v_r
       WHERE t.quiz_id = v_q.id AND t.name <> '🧪 Testhold'
       GROUP BY t.id, t.name, tr.started_at
    ) x;

  RETURN jsonb_build_object(
    'quiz', jsonb_build_object('id', v_q.id, 'title', v_q.title, 'status', v_q.status,
                               'round_no', v_q.round_no, 'description', v_q.description),
    'customer', v_cust, 'theme', v_q.theme,
    'delete_after', v_q.delete_after, 'data_purged_at', v_q.data_purged_at, 'round', v_r,
    'rounds', (SELECT COALESCE(jsonb_agg(g), '[]'::jsonb) FROM generate_series(1, v_q.round_no) g),
    'stops', v_stops, 'activities', v_acts, 'max_points', v_max,
    'teams', v_teams, 'generated_at', now());
END $$;

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
         data_purged_at = CASE WHEN p_status = 'aktiv'     THEN NULL ELSE data_purged_at END
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

-- ---------------------------------------------------------------------
-- DEL 2: GDPR-opbevaring
-- ---------------------------------------------------------------------
-- Allerede afsluttede løb får også en slettedato (90 dage fra nu)
UPDATE quiz.quizzes SET delete_after = now() + interval '90 days'
 WHERE status = 'arkiveret' AND delete_after IS NULL;

-- Hvilke løb har deltagerdata der skal slettes nu?
--   · afsluttede løb hvor delete_after er passeret
--   · løb der aldrig blev afsluttet, og hvor sidste svar er over 12 måneder gammelt
CREATE OR REPLACE FUNCTION quiz.get_purgeable_quizzes()
RETURNS TABLE(quiz_id uuid) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT q.id
    FROM quiz.quizzes q
   WHERE EXISTS (SELECT 1 FROM quiz.teams t
                  WHERE t.quiz_id = q.id AND t.name <> '🧪 Testhold'
                    AND (q.delete_after IS NULL OR t.created_at < q.delete_after))
     AND (
          (q.status = 'arkiveret' AND q.delete_after IS NOT NULL AND q.delete_after < now())
       OR (q.status <> 'arkiveret'
           AND COALESCE((SELECT max(s.created_at) FROM quiz.submissions s
                           JOIN quiz.teams t2 ON t2.id = s.team_id WHERE t2.quiz_id = q.id), q.created_at)
               < now() - interval '12 months')
     );
$$;

-- Hold-id'er (så Edge Function kan fjerne holdenes fotos i Storage før rækkerne slettes)
CREATE OR REPLACE FUNCTION quiz.get_quiz_team_ids(p_quiz_id uuid)
RETURNS TABLE(team_id uuid) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT id FROM quiz.teams WHERE quiz_id = p_quiz_id;
$$;

-- Sletter ALLE deltagerdata for et løb. Selve løbet (stop, opgaver, fasit) bevares, så det kan genbruges/kopieres.
CREATE OR REPLACE FUNCTION quiz.purge_quiz_participant_data(p_quiz_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_ids uuid[]; n_sub int; n_team int;
BEGIN
  SELECT COALESCE(array_agg(id), '{}'::uuid[]) INTO v_ids FROM quiz.teams WHERE quiz_id = p_quiz_id;
  DELETE FROM quiz.team_positions WHERE team_id = ANY (v_ids);
  DELETE FROM quiz.submissions    WHERE team_id = ANY (v_ids);
  GET DIAGNOSTICS n_sub = ROW_COUNT;
  DELETE FROM quiz.teams          WHERE id      = ANY (v_ids);   -- team_runs, stop_unlocks, unlock_attempts følger med (CASCADE)
  GET DIAGNOSTICS n_team = ROW_COUNT;
  PERFORM set_config('quiz.bypass_guard', '1', true);
  UPDATE quiz.quizzes SET data_purged_at = now() WHERE id = p_quiz_id;
  PERFORM set_config('quiz.bypass_guard', '0', true);
  RETURN jsonb_build_object('teams', n_team, 'submissions', n_sub);
END $$;

-- Må denne session styre dette løb? (Edge Function kører som service role, så den kan ikke bruge header-baseret check_session)
CREATE OR REPLACE FUNCTION quiz.session_can_manage(p_session_id uuid, p_quiz_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT EXISTS (
    SELECT 1 FROM quiz.sessions s LEFT JOIN quiz.quizzes q ON q.id = p_quiz_id
     WHERE s.id = p_session_id AND s.expires_at > now()
       AND (s.is_admin OR s.quiz_id = p_quiz_id OR (s.customer_id IS NOT NULL AND s.customer_id = q.customer_id))
  );
$$;

-- Almindelig oprydning (kaldes dagligt af purge-data)
CREATE OR REPLACE FUNCTION quiz.cleanup_housekeeping()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE n_att int := 0; n_ses int := 0; n_unl int := 0; n_err int := 0;
BEGIN
  DELETE FROM quiz.login_attempts  WHERE created_at < now() - interval '7 days';   GET DIAGNOSTICS n_att = ROW_COUNT;
  DELETE FROM quiz.sessions        WHERE expires_at < now() - interval '1 day';    GET DIAGNOSTICS n_ses = ROW_COUNT;
  DELETE FROM quiz.unlock_attempts WHERE at < now() - interval '30 days';          GET DIAGNOSTICS n_unl = ROW_COUNT;
  BEGIN
    DELETE FROM quiz.errors WHERE created_at < now() - interval '30 days';         GET DIAGNOSTICS n_err = ROW_COUNT;
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
  END;
  RETURN jsonb_build_object('login_attempts', n_att, 'sessions', n_ses, 'unlock_attempts', n_unl, 'errors', n_err);
END $$;

-- Disse må KUN kaldes af Edge Function (service role)
REVOKE EXECUTE ON FUNCTION quiz.get_purgeable_quizzes()                  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION quiz.get_quiz_team_ids(uuid)                  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION quiz.purge_quiz_participant_data(uuid)        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION quiz.session_can_manage(uuid, uuid)           FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION quiz.cleanup_housekeeping()                   FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION quiz.get_purgeable_quizzes()                  TO service_role;
GRANT  EXECUTE ON FUNCTION quiz.get_quiz_team_ids(uuid)                  TO service_role;
GRANT  EXECUTE ON FUNCTION quiz.purge_quiz_participant_data(uuid)        TO service_role;
GRANT  EXECUTE ON FUNCTION quiz.session_can_manage(uuid, uuid)           TO service_role;
GRANT  EXECUTE ON FUNCTION quiz.cleanup_housekeeping()                   TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA quiz TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA quiz TO service_role;
