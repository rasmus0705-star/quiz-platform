-- =====================================================================
-- 002_naodudgang_resultater_kopier.sql      (kør i Supabase → SQL Editor)
-- Kræver at 001_sikkerhed_og_runder.sql allerede er kørt. Kan genkøres.
--
--   1. Nødudgang: nødkode pr. stop (quizmaster giver den til holdet ved GPS-problemer)
--   2. Resultater: get_results (rangliste + alle svar) til resultatside/CSV/diplomer
--   3. Kopiér løb: copy_quiz (stop, opgaver og fasit kopieres – hold gør ikke)
-- =====================================================================

-- ---------------------------------------------------------------------
-- DEL 1: Nødudgang
-- ---------------------------------------------------------------------
-- 4 cifre er nemt at sige i telefonen. Brute force stoppes af forsøgsgrænsen nedenfor.
ALTER TABLE quiz.stops
  ADD COLUMN IF NOT EXISTS unlock_code text NOT NULL
  DEFAULT lpad((floor(random() * 10000))::int::text, 4, '0');

CREATE TABLE IF NOT EXISTS quiz.stop_unlocks (
  team_id     uuid        NOT NULL REFERENCES quiz.teams(id) ON DELETE CASCADE,
  stop_id     uuid        NOT NULL REFERENCES quiz.stops(id) ON DELETE CASCADE,
  round_no    int         NOT NULL,
  unlocked_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (team_id, stop_id, round_no)
);
ALTER TABLE quiz.stop_unlocks ENABLE ROW LEVEL SECURITY;      -- kun via RPC

