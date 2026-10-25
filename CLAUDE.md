# CLAUDE.md – GPS-quizplatform projektkort

> Indsæt dette i starten af en ny chat for hurtig kontekst.
> Opdateret efter session 25. oktober 2026.

## Hvad er dette?

Dansk selvbetjeningsplatform til GPS-quiz og escape room — "Jagten".
Rasmus (admin) sælger adgang til kunder (foreninger/arrangører), som selv bygger
og deler løb via en kunde-PIN. Hold spiller via QR/link i mobilbrowser uden login.
Bygget af Rasmus (ralv@verdo.com).

## Tech-stack

| Del | Teknologi |
|---|---|
| Frontend | Statisk HTML + Vanilla JS, ingen build-trin |
| Hosting | GitHub Pages – `rasmus0705-star.github.io/quiz-platform` |
| Backend | Supabase – projekt `qmdqzdatlanyhewjwpzc` |
| Skema | `quiz` (separat fra public/beersniffer-tabeller) |
| Kort | Leaflet + OpenStreetMap + Nominatim (geocoding) |
| Storage | Supabase Storage – bucket `quiz-uploads` |
| Betaling | Stripe (Fase 3 – ikke bygget endnu) |

## URL-oversigt

| Side | URL |
|---|---|
| Landingsside | `/index.html` (Jagten – mørkt design, guld) |
| Admin-login | `/app/login.html` |
| Kunde-login | `/app/login.html?c=<customer-id>` |
| Admin-oversigt | `/app/overview.html` |
| Kunder (admin) | `/app/customers.html` |
| Alle løb (admin) | `/app/dashboard.html` |
| Admin-editor | `/app/editor.html?q=<quiz-id>` |
| Kunde-oversigt | `/app/customer-overview.html` |
| Kunde-editor (wizard) | `/app/customer-editor.html?q=<quiz-id>` |
| Holdspil | `/play/quiz.html?t=<hold-token>` |
| Scoreboard | `/board/scoreboard.html?q=<quiz-id>` |

## Filstruktur

```
/index.html                  – Landingsside (Jagten – mørkt tema, guld)
/app/login.html              – Admin + kunde-login
/app/overview.html           – Admin-landingsside
/app/customers.html          – Kundeliste, PIN pr. kunde, del-knapper
/app/dashboard.html          – Alle løb (admin)
/app/editor.html             – Admin-editor: fuld kontrol, GPS-radius pr. stop,
                               MC antal svarmuligheder, stop_order toggle
/app/customer-overview.html  – Kunde-landingsside: løbkort med stats, hold-deling,
                               test/aktivér/genaktivér knapper, scoreboard-pill
/app/customer-editor.html    – Kunde-wizard (3 trin): løb → rute+opgaver → hold+deling
/play/quiz.html              – Spiller: kort fylder alt, GPS-popup, auto-opgave ved radius,
                               afstandsnedtæller, stop-liste overlay, færdig-skærm med konfetti
/board/scoreboard.html       – Live scoreboard: rangliste, fremgang, foto-galleri, vinder-banner
/js/api.js                   – Supabase-klient, PIN-session (VIGTIGT: scoreboard bruger IKKE api.js)
/js/config.js                – Supabase URL + anon key
```

## Auth-system

| Aktør | Login | Session |
|---|---|---|
| Admin | `login.html` uden parameter | `is_admin: true` |
| Kunde | `login.html?c=<customer-id>` | `customer_id: <id>` |
| Spiller | Ingen — token i URL `?t=<token>` | – |

- PIN sidder på `customers.pin_hash` (ikke på quizzes)
- Edge Function `quiz-pin-auth` — sender `{ customer_id, pin }` for kunde, `{ pin }` for admin
- Rate-limit: 5 forsøg → 10 min blokering. Nulstil: `DELETE FROM quiz.login_attempts;`
- Deploy via Supabase Dashboard (ikke git push)
- CORS-headers skal inkludere: `authorization, x-client-info, apikey, content-type`

## Datamodel (schema: quiz)

| Tabel | Vigtige kolonner |
|---|---|
| `quizzes` | `title`, `status` (kladde/testing/aktiv/arkiveret), `customer_id`, `description`, `stop_order` (fri/laast), `mode` (gps/rum/hybrid) |
| `customers` | `name`, `email`, `phone`, `company`, `notes`, `pin_hash`, `pin_expires_at` |
| `stops` | `quiz_id`, `name`, `lat`, `lng`, `radius_m` (default 15m!), `sort`, `qr_token` |
| `activities` | `type`, `question`, `points`, `options`, `media_url`, `approval` (auto/manuel/vis_kun) |
| `answer_keys` | `activity_id`, `correct`, `tolerance` — sendes ALDRIG til klienten |
| `teams` | `quiz_id`, `name`, `token`, `push_token` |
| `submissions` | `team_id`, `activity_id`, `answer` (jsonb — foto-URL gemmes her), `points`, `is_correct` |
| `sessions` | `is_admin`, `customer_id`, `quiz_id`, `expires_at` |
| `notifications` | Fremtidssikring til push (ikke i brug) |

