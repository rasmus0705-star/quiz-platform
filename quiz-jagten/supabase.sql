-- Quizjagten: statistik og fejlmeldinger
-- Kør hele filen én gang i Supabase → SQL Editor. Den kan køres igen uden at ødelægge data.

-- 1) Tabeller ------------------------------------------------------------
create table if not exists public.question_stats (
  question_id text primary key,
  answered    integer not null default 0,
  correct     integer not null default 0,
  updated_at  timestamptz not null default now()
);

create table if not exists public.question_reports (
  id          bigint generated always as identity primary key,
  question_id text not null,
  reason      text not null check (reason in ('forkert_svar', 'uklart', 'foraeldet', 'andet')),
  comment     text check (char_length(comment) <= 500),
  created_at  timestamptz not null default now()
);

-- RLS slået til uden policies = ingen kan læse/skrive direkte via API'et.
-- Appen må kun bruge de to funktioner herunder.
alter table public.question_stats   enable row level security;
alter table public.question_reports enable row level security;

-- 2) Log svar (appen sender op til 50 ad gangen) ----------------------------
create or replace function public.log_answers(answers jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if jsonb_typeof(answers) <> 'array' or jsonb_array_length(answers) > 50 then
    raise exception 'Ugyldig forespørgsel';
  end if;

  insert into question_stats as s (question_id, answered, correct)
  select a->>'q',
         count(*),
         count(*) filter (where (a->>'ok')::boolean)
  from jsonb_array_elements(answers) as a
  where a->>'q' ~ '^[a-z]{3}-[0-9]{4}$'
  group by a->>'q'
  on conflict (question_id) do update
    set answered   = s.answered + excluded.answered,
        correct    = s.correct  + excluded.correct,
        updated_at = now();
end;
$$;

-- 3) Fejlmelding ---------------------------------------------------------
create or replace function public.report_question(p_qid text, p_reason text, p_comment text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_qid !~ '^[a-z]{3}-[0-9]{4}$' then
    raise exception 'Ugyldigt spørgsmåls-id';
  end if;
  insert into question_reports (question_id, reason, comment)
  values (p_qid, p_reason, left(nullif(trim(p_comment), ''), 500));
end;
$$;

revoke all on function public.log_answers(jsonb) from public;
revoke all on function public.report_question(text, text, text) from public;
grant execute on function public.log_answers(jsonb) to anon, authenticated;
grant execute on function public.report_question(text, text, text) to anon, authenticated;

-- 4) Overblik til dig (kun synligt i dashboardet, ikke via API'et) -----------
-- Foreslået niveau ud fra svarprocent, når et spørgsmål har mindst 30 svar.
create or replace view public.question_quality
with (security_invoker = true) as
select s.question_id,
       s.answered,
       s.correct,
       round(100.0 * s.correct / nullif(s.answered, 0)) as pct_rigtige,
       case
         when s.answered < 30 then null
         when s.correct::numeric / s.answered >= 0.80 then 1
         when s.correct::numeric / s.answered >= 0.60 then 2
         when s.correct::numeric / s.answered >= 0.35 then 3
         else 4
       end as foreslaaet_niveau,
       (select count(*) from question_reports r where r.question_id = s.question_id) as fejlmeldinger,
       s.updated_at
from question_stats s;

revoke all on public.question_quality from anon, authenticated;
