-- =====================================================================
-- reparation_003.sql          (kør i Supabase → SQL Editor – kan genkøres)
-- Reparerer det, som migration 003 ikke fik gjort: funktionerne der sletter deltagerdata
-- og fotos (purge-data, "Slet deltagerdata nu", sletning af løb, det daglige slette-job),
-- resultat-siden med tema/slettedato og tema-id'er der kan gemmes.
-- Rører IKKE noget fra 001, 002 eller 004. Kør tjek_database.sql bagefter – alt skal være OK.
-- =====================================================================

ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS data_purged_at timestamptz;
ALTER TABLE quiz.quizzes ADD COLUMN IF NOT EXISTS delete_after   timestamptz;

-- Tema-id'er: fjern evt. gammel begrænsning, så nye temaer kan gemmes (hvert trin for sig, så ét problem ikke stopper resten)
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'quiz.quizzes'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ~* '\mtheme\M' AND pg_get_constraintdef(oid) !~* 'theme_texts'
              AND conname <> 'quizzes_theme_format'
  LOOP EXECUTE format('ALTER TABLE quiz.quizzes DROP CONSTRAINT %I', r.conname); END LOOP;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'gammel tema-begrænsning blev ikke fjernet: %', SQLERRM; END $$;

DO $$ BEGIN
  UPDATE quiz.quizzes SET theme = 'standard' WHERE theme IS NOT NULL AND theme !~ '^[a-z0-9_-]{1,30}$';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'tema-id''er blev ikke rettet: %', SQLERRM; END $$;

DO $$ BEGIN
  ALTER TABLE quiz.quizzes DROP CONSTRAINT IF EXISTS quizzes_theme_format;
  ALTER TABLE quiz.quizzes ADD CONSTRAINT quizzes_theme_format CHECK (theme IS NULL OR theme ~ '^[a-z0-9_-]{1,30}$');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'tema-formatkrav blev ikke sat: %', SQLERRM; END $$;

-- Allerede afsluttede løb får en slettedato (90 dage fra nu), hvis de ikke har en
UPDATE quiz.quizzes SET delete_after = now() + interval '90 days' WHERE status = 'arkiveret' AND delete_after IS NULL;

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

CREATE OR REPLACE FUNCTION quiz.get_quiz_team_ids(p_quiz_id uuid)
RETURNS TABLE(team_id uuid) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT id FROM quiz.teams WHERE quiz_id = p_quiz_id;
$$;

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

CREATE OR REPLACE FUNCTION quiz.session_can_manage(p_session_id uuid, p_quiz_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  SELECT EXISTS (
    SELECT 1 FROM quiz.sessions s LEFT JOIN quiz.quizzes q ON q.id = p_quiz_id
     WHERE s.id = p_session_id AND s.expires_at > now()
       AND (s.is_admin OR s.quiz_id = p_quiz_id OR (s.customer_id IS NOT NULL AND s.customer_id = q.customer_id))
  );
$$;

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

-- Disse må KUN kaldes af Edge Function (service role)
REVOKE EXECUTE ON FUNCTION quiz.get_purgeable_quizzes()                  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION quiz.get_quiz_team_ids(uuid)                  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION quiz.purge_quiz_participant_data(uuid)        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION quiz.session_can_manage(uuid, uuid)           FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION quiz.get_purgeable_quizzes()                  TO service_role;
GRANT  EXECUTE ON FUNCTION quiz.get_quiz_team_ids(uuid)                  TO service_role;
GRANT  EXECUTE ON FUNCTION quiz.purge_quiz_participant_data(uuid)        TO service_role;
GRANT  EXECUTE ON FUNCTION quiz.session_can_manage(uuid, uuid)           TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA quiz TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA quiz TO service_role;