CREATE TABLE IF NOT EXISTS quiz.unlock_attempts (
  id      bigserial   PRIMARY KEY,
  team_id uuid        NOT NULL REFERENCES quiz.teams(id) ON DELETE CASCADE,
  stop_id uuid        NOT NULL REFERENCES quiz.stops(id) ON DELETE CASCADE,
  success boolean     NOT NULL,
  at      timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE quiz.unlock_attempts ENABLE ROW LEVEL SECURITY;   -- kun via RPC
CREATE INDEX IF NOT EXISTS unlock_attempts_lookup ON quiz.unlock_attempts (team_id, stop_id, at);

-- Hold sender nødkoden → true/false. Koden læses aldrig af spillere.
CREATE OR REPLACE FUNCTION quiz.unlock_stop(p_token text, p_stop_id uuid, p_code text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_team uuid; v_quiz uuid; v_round int; v_code text; v_fails int;
BEGIN
  SELECT t.id, t.quiz_id, q.round_no INTO v_team, v_quiz, v_round
    FROM quiz.teams t JOIN quiz.quizzes q ON q.id = t.quiz_id
   WHERE t.token = p_token AND (q.status IN ('testing','aktiv') OR t.name = '🧪 Testhold');
  IF v_team IS NULL THEN RAISE EXCEPTION 'Løbet er ikke aktivt'; END IF;

  SELECT s.unlock_code INTO v_code FROM quiz.stops s WHERE s.id = p_stop_id AND s.quiz_id = v_quiz;
  IF v_code IS NULL THEN RAISE EXCEPTION 'Stoppet findes ikke i dette løb'; END IF;

  SELECT count(*)::int INTO v_fails FROM quiz.unlock_attempts
   WHERE team_id = v_team AND stop_id = p_stop_id AND NOT success AND at > now() - interval '10 minutes';
  IF v_fails >= 5 THEN
    RAISE EXCEPTION 'For mange forkerte forsøg – vent lidt og prøv igen, eller spørg din quizmaster';
  END IF;

  IF btrim(coalesce(p_code, '')) = v_code THEN
    INSERT INTO quiz.unlock_attempts (team_id, stop_id, success) VALUES (v_team, p_stop_id, true);
    INSERT INTO quiz.stop_unlocks (team_id, stop_id, round_no) VALUES (v_team, p_stop_id, v_round)
      ON CONFLICT DO NOTHING;
    RETURN true;
  END IF;

  INSERT INTO quiz.unlock_attempts (team_id, stop_id, success) VALUES (v_team, p_stop_id, false);
  RETURN false;
END $$;

-- Hvilke stop har holdet allerede låst op (så det overlever genindlæsning)
CREATE OR REPLACE FUNCTION quiz.get_team_unlocks(p_token text)
RETURNS TABLE(stop_id uuid) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT u.stop_id
    FROM quiz.stop_unlocks u
    JOIN quiz.teams   t ON t.id = u.team_id
    JOIN quiz.quizzes q ON q.id = t.quiz_id
   WHERE t.token = p_token AND u.round_no = q.round_no;
$$;

-- Logbog til quizmasteren: hvem brugte nødkode hvor (kun nuværende runde)
CREATE OR REPLACE FUNCTION quiz.get_unlocks(p_quiz_id uuid)
RETURNS TABLE(team_name text, stop_name text, unlocked_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF NOT (quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  RETURN QUERY
    SELECT t.name, s.name, u.unlocked_at
      FROM quiz.stop_unlocks u
      JOIN quiz.teams   t  ON t.id = u.team_id
      JOIN quiz.stops   s  ON s.id = u.stop_id
      JOIN quiz.quizzes qz ON qz.id = t.quiz_id
     WHERE t.quiz_id = p_quiz_id AND u.round_no = qz.round_no AND t.name <> '🧪 Testhold'
     ORDER BY u.unlocked_at DESC
     LIMIT 50;
END $$;

-- ---------------------------------------------------------------------
-- DEL 2: Resultater (rangliste + alle svar) – kun quizmaster/admin
-- ---------------------------------------------------------------------
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
    'customer', v_cust, 'round', v_r,
    'rounds', (SELECT COALESCE(jsonb_agg(g), '[]'::jsonb) FROM generate_series(1, v_q.round_no) g),
    'stops', v_stops, 'activities', v_acts, 'max_points', v_max,
    'teams', v_teams, 'generated_at', now());
END $$;

-- ---------------------------------------------------------------------
-- DEL 3: Kopiér løb (til næste års udgave) – nye hold, nye nødkoder
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION quiz.copy_quiz(p_quiz_id uuid, p_title text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE
  v_src quiz.quizzes; v_new uuid := gen_random_uuid();
  s record; a record; v_ns uuid; v_na uuid;
BEGIN
  IF NOT (quiz.check_session(p_quiz_id) OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  SELECT * INTO v_src FROM quiz.quizzes WHERE id = p_quiz_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Løb ikke fundet'; END IF;

  INSERT INTO quiz.quizzes (id, title, description, status, stop_order, customer_id,
                            mode, timer_min, theme, theme_texts)
  VALUES (v_new,
          COALESCE(NULLIF(btrim(p_title), ''), left(COALESCE(v_src.title, 'Løb'), 90) || ' (kopi)'),
          v_src.description, 'kladde', v_src.stop_order, v_src.customer_id,
          v_src.mode, v_src.timer_min, v_src.theme, v_src.theme_texts);

  FOR s IN SELECT * FROM quiz.stops WHERE quiz_id = p_quiz_id ORDER BY sort, created_at, id LOOP
    INSERT INTO quiz.stops (quiz_id, name, lat, lng, radius_m, sort)
    VALUES (v_new, s.name, s.lat, s.lng, s.radius_m, s.sort)
    RETURNING id INTO v_ns;                                   -- ny nødkode genereres automatisk

    FOR a IN SELECT * FROM quiz.activities WHERE stop_id = s.id ORDER BY sort NULLS LAST, id LOOP
      INSERT INTO quiz.activities (stop_id, sort, type, question, options, points,
                                   time_limit_s, hint, media_url, approval)
      VALUES (v_ns, a.sort, a.type, a.question, a.options, a.points,
              a.time_limit_s, a.hint, a.media_url, a.approval)
      RETURNING id INTO v_na;

      INSERT INTO quiz.answer_keys (activity_id, correct, tolerance)
      SELECT v_na, k.correct, k.tolerance FROM quiz.answer_keys k WHERE k.activity_id = a.id;
    END LOOP;
  END LOOP;

  RETURN v_new;
END $$;

-- ---------------------------------------------------------------------
-- Rettigheder (service role) – dækker også de nye tabeller
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA quiz TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA quiz TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA quiz TO service_role;
