-- 011_customer_quiz_flow.sql
-- Kunde-login og oprettelse af kladde-løb fra customer-editor.
-- Kan køres flere gange i Supabase SQL Editor.

ALTER TABLE quiz.sessions
  ADD COLUMN IF NOT EXISTS customer_id uuid
  REFERENCES quiz.customers(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS sessions_customer_id_idx
  ON quiz.sessions (customer_id)
  WHERE customer_id IS NOT NULL;

-- PostgreSQL kan ikke ændre parameter-defaults med CREATE OR REPLACE.
-- Fjern derfor alle eventuelle gamle overloads først.
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT oid::regprocedure::text AS signature
      FROM pg_proc
     WHERE pronamespace = 'quiz'::regnamespace
       AND proname = 'create_quiz_for_customer'
  LOOP
    EXECUTE 'DROP FUNCTION ' || f.signature;
  END LOOP;
END;
$$;

CREATE FUNCTION quiz.create_quiz_for_customer(
  p_session_id uuid,
  p_title text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = quiz, public
AS $$
DECLARE
  v_customer_id uuid;
  v_quiz_id uuid := gen_random_uuid();
  v_title text := left(btrim(coalesce(p_title, '')), 90);
BEGIN
  IF v_title = '' THEN
    RAISE EXCEPTION 'Løbet skal have et navn';
  END IF;

  SELECT COALESCE(s.customer_id, q.customer_id)
    INTO v_customer_id
    FROM quiz.sessions s
    LEFT JOIN quiz.quizzes q ON q.id = s.quiz_id
   WHERE s.id = p_session_id
     AND s.is_admin = false
     AND s.expires_at > now();

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Ugyldig eller udløbet kundesession';
  END IF;

  INSERT INTO quiz.quizzes (
    id, title, status, stop_order, customer_id, theme, hide_results
  ) VALUES (
    v_quiz_id, v_title, 'kladde', 'fri', v_customer_id, 'standard', true
  );

  RETURN v_quiz_id;
END;
$$;

GRANT EXECUTE ON FUNCTION quiz.create_quiz_for_customer(uuid, text)
  TO anon, authenticated;
