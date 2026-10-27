-- 012_admin_error_management.sql
-- Giver admin mulighed for at rydde fejloversigten fra admin-siden.

CREATE OR REPLACE FUNCTION quiz.admin_clear_errors()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = quiz, public
AS $$
DECLARE
  v_deleted integer := 0;
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;

  DELETE FROM quiz.errors;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION quiz.admin_clear_errors() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION quiz.admin_clear_errors() TO anon, authenticated;
