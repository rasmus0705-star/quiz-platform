-- 010_login_rate_limit.sql
-- Simpelt rate-limit-lag til PIN-login, så en PIN (især admin-PIN'en)
-- ikke kan gættes/brute-forces ubegrænset.
--
-- KØR I SUPABASE SQL EDITOR

CREATE TABLE IF NOT EXISTS quiz.login_attempts (
  id         bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target     text        NOT NULL,   -- 'admin' eller et quiz_id (som tekst)
  success    boolean     NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_target_time
  ON quiz.login_attempts (target, created_at DESC);

-- Kun service-role (Edge Function) må tilgå denne tabel – ingen policies
-- gives til anon/authenticated, nøjagtig samme mønster som quiz.sessions.
ALTER TABLE quiz.login_attempts ENABLE ROW LEVEL SECURITY;

-- Ryd selv gamle rækker op efter 7 dage, næste gang funktionen kaldes
-- (simpelt vedligehold uden behov for en cron-opgave).
CREATE OR REPLACE FUNCTION quiz.cleanup_old_login_attempts()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = quiz, public
AS $$
  DELETE FROM quiz.login_attempts WHERE created_at < now() - interval '7 days';
$$;