## RPC-funktioner

| Funktion | Formål |
|---|---|
| `delete_quiz_cascade(p_quiz_id)` | Slet quiz + alt relateret |
| `get_team_by_token(p_token)` | Hent hold uden login |
| `get_quiz_stops(p_token)` | Hent stop + aktiviteter til spillet — returnerer også `quiz_mode` (stop_order) og `activity_approval` |
| `create_quiz_for_customer(p_session_id, p_title)` | Opret quiz som kunde (omgår RLS, SET LOCAL row_security = off) |
| `update_team_position(p_token, p_lat, p_lng, p_accuracy_m)` | Opdater holdets GPS-position |
| `get_team_submissions(p_token)` | Hent holdets besvarelser |
| `check_session(quiz_id)` | Tjek session — admin ELLER customer_id ejer quizzen |

## GPS-indstillinger i play/quiz.html

```javascript
const MIN_ACCURACY_M = 25        // Ignorer GPS hvis nøjagtighed > 25m
const PROXIMITY_HITS_NEEDED = 4  // Kræv 4 hits i træk (~8 sek) før popup
```
- Default radius på stops: **15m** (tidligere 50m — alle eksisterende er opdateret)
- GPS-nøjagtighedsindikator vises i topbar (grøn/rød)

## Spiller-flow (play/quiz.html)

1. GPS-permission popup — kan ikke lukkes før accepteret
2. Kort fylder hele skærmen — holdets position som blå prik
3. Stop-pins: rød=tilgængelig, grøn=besvaret, grå=låst
4. Afstandsnedtæller i bunden til næste stop
5. Auto-popup når inden for radius (4 hits i træk)
6. Opgave fylder hele skærmen — kan ikke lukkes før besvaret
7. 3 sekunders nedtæller → automatisk tilbage til kort
8. Alle besvaret → festlig færdig-skærm med konfetti + scoreboard-link
9. Låst løb (arkiveret) → lås-skærm med scoreboard-link

## Scoreboard (board/scoreboard.html)

**VIGTIGT:** Scoreboard bruger IKKE `api.js` — har sin egen `createClient`:
```javascript
const { createClient } = supabase
const sb = createClient(SUPABASE_URL, SUPABASE_ANON)
```
- Live-opdatering via Supabase realtime + 15 sekunders interval
- Rangliste med progressbar, tid brugt, tiebreaker på tid
- Vinder-banner når alle hold er færdige
- Foto-galleri nederst
- Admin-bar (kun synlig for admin): "Afslut løbet nu"-knap
- **KENDT FEJL:** Scoreboard viser ikke data korrekt — fejlsøges næste session

## Hvad er færdigt ✅

- Landingsside (Jagten) med "Find mit login" via email
- PIN-auth pr. kunde, rate-limiting, sessions
- Admin: Oversigt, Kunder, Alle løb, Editor (fuld kontrol)
- Kunde: Oversigt med stats/hold-deling/test/aktivér, Editor-wizard
- Spiller: Kort, GPS, auto-popup, afstandsnedtæller, færdig-skærm
- Stop-rækkefølge: fri/låst (stop_order kolonne)
- MC: valgfrit antal svarmuligheder (2/3/4)
- GPS-radius redigerbar pr. stop i admin-editor (kun admin)
- Foto-upload til Storage (editor + spiller)
- Scoreboard: struktur bygget, realtime-subscription

## Hvad mangler / kendte fejl ❌

- **Scoreboard viser ikke data** — fejl under fejlsøgning (næste prioritet)
- Foto-opgaver: manuel godkendelse på scoreboard
- Tema-system — `standard.json` forberedt men ikke i brug
- Oprydning: døde type-aliaser i `play/quiz.html`
- Betaling (Stripe – Fase 3)
- Push-notifikationer (infrastruktur klar)

## Roadmap

- **Fase 1–1c** ✅ Auth, admin, kunde-flow, spiller-kort
- **Fase 2** ← næste: Fix scoreboard, foto-godkendelse, temaer
- **Fase 3** — Stripe-betaling
- **Fase 4** — QR-scanner alternativ til GPS, escape room/indendørs
- **Fase 5** — Eget domæne, separat Supabase-projekt
- **Fase 6** — Push-notifikationer, app-forbedringer
- **Fase 7** — Marketing, Lions-kanal

## Konventioner

- `answer_keys` sendes ALDRIG til klienten
- Hold: token i URL `?t=<token>`, ikke login
- Kun `config.js` indeholder Supabase anon key
- Alle stier er relative — ingen hardkodede domæner
- PowerShell: brug `;` i stedet for `&&`
- Statusværdier: `kladde`/`testing`/`aktiv`/`arkiveret` (dansk)
- Edge Functions: deploy via Supabase Dashboard (ikke git push)
- Scoreboard: egen klient, ikke api.js
