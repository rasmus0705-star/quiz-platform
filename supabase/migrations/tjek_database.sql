-- =====================================================================
-- tjek_database.sql  (kør i Supabase → SQL Editor – ændrer INTET)
-- Viser hvilke kolonner og funktioner din database har. Rækker med MANGLER står øverst.
-- MANGLER = en migration er ikke kørt (eller kørte ikke færdigt). Kør 001, 002, 003, 004 i rækkefølge (alle kan genkøres).
-- =====================================================================
WITH k(tbl, col) AS (VALUES
  ('quizzes','round_no'), ('quizzes','stop_order'), ('quizzes','theme'), ('quizzes','delete_after'),
  ('quizzes','data_purged_at'), ('quizzes','hide_results'), ('quizzes','results_revealed_at'),
  ('quizzes','opens_at'), ('quizzes','closes_at'), ('stops','unlock_code'), ('teams','token')),
f(fn, kraever) AS (VALUES
  ('set_quiz_status','001'), ('create_test_team','001'), ('copy_quiz','002'), ('unlock_stop','002'), ('get_results','002'),
  ('get_purgeable_quizzes','003'), ('get_quiz_team_ids','003'), ('purge_quiz_participant_data','003'), ('session_can_manage','003'), ('cleanup_housekeeping','003'),
  ('get_team_positions','004'), ('reveal_results','004'), ('submit_order','004'), ('list_orders','004'),
  ('change_my_pin','004'), ('admin_stats','004'), ('end_test_team','004'))
SELECT 'kolonne' AS type, tbl || '.' || col AS navn, '' AS kraever_migration,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema = 'quiz' AND c.table_name = k.tbl AND c.column_name = k.col) THEN 'OK' ELSE 'MANGLER' END AS status
  FROM k
UNION ALL
SELECT 'funktion', fn, kraever,
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'quiz' AND p.proname = f.fn) THEN 'OK' ELSE 'MANGLER' END
  FROM f
ORDER BY status, type, navn;
