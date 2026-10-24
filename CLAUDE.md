# CLAUDE.md – GPS-quizplatform projektkort

> Indsæt dette i starten af en ny chat for hurtig kontekst.
> Opdateret efter stor session 24. oktober 2026.

## Hvad er dette?

Dansk selvbetjeningsplatform til GPS-quiz og indendørs opgaverum.
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
| Storage | Supabase Storage – bucket `quiz-uploads` (opgave- og svar-billeder) |
| Betaling | Stripe (Fase 3 – ikke bygget endnu) |

## URL-oversigt

| Side | URL |
|---|---|
| Forside (redirect) | `/index.html` → `/app/login.html` |
| Admin-login | `/app/login.html` (ingen parameter) |
| Kunde-login | `/app/login.html?c=<customer-id>` |
| Admin-oversigt | `/app/overview.html` |
| Kunder (admin) | `/app/customers.html` |
| Alle løb (admin) | `/app/dashboard.html` |
| Admin-editor | `/app/editor.html?q=<quiz-id>` |
| Kunde-oversigt | `/app/customer-overview.html` |
| Kunde-editor (wizard) | `/app/customer-editor.html?q=<quiz-id>` |
| Holdspil | `/play/quiz.html?t=<hold-token>` |
| Scoreboard | `/board/scoreboard.html?q=<quiz-id>` |

## Filstruktur – vigtige filer

```
/app/login.html              – Admin + kunde-login (?c=<customer-id> for kunde)
/app/overview.html           – Admin-landingsside, nøgletal + seneste løb/kunder
/app/customers.html          – Kundeliste, PIN pr. kunde, del-knapper (link/QR/mail)
/app/dashboard.html          – Alle løb: fuld liste, filtre, slet
/app/editor.html             – Admin-editor: fuld kontrol over løb
/app/customer-overview.html  – Kunde-landingsside: løbkort med stats, hold-deling,
                               test/aktivér knapper direkte på kortet
/app/customer-editor.html    – Kunde-wizard (3 trin): løb → rute+opgaver → hold+deling
/js/api.js                   – Supabase-klient, PIN-session, getSession()
/js/config.js                – Supabase URL + anon key (aldrig i git)
/play/quiz.html              – Holdspil: GPS-check, live point, realtime
/board/scoreboard.html       – Live scoreboard med realtime opdatering
```

## Auth-system

### To aktørtyper:
| Aktør | Login | Session indeholder |
|---|---|---|
| Admin (Rasmus) | `login.html` uden parameter | `is_admin: true` |
| Kunde | `login.html?c=<customer-id>` | `customer_id: <id>` |
| Spiller | Ingen login — token i URL `?t=<token>` | – |

### PIN-struktur:
- **Admin-PIN**: Supabase Edge Function secret (`ADMIN_PIN`)
- **Kunde-PIN**: Gemt som SHA-256 hash på `customers.pin_hash` (ikke på quizzes længere!)
- Min. 6 cifre, rate-limit: 5 forkerte forsøg → 10 min. blokering
- Nulstil akut: `DELETE FROM quiz.login_attempts;`

### Edge Function `quiz-pin-auth`:
- Sender `{ customer_id, pin }` for kunde, `{ pin }` for admin
- Returnerer `{ session_id, is_admin, customer_id, expires_at }`
- Quiz-PIN-logik er FJERNET — PIN sidder nu på customers, ikke quizzes
- Deploy via Supabase Dashboard → Edge Functions (IKKE git push)
- CORS-headers skal inkludere: `authorization, x-client-info, apikey, content-type`

### Sessions-tabel har nu:
- `id`, `is_admin`, `expires_at`, `quiz_id` (nullable, legacy), `customer_id` (nullable, ny)

## Datamodel (schema: quiz)

| Tabel | Vigtige kolonner / noter |
|---|---|
| `quizzes` | `title`, `status` (kladde/testing/aktiv/arkiveret), `customer_id` (FK→customers), `description` (ny) |
| `customers` | `name`, `email`, `phone`, `company`, `notes`, `pin_hash` (ny), `pin_expires_at` (ny) |
| `stops` | `quiz_id`, `name`, `lat`, `lng`, `radius_m`, `sort`, `qr_token` (ny, fremtidssikring) |
| `activities` | `type`, `question`, `points`, `options`, `media_url` (ny), `approval` (ny: auto/manuel/vis_kun) |
| `answer_keys` | `activity_id`, `correct`, `tolerance` – sendes ALDRIG til klienten |
| `teams` | `quiz_id`, `name`, `token`, `push_token` (ny, fremtidssikring) |
| `submissions` | `team_id`, `activity_id`, `answer` (jsonb – foto-URL gemmes her) |
| `sessions` | `is_admin`, `customer_id`, `quiz_id`, `expires_at` |
| `login_attempts` | Rate-limit-log |
| `notifications` | Fremtidssikring til push (ikke i brug endnu) |

## Storage (Supabase)

