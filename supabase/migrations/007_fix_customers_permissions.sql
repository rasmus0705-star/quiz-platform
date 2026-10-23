-- 007_fix_customers_permissions.sql
-- Retter: "permission denied for table customers"
-- 006 oprettede tabellen + RLS-politik, men glemte selve GRANT'et til
-- anon/authenticated. RLS styrer kun HVILKE rækker man må se/ændre –
-- Postgres kræver derudover denne grundlæggende tilladelse til tabellen.
--
-- KØR I SUPABASE SQL EDITOR

GRANT SELECT, INSERT, UPDATE, DELETE ON quiz.customers TO anon, authenticated;
