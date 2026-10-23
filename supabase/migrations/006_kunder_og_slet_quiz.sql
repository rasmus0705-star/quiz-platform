-- 006_kunder_og_slet_quiz.sql
-- Tilføjer kundestyring (customers) og sikker sletning af quiz.
--
-- KØR I SUPABASE SQL EDITOR

-- ============================================================
-- 1. Kunde-tabel
-- ============================================================
CREATE TABLE IF NOT EXISTS quiz.customers (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text        NOT NULL,
  email      text,
  phone      text,
  company    text,
  notes      text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE quiz.customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_full_access" ON quiz.customers;
CREATE POLICY "admin_full_access" ON quiz.customers
  USING      (quiz.check_session_is_admin() OR auth.role() = 'authenticated')
  WITH CHECK (quiz.check_session_is_admin() OR auth.role() = 'authenticated');

-- ============================================================
-- 2. Knyt quizzer til en kunde (valgfrit felt)
-- ============================================================
ALTER TABLE quiz.quizzes
  ADD COLUMN IF NOT EXISTS customer_id uuid REFERENCES quiz.customers(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_quizzes_customer_id ON quiz.quizzes(customer_id);

-- ============================================================
-- 3. Sikker sletning af en quiz (rydder alle relaterede rækker)
--    Kun admin-session eller indlogget Supabase-bruger må kalde den.
-- ============================================================
CREATE OR REPLACE FUNCTION quiz.delete_quiz_cascade(p_quiz_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = quiz, public
AS $$
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet: kun admin kan slette quizzer';
  END IF;

  DELETE FROM quiz.team_positions WHERE team_id IN (SELECT id FROM quiz.teams WHERE quiz_id = p_quiz_id);
  DELETE FROM quiz.submissions    WHERE team_id IN (SELECT id FROM quiz.teams WHERE quiz_id = p_quiz_id);
  DELETE FROM quiz.teams          WHERE quiz_id = p_quiz_id;
  DELETE FROM quiz.answer_keys WHERE activity_id IN (
    SELECT a.id FROM quiz.activities a JOIN quiz.stops s ON s.id = a.stop_id WHERE s.quiz_id = p_quiz_id
  );
  DELETE FROM quiz.activities WHERE stop_id IN (SELECT id FROM quiz.stops WHERE quiz_id = p_quiz_id);
  DELETE FROM quiz.stops     WHERE quiz_id = p_quiz_id;
  DELETE FROM quiz.quizzes  WHERE id = p_quiz_id;
END;
$$;

GRANT EXECUTE ON FUNCTION quiz.delete_quiz_cascade(uuid) TO anon, authenticated;

-- ============================================================
-- 4. Bekræft
-- ============================================================
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'quiz' AND table_name = 'customers';
