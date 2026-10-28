-- 014_admin_analytics.sql
-- Månedlige nøgletal til admin-statistikken.

CREATE OR REPLACE FUNCTION quiz.admin_analytics(p_months integer DEFAULT 12)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = quiz, public
AS $$
DECLARE
  v_months integer := LEAST(GREATEST(COALESCE(p_months, 12), 3), 24);
  v_from timestamptz := date_trunc('month', now()) - ((v_months - 1) * interval '1 month');
BEGIN
  IF NOT quiz.check_session_is_admin() THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;

  RETURN jsonb_build_object(
    'months', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'month', to_char(m.month_start, 'YYYY-MM'),
        'customers', (SELECT count(*) FROM quiz.customers c WHERE c.created_at >= m.month_start AND c.created_at < m.month_start + interval '1 month'),
        'quizzes',   (SELECT count(*) FROM quiz.quizzes q WHERE q.created_at >= m.month_start AND q.created_at < m.month_start + interval '1 month'),
        'teams',     (SELECT count(*) FROM quiz.teams t WHERE t.name <> '🧪 Testhold' AND t.created_at >= m.month_start AND t.created_at < m.month_start + interval '1 month'),
        'answers',   (SELECT count(*) FROM quiz.submissions s WHERE s.created_at >= m.month_start AND s.created_at < m.month_start + interval '1 month'),
        'orders',    (SELECT count(*) FROM quiz.orders o WHERE o.created_at >= m.month_start AND o.created_at < m.month_start + interval '1 month')
      ) ORDER BY m.month_start), '[]'::jsonb)
      FROM generate_series(v_from, date_trunc('month', now()), interval '1 month') AS m(month_start)
    ),
    'quiz_statuses', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('label', status, 'value', amount) ORDER BY status), '[]'::jsonb)
      FROM (SELECT status, count(*)::int AS amount FROM quiz.quizzes GROUP BY status) x
    ),
    'activity_types', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('label', type, 'value', amount) ORDER BY type), '[]'::jsonb)
      FROM (SELECT type, count(*)::int AS amount FROM quiz.activities GROUP BY type) x
    ),
    'refreshed_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION quiz.admin_analytics(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION quiz.admin_analytics(integer) TO anon, authenticated;
