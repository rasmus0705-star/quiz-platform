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

-- get_quiz_stops is already defined by 001_sikkerhed_og_runder.sql with
-- round-aware locked-order behavior and the full return signature. Do not
-- replace it here: PostgreSQL cannot change a function's RETURNS TABLE shape
-- using CREATE OR REPLACE FUNCTION.
GRANT EXECUTE ON FUNCTION quiz.get_quiz_stops(text) TO anon, authenticated;
