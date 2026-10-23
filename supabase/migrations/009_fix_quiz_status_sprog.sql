-- 009_fix_quiz_status_sprog.sql
-- Retter: get_quiz_stops tjekkede status IN ('active','testing') – men
-- platformen bruger danske statusnavne (kladde/testing/aktiv/arkiveret).
-- 'active' findes aldrig, så selv et AKTIVERET løb viste "Ingen stop
-- endnu" for de rigtige hold.
--
-- Udvider samtidig til også at tillade 'kladde', så "Test som spiller"
-- kan bruges til at forhåndsvise løbet, mens det stadig bygges.
-- 'arkiveret' er bevidst IKKE med – et arkiveret løb skal ikke kunne spilles.
--
-- KØR I SUPABASE SQL EDITOR

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
    AND q.status IN ('kladde', 'testing', 'aktiv')
  ORDER BY s.sort, a.sort;
$$;

GRANT EXECUTE ON FUNCTION quiz.get_quiz_stops(text) TO anon, authenticated;
