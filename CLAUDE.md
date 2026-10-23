# CLAUDE.md – GPS-quizplatform projektkort

> Indsæt dette i starten af en ny chat for hurtig kontekst.
> Erstatter tidligere version – denne er opdateret efter admin-UI-omstruktureringen.

## Hvad er dette?

Dansk selvbetjeningsplatform til GPS-quiz og indendørs opgaverum.
Quizmaster opsætter løbet via editor; hold spiller via QR/link i mobilbrowser.
Rasmus (admin) sælger adgang til kunder (foreninger/arrangører), som selv redigerer
deres løb via en PIN. Bygget af Rasmus (ralv@verdo.com).

## Tech-stack

| Del | Teknologi |
|---|---|
| Frontend | Statisk HTML + Vanilla JS, ingen build-trin |
| Hosting | GitHub Pages – `rasmus0705-star.github.io/quiz-platform` |
| Backend | Supabase – projekt `qmdqzdatlanyhewjwpzc` |
| Skema | `quiz` (separat fra public/beersniffer-tabeller) |
| Kort | Leaflet + OpenStreetMap |
| Betaling | Stripe (Fase 3 – ikke bygget endnu) |

## URL-oversigt

| Side | URL |
|---|---|
| Forside (redirect) | `/index.html` → `/app/login.html` |
| Login | `/app/login.html` (admin, eller `?q=<quiz-id>` for kunde) |
| **Oversigt** (admin-landingsside) | `/app/overview.html` |
| **Kunder** | `/app/customers.html` |
| Alle løb (fuld liste + filtre) | `/app/dashboard.html` |
| Editor | `/app/editor.html?q=<quiz-id>` |
| Holdspil | `/play/quiz.html?t=<hold-token>` |
| Scoreboard | `/board/scoreboard.html?q=<quiz-id>` |

## Filstruktur (kun det der afviger fra det oplagte)

```
/app/overview.html   – NY: admin-landingsside, nøgletal + seneste løb/kunder
/app/customers.html  – NY: kundeliste + mini-dashboard pr. kunde (PIN/slet/nyt løb)
/app/dashboard.html  – "Alle løb": fuld liste, filtre (Alle/Aktive/Uden kunde), slet-quiz
/app/editor.html     – wizard-UX: ✅-ikoner pr. fane, aktivering låst til krav er opfyldt,
                        "Test som spiller" (opretter skjult, selv-ryddende testhold)
/icons/*.png         – PWA-ikoner (var tomme/manglende – nu rigtige, marineblå+koral)
/sw.js               – precacher nu app-sider (ikke kun CSS/JS)
```

Fælles admin-sidebar (Oversigt/Kunder/Alle løb) er dupliceret inline i hver side –
ingen build-trin, så ingen delt komponentfil.

## Datamodel (schema: quiz) – tilføjelser siden sidst

| Tabel | Formål |
|---|---|
| **customers** | Kunder – name, email, phone, company, notes. `quizzes.customer_id` peger hertil (nullable) |
| **login_attempts** | Rate-limit-log til PIN-login (kun service-role adgang) |

Resten af datamodellen (quizzes/stops/activities/answer_keys/teams/submissions/
sessions/team_positions/errors) er uændret.

## Auth-system – vigtige ændringer

- Kunde-PIN skal nu være **min. 6 cifre** (klient-valideret i dashboard/customers).
- **Rate-limit**: `quiz-pin-auth` blokerer et target (admin, eller et quiz-id) i
  10 min. efter 5 forkerte forsøg. Nulstil akut med:
  `DELETE FROM quiz.login_attempts;`
- `ADMIN_PIN` er en Supabase Edge Function-secret – bør være 6+ cifre.
- **VIGTIGT:** Edge Functions deployes IKKE ved git push – GitHub Pages server kun
  statiske filer. Rasmus har ingen Supabase CLI installeret; deploy sker via
  Supabase Dashboard → Edge Functions → vælg funktion → indsæt kode → Deploy.
- CORS-headers på enhver ny Edge Function skal inkludere
  `authorization, x-client-info, apikey, content-type` – en for snæver liste
  (kun `Content-Type, Authorization`) fik login til at fejle helt stille
  (kun OPTIONS i logs, aldrig POST) efter supabase-js opdaterede sig selv via
  den upinnede CDN-URL.

## Konventioner

- `answer_keys` sendes ALDRIG til klienten
- Hold bruger token fra URL: `?t=<token>`, ikke login
- Kun `config.js` indeholder Supabase anon key
- Alle stier er relative – ingen hardkodede domæner
- PowerShell: brug `;` i stedet for `&&` mellem git-kommandoer
- Statusværdier er **danske**: `kladde`/`testing`/`aktiv`/`arkiveret` (ikke engelsk
  'active' – det var en tidligere bug i en RPC, nu rettet)

## Hvad er færdigt ✅

- PIN-auth + rate-limiting, admin + kunde, 7-dages/24-timers sessions
- **Holdspil (`play/quiz.html`) og scoreboard ER fuldt bygget** – modsat hvad en
  tidligere version af dette kort sagde. GPS-check, live point, realtime opdatering
- Admin: Oversigt (nøgletal), Kunder (mini-dashboard pr. kunde), Alle løb
  (filtre + slet), alt med konsistent sidebar-navigation og eget visuelt look
  (marineblå/koral, matcher spiloplevelsen – ikke generisk hvid SaaS-stil)
- Editor: tab-UX med færdiggørelses-tjek, låst aktivering, selv-ryddende testhold
- Slet-quiz (cascade-sikker RPC), kunde↔quiz-kobling
- PWA-ikoner og service worker virker nu reelt

## Hvad mangler ❌

- `play/quiz.html` – foto-opgaver uploader endnu ikke til Supabase Storage
  (gemmer kun filnavn som "svar", auto-godkendes)
- Betaling (Stripe – Fase 3)
- Tema-system: `themes/standard.json` har forberedte tekster, men intet bruger
  dem endnu – alt er hardkodet dansk i `play/quiz.html`
- Mindre oprydning: `'text'/'number'` type-aliaser i play/quiz.html er dødt
  kode (editoren laver kun `'tekst'/'tal'`)

## Roadmap

- **Fase 1** – Basisfunktioner ✅ done
- **Fase 1b** – Admin-overblik, kundestyring, sikkerhed ✅ done (denne runde)
- **Fase 2** – Foto-opgaver (Storage) + temaer ← næste oplagte skridt
- **Fase 3** – Betaling (Stripe)
- **Fase 4** – Opgaverum + hybrid (GPS + indendørs)
- **Fase 5** – Eget domæne + separat Supabase-projekt (lancering)
- **Fase 6** – Marketing, Lions-kanal
