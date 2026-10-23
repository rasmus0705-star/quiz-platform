-- 008_fix_activities_options_nullable.sql
-- Retter: "null value in column "options" of relation "activities"
--          violates not-null constraint"
--
-- Editoren sender bevidst options:null for opgavetyper der ikke er
-- multiple-choice (tal, tekst, foto, info) – kolonnen skal derfor
-- kunne være NULL.
--
-- KØR I SUPABASE SQL EDITOR

ALTER TABLE quiz.activities ALTER COLUMN options DROP NOT NULL;