- Bucket: `quiz-uploads` (public)
- `task-images/<quiz-id>/<timestamp>.<ext>` – opgavebilleder uploadet i editor
- `answers/<team-id>/<timestamp>.<ext>` – svar-billeder uploadet af spillere
- RLS: anon må uploade til begge mapper, alle må læse

## Opgavetyper

| Type | Fasit | Godkendelse |
|---|---|---|
| `mc` | Index i options | Automatisk |
| `tekst` | String eller array af strings | Automatisk |
| `tal` | Tal + tolerance | Automatisk |
| `foto` | Ingen fasit | `approval`: auto/manuel/vis_kun |
| `info` | Ingen fasit | Ingen point |

Alle opgavetyper kan have et valgfrit billede (`media_url`).
Foto-opgaver har `approval`-felt: `auto` (point med det samme), `manuel` (admin godkender på scoreboard), `vis_kun` (ingen point, vises på scoreboard).

## Kunde-flow

1. Admin opretter kunde i `customers.html`, sætter PIN
2. Admin sender login-link: `login.html?c=<customer-id>` + PIN via mail/QR
3. Kunde logger ind → lander på `customer-overview.html`
4. Kunde opretter løb → `customer-editor.html` (wizard: 3 trin)
   - Trin 1: Navn + beskrivelse
   - Trin 2: Rute (kort med Nominatim-søgning) + stop + opgaver
   - Trin 3: Hold + deling (link/QR/mail/print pr. hold)
5. Gem → redirect til oversigt
6. På oversigtskortet: **🧪 Test** og **▶️ Aktivér** knapper direkte
7. Spiller åbner hold-link → spiller løbet

## RPC-funktioner

| Funktion | Formål |
|---|---|
| `delete_quiz_cascade(p_quiz_id)` | Slet quiz + alle relaterede data |
| `get_team_by_token(p_token)` | Hent hold uden login (til spillet) |
| `create_quiz_for_customer(p_session_id, p_title)` | Opret quiz som kunde (omgår RLS) |

## RLS-noter

- `check_session(quiz_id)` – tjekker om session er admin ELLER har customer_id der ejer quizzen
- `anon` har GRANT SELECT på `quiz.sessions` og `quiz.customers`
- Kunde-sessioner bruger `x-session` header (sat via `activatePinClient()` i api.js)
- Supabase Storage: anon må uploade til `task-images/` og `answers/`

## Konventioner

- `answer_keys` sendes ALDRIG til klienten
- Hold bruger token fra URL: `?t=<token>`, ikke login
- Kun `config.js` indeholder Supabase anon key
- Alle stier er relative – ingen hardkodede domæner
- PowerShell: brug `;` i stedet for `&&` mellem git-kommandoer
- Statusværdier er **danske**: `kladde`/`testing`/`aktiv`/`arkiveret`
- Edge Functions deployes via Supabase Dashboard (ikke git push)
- Fælles admin-sidebar er dupliceret inline i hver side (ingen build-trin)

## Hvad er færdigt ✅

- PIN-auth pr. kunde (ikke pr. quiz), rate-limiting, admin + kunde, sessions
- Admin: Oversigt, Kunder (med PIN, del-knapper: link/QR/mail), Alle løb
- Admin-editor: fuld kontrol, foto-upload til Storage, godkendelse-dropdown, media_url
- Kunde-oversigt: løbkort med stats (stop/opgaver/hold), hold-deling pr. hold,
  test/aktivér knapper direkte på kortet
- Kunde-editor: wizard (3 trin), kortsøgning via Nominatim, vejledning, del pr. hold
- Gem redirecter til kunde-oversigt
- Holdspil og scoreboard er fuldt bygget (GPS-check, live point, realtime)
- Storage bucket + RLS policies
- Fremtidssikring: `qr_token` på stops, `push_token` på teams, `notifications`-tabel
- RPC `create_quiz_for_customer` (omgår RLS for kunde-oprettelse)

## Hvad mangler ❌

- `play/quiz.html` – foto-svar uploader ikke til Storage endnu (gemmer kun filnavn)
- Scoreboard – manuel godkendelse af foto-svar (admin-lag på scoreboard)
- Tema-system – `themes/standard.json` forberedt men ikke i brug
- Oprydning: `'text'/'number'` type-aliaser i `play/quiz.html` er dødt kode
- Betaling (Stripe – Fase 3)

## Roadmap

- **Fase 1** – Basisfunktioner ✅
- **Fase 1b** – Admin-overblik, kundestyring, sikkerhed ✅
- **Fase 1c** – Kunde-flow, kunde-editor, del-knapper ✅ (denne session)
- **Fase 2** – Foto-svar til Storage + manuel godkendelse på scoreboard + temaer ← næste
- **Fase 3** – Betaling (Stripe)
- **Fase 4** – QR-scanner som alternativ til GPS, opgaverum + hybrid
- **Fase 5** – Eget domæne + separat Supabase-projekt (lancering)
- **Fase 6** – Push-notifikationer (infrastruktur klar), app-forbedringer
- **Fase 7** – Marketing, Lions-kanal
