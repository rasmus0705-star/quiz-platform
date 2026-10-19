# CLAUDE.md – Projektkort: GPS-quizplatform

> Indsæt dette som første besked til AI i nye sessioner for at spare tokens.

## Hvad er dette?

Dansk selvbetjeningsplatform til GPS-quiz og indendørs opgaverum.
Quizmaster opsætter løbet via editor; hold spiller via QR/link i mobilbrowser.
Fastpris pr. arrangement.

## Tech-stack

| Del | Teknologi |
|---|---|
| Frontend | Statisk HTML + Vanilla JS, ingen build-trin |
| Hosting | GitHub Pages (quiz-platform repo) |
| Backend | Supabase – beersniffer-projekt (qmdqzdatlanyhewjwpzc) |
| Skema | `quiz` (separat fra public/beersniffer-tabeller) |
| Bucket | `quiz-media` (privat) |
| Kort | Leaflet + OpenStreetMap |
| Betaling | Stripe Checkout + webhook (Fase 3) |
| PWA | manifest.json + sw.js |

## Filstruktur

```
/index.html                   – Forside
/app/dashboard.html           – Quizmaster-overblik (kræver login)
/app/editor.html              – Opret/rediger quiz (?q=<id>)
/play/quiz.html               – Holdspil (?t=<hold-token>)
/board/scoreboard.html        – Live scoreboard (?q=<quiz-id>)
/js/config.js                 – Supabase URL + anon key
/js/api.js                    – Supabase-klient, auth, fejllog
/js/map.js                    – Leaflet-hjælpefunktioner
/js/activities/               – Én fil pr. opgavetype
/themes/standard.css/.json    – Standardtema
/themes/<tema>.css/.json      – Øvrige temaer
/supabase/migrations/         – SQL-migrationer
/supabase/functions/          – Edge Functions
/CLAUDE.md                    – Dette fil
```

## Datamodel (schema: quiz)

| Tabel | Formål |
|---|---|
| quizzes | Et quiz-løb (ejet af en quizmaster) |
| stops | GPS-punkt eller rum-station |
| activities | Opgaver pr. stop (26 typer) |
| answer_keys | Fasit – kun service-role key |
| teams | Hold med hold-token (ingen login) |
| submissions | Besvarelser – skrives kun af Edge Function |
| team_positions | Live GPS-positioner |
| payments | Stripe-betalinger |
| errors | Frontend-fejllog |

## Vigtige konventioner

- `answer_keys` sendes ALDRIG til klienten – altid server-side tjek
- Hold bruger token fra URL: `?t=<token>`, ikke login
- Kun `config.js` indeholder Supabase-nøglen (anon key kun)
- Alle stier er relative – ingen hardkodede domæner
- Str_replace-patches, .bak-backups, dry-run før destruktive operationer

## Roadmap (faser)

- **Fase 0** – Validering (navn, landing page, 5 pilotkunder)
- **Fase 1** – Testopsætning + basisfunktioner (aktiv)
- **Fase 2** – Temaer + fuldt opgavekatalog
- **Fase 3** – Betaling (Stripe)
- **Fase 4** – Opgaverum + hybrid
- **Fase 5** – Eget domæne + Supabase-projekt (lancering)
- **Fase 6** – Marketing, Lions-kanal
- **Fase 7–8** – Avancerede opgavetyper, gruppeadmin

## Supabase Edge Functions (præfiks: quiz-)

- `quiz-check-answer` – validerer svar server-side
- `quiz-stripe-webhook` – håndterer betalings-events

## Aktuel status

Fase 1 i gang. Skema oprettet, repo-skelet bygget.
Næste: RPC-funktioner til hold-token-adgang (002_quiz_rpc.sql),
derefter fuld editor med aktiviteter.
