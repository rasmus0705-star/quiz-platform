-- 002_quiz_rpc.sql
-- RPC-funktioner til hold-token-adgang (ingen login påkrævet for spillere)
-- Kør i Supabase SQL Editor efter 001_quiz_schema.sql

-- ============================================================
-- 1. get_team_by_token
--    Returnerer hold-data baseret på ?t= token i URL'en.
--    SECURITY DEFINER – kører som postgres, omgår RLS.
--    Klienten sender kun token; modtager id, navn og quiz-id.
-- ============================================================
CREATE OR REPLACE FUNCTION quiz.get_team_by_token(p_token text)
RETURNS TABLE (
  team_id   uuid,
  team_name text,
  quiz_id   uuid,
  points    int
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = quiz, public
AS $$
  SELECT
    t.id          AS team_id,
    t.name        AS team_name,
    t.quiz_id     AS quiz_id,
    COALESCE(SUM(s.points) FILTER (WHERE s.is_correct), 0)::int AS points
  FROM quiz.teams t
  LEFT JOIN quiz.submissions s ON s.team_id = t.id
  WHERE t.token = p_token
  GROUP BY t.id, t.name, t.quiz_id;
$$;

GRANT EXECUTE ON FUNCTION quiz.get_team_by_token(text) TO anon, authenticated;
COMMENT ON FUNCTION quiz.get_team_by_token IS
  'Returnerer hold-id, navn, quiz-id og samlet pointscore for et hold-token. SECURITY DEFINER.';


-- ============================================================
-- 2. get_quiz_stops
--    Returnerer alle stop (og deres aktiviteter) for et quiz,
--    verificeret via hold-token.
--    answer_keys er ALDRIG inkluderet.
-- ============================================================
CREATE OR REPLACE FUNCTION quiz.get_quiz_stops(p_token text)
RETURNS TABLE (
  stop_id   uuid,
  stop_name text,
  sort      int,
  lat       double precision,
  lng       double precision,
  radius_m  int,
  activity_id       uuid,
  activity_type     text,
  activity_question text,
  activity_media_url text,
  activity_options  jsonb,
  activity_points   int
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = quiz, public
AS $$
  SELECT
    s.id          AS stop_id,
    s.name        AS stop_name,
    s.sort        AS sort,
    s.lat,
    s.lng,
    s.radius_m,
    a.id          AS activity_id,
    a.type        AS activity_type,
    a.question    AS activity_question,
    a.media_url   AS activity_media_url,
    a.options     AS activity_options,
    a.points      AS activity_points
  FROM quiz.teams t
  JOIN quiz.quizzes q  ON q.id = t.quiz_id
  JOIN quiz.stops  s   ON s.quiz_id = q.id
  LEFT JOIN quiz.activities a ON a.stop_id = s.id
  WHERE t.token = p_token
    AND q.status IN ('active', 'testing')
  ORDER BY s.sort, a.sort;
$$;

GRANT EXECUTE ON FUNCTION quiz.get_quiz_stops(text) TO anon, authenticated;
COMMENT ON FUNCTION quiz.get_quiz_stops IS
  'Returnerer stop og aktiviteter for holdet bag tokenet. Inkluderer aldrig fasit.';


-- ============================================================
-- 3. get_team_submissions
--    Returnerer hvilke aktiviteter holdet allerede har besvaret
--    (til at genskabe fremskridt ved genindlæsning).
-- ============================================================
CREATE OR REPLACE FUNCTION quiz.get_team_submissions(p_token text)
RETURNS TABLE (
  activity_id uuid,
  is_correct  boolean,
  points      int,
  submitted_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = quiz, public
AS $$
  SELECT
    sub.activity_id,
    sub.is_correct,
    sub.points,
    sub.created_at AS submitted_at
  FROM quiz.submissions sub
  JOIN quiz.teams t ON t.id = sub.team_id
  WHERE t.token = p_token
  ORDER BY sub.created_at;
$$;

GRANT EXECUTE ON FUNCTION quiz.get_team_submissions(text) TO anon, authenticated;
COMMENT ON FUNCTION quiz.get_team_submissions IS
  'Returnerer holdets tidligere besvarelser – bruges til at genskabe fremskridt.';


-- ============================================================
-- 4. update_team_position
--    Opdaterer eller indsætter GPS-position for et hold.
--    Spillerens position sendes fra play/quiz.html løbende.
-- ============================================================
CREATE OR REPLACE FUNCTION quiz.update_team_position(
  p_token text,
  p_lat   double precision,
  p_lng   double precision,
  p_accuracy_m int DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = quiz, public
AS $$
DECLARE
  v_team_id uuid;
BEGIN
  v_team_id := quiz.team_id_from_token(p_token);
  IF v_team_id IS NULL THEN RETURN; END IF;

  INSERT INTO quiz.team_positions (team_id, lat, lng, accuracy_m, recorded_at)
  VALUES (v_team_id, p_lat, p_lng, p_accuracy_m, now())
  ON CONFLICT (team_id)
  DO UPDATE SET
    lat         = EXCLUDED.lat,
    lng         = EXCLUDED.lng,
    accuracy_m  = EXCLUDED.accuracy_m,
    recorded_at = EXCLUDED.recorded_at;
END;
$$;

GRANT EXECUTE ON FUNCTION quiz.update_team_position(text, double precision, double precision, int)
  TO anon, authenticated;
COMMENT ON FUNCTION quiz.update_team_position IS
  'Upsert af holdets GPS-position. Kalder team_id_from_token internt.';


-- ============================================================
-- Sørg for at team_positions har UNIQUE på team_id
-- (til ON CONFLICT i update_team_position).
-- Hvis tabellen allerede er oprettet uden constraint, tilføj den:
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'team_positions_team_id_key'
      AND conrelid = 'quiz.team_positions'::regclass
  ) THEN
    ALTER TABLE quiz.team_positions ADD CONSTRAINT team_positions_team_id_key UNIQUE (team_id);
  END IF;
END $$;


-- ============================================================
-- 5. Realtime-publikation
--    Kør manuelt én gang (kræver superuser / Supabase dashboard):
--
--    ALTER PUBLICATION supabase_realtime ADD TABLE quiz.submissions;
--    ALTER PUBLICATION supabase_realtime ADD TABLE quiz.team_positions;
--
--    Gøres under: Database → Replication → supabase_realtime
-- ============================================================
