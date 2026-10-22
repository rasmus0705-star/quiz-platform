-- 005_pin_auth.sql
-- PIN-baseret login til quizmasters (kunder + admin)
-- Erstatter magic-link afhængighed.
--
-- KØR I SUPABASE SQL EDITOR

-- ============================================================
-- 1. Tilføj PIN-felter til quizzes
-- ============================================================
ALTER TABLE quiz.quizzes
  ADD COLUMN IF NOT EXISTS pin_hash       text,
  ADD COLUMN IF NOT EXISTS pin_expires_at timestamptz;

-- Gør owner_id nullable (admin-PIN opretter quizzer uden Supabase-bruger)
ALTER TABLE quiz.quizzes
  ALTER COLUMN owner_id DROP NOT NULL;

-- ============================================================
-- 2. Opret sessions-tabel
-- ============================================================
CREATE TABLE IF NOT EXISTS quiz.sessions (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  quiz_id    uuid        REFERENCES quiz.quizzes(id) ON DELETE CASCADE,
  is_admin   boolean     NOT NULL DEFAULT false,
  expires_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Kun service-role må tilgå sessions direkte
ALTER TABLE quiz.sessions ENABLE ROW LEVEL SECURITY;
-- Ingen policies = ingen adgang for anon/authenticated (Edge Function bruger service-role)

-- ============================================================
-- 3. Helper: hent session-id fra request-header
-- ============================================================
CREATE OR REPLACE FUNCTION quiz.get_session_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = quiz, public
STABLE
AS $$
DECLARE
  v_id uuid;
BEGIN
  BEGIN
    v_id := (current_setting('request.headers', true)::json->>'x-session')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  RETURN v_id;
END;
$$;

-- ============================================================
-- 4. Check om aktuel session giver adgang til quiz_id
-- ============================================================
CREATE OR REPLACE FUNCTION quiz.check_session(p_quiz_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = quiz, public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM quiz.sessions s
    WHERE s.id        = quiz.get_session_id()
      AND s.expires_at > now()
      AND (s.quiz_id  = p_quiz_id OR s.is_admin = true)
  );
$$;

-- Check om aktuel session er admin (til INSERT uden quiz_id-kontekst)
CREATE OR REPLACE FUNCTION quiz.check_session_is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = quiz, public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM quiz.sessions s
    WHERE s.id       = quiz.get_session_id()
      AND s.expires_at > now()
      AND s.is_admin = true
  );
$$;

-- ============================================================
-- 5. RLS-politikker – tilføj PIN-session adgang
-- ============================================================

-- ── quizzes ─────────────────────────────────────────────────
DROP POLICY IF EXISTS "pin_session_select" ON quiz.quizzes;
CREATE POLICY "pin_session_select" ON quiz.quizzes
  FOR SELECT USING (quiz.check_session(id));

DROP POLICY IF EXISTS "pin_session_update" ON quiz.quizzes;
CREATE POLICY "pin_session_update" ON quiz.quizzes
  FOR UPDATE USING (quiz.check_session(id));

DROP POLICY IF EXISTS "pin_session_insert" ON quiz.quizzes;
CREATE POLICY "pin_session_insert" ON quiz.quizzes
  FOR INSERT WITH CHECK (quiz.check_session_is_admin());

-- ── stops ────────────────────────────────────────────────────
DROP POLICY IF EXISTS "pin_session_stops" ON quiz.stops;
CREATE POLICY "pin_session_stops" ON quiz.stops
  USING      (quiz.check_session(quiz_id))
  WITH CHECK (quiz.check_session(quiz_id));

-- ── activities ───────────────────────────────────────────────
DROP POLICY IF EXISTS "pin_session_activities" ON quiz.activities;
CREATE POLICY "pin_session_activities" ON quiz.activities
  USING (
    EXISTS (
      SELECT 1 FROM quiz.stops s
      WHERE s.id = stop_id AND quiz.check_session(s.quiz_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM quiz.stops s
      WHERE s.id = stop_id AND quiz.check_session(s.quiz_id)
    )
  );

-- ── answer_keys ──────────────────────────────────────────────
DROP POLICY IF EXISTS "pin_session_answer_keys" ON quiz.answer_keys;
CREATE POLICY "pin_session_answer_keys" ON quiz.answer_keys
  USING (
    EXISTS (
      SELECT 1
      FROM quiz.activities a
      JOIN quiz.stops s ON s.id = a.stop_id
      WHERE a.id = activity_id AND quiz.check_session(s.quiz_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM quiz.activities a
      JOIN quiz.stops s ON s.id = a.stop_id
      WHERE a.id = activity_id AND quiz.check_session(s.quiz_id)
    )
  );

-- ── teams ────────────────────────────────────────────────────
DROP POLICY IF EXISTS "pin_session_teams" ON quiz.teams;
CREATE POLICY "pin_session_teams" ON quiz.teams
  USING      (quiz.check_session(quiz_id))
  WITH CHECK (quiz.check_session(quiz_id));

-- ============================================================
-- 6. Bekræft
-- ============================================================
SELECT
  tablename,
  policyname
FROM pg_policies
WHERE schemaname = 'quiz'
  AND policyname LIKE 'pin_%'
ORDER BY tablename, policyname;
