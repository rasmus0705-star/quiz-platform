# CLAUDE.md – "Jagten" (GPS-quizplatform) projektkort

> Indsæt i starten af en ny chat for hurtig kontekst. Opdateret 26. oktober 2026 (efter temaer, kortudbyder-modul, GDPR, selvhostede biblioteker).

## Hvad er dette?
Dansk selvbetjeningsplatform til GPS-quiz (escape room kommer senere), brandet **Jagten**.
Rasmus (admin) giver kunder (foreninger/arrangører) adgang med en PIN. Kunden bygger sine løb i en wizard og deler
hold-links/QR. Hold spiller i mobilbrowseren **uden login** (token i URL). Bygget af Rasmus (ralv@verdo.com).

## Tech
| Del | Valg |
|---|---|
| Frontend | Statisk HTML + vanilla JS, intet build-trin |
| Hosting | GitHub Pages `rasmus0705-star.github.io/quiz-platform/` (**projekt-URL → brug altid relative stier**) |
| Backend | Supabase `qmdqzdatlanyhewjwpzc`, skema `quiz` |
| Kort | Leaflet (selvhostet) + udskiftelig udbyder via `js/map-config.js` (OSM kun til test) – se afsnittet "Kort" |
| Biblioteker/skrifttyper | Selvhostet i `vendor/` og `fonts/` (ingen CDN/Google) |
| Slet-job | Edge Function `purge-data` + GitHub Action `.github/workflows/purge-data.yml` |
| Storage | Bucket `quiz-uploads` (public; kun billeder, max 5 MB) |

## Sider
| Side | Fil | Hvem |
|---|---|---|
| Forside + "Find mit login" | `index.html` | alle |
| Login | `app/login.html` (admin) · `?c=<customer-id>` (kunde) | – |
| Admin | `overview.html`, `customers.html`, `dashboard.html`, `editor.html?q=` | admin |
| Kunde | `customer-overview.html`, `customer-editor.html[?q=]` | kunde |
| Resultater | `app/results.html?q=<quiz-id>[&r=<runde>]` – rangliste, alle svar, CSV, diplomer, kopiér, ny runde | admin + kunde (ejer) |
| Spil | `play/quiz.html?t=<hold-token>` | hold |
| Scoreboard | `board/scoreboard.html?q=<quiz-id>[&r=<runde>][&tv=1]` | alle (+ quizmaster-bar) |
| Jura (UDKAST) | `privatliv.html`, `databehandleraftale.html` | alle / kunder |
| PWA | `sw.js` (v4), `manifest.json` (relative stier!) | – |
| Delt JS | `js/api.js`, `js/config.js`, `js/map-config.js`, `js/map.js`, `js/themes.js` | – |

## Sikkerhedsmodel (VIGTIGT – ændret 25/10)
- Anon-nøglen er offentlig. **`anon` har ingen læse-policies længere** på quizzes/stops/activities/teams/submissions/customers/sessions.
  Alt offentligt går via `SECURITY DEFINER`-RPC'er: `get_team_by_token`, `get_quiz_stops`, `get_team_submissions`,
  `start_team_run`, `update_team_position`, `get_scoreboard`, `find_login`.
- Admin/kunde-sider kører som `anon` + header `x-session` (sættes af `activatePinClient()` i api.js). Adgang afgøres af
  `check_session(quiz_id)` / `check_session_is_admin()` i policies `pin_session_*`.
- Trigger `trg_guard_quiz_update`: kunder kan ikke ændre `status`, `customer_id`, `owner_id`, `round_no`, `paid_at`,
  `delete_after` direkte. Status ændres kun via RPC `set_quiz_status`.
- Kunde-PIN: bcrypt på `customers.pin_hash`, sættes via RPC `set_customer_pin` (admin), verificeres af RPC
  `verify_customer_pin` (kun service_role). Gamle SHA-256-hashes opgraderes automatisk ved næste login.
- **Aldrig** interpolér brugerdata (titler, holdnavne) i inline `onclick="…"`. Brug id'er + opslag, `textContent` eller `esc()`.
- Fasit (`answer_keys`) forlader aldrig serveren. Svar bedømmes i Edge Function `quiz-check-answer`.

## Datamodel (kun det vigtige)
- `quizzes`: `status` (kladde/testing/aktiv/arkiveret), `stop_order` (fri/laast), `round_no`, `description`, `customer_id`. (`mode` er gps/rum/hybrid – bruges ikke endnu. `pin_hash/pin_expires_at` er legacy og nullet.)
- `stops`: `lat,lng,radius_m` (default 15, kun admin redigerer), `sort`, `qr_token`, **`unlock_code`** (4 cifre, nødkode, tilfældig pr. stop)
- `stop_unlocks` (hold har brugt nødkode på stop i runde) og `unlock_attempts` (forsøg → spærring efter 5 forkerte pr. hold+stop pr. 10 min) – kun via RPC
- `activities`: `type` mc/tekst/tal/foto/info, `options`, `points`, `media_url`, `approval` auto/manuel/vis_kun
- `submissions`: `status` ok/pending/rejected, **`round_no`**, unik (team_id, activity_id, round_no)
- `team_runs`: starttid pr. hold pr. runde (via `start_team_run`)
- `teams`: `token` (nu 16 hex + slug), testhold hedder præcis `🧪 Testhold` (serveren bygger på navnet)

## Runder
Genaktivering af et afsluttet løb = **ny runde** (`round_no+1`): alle hold starter forfra, gamle resultater bevares og kan ses via
rundevælgeren på scoreboardet. Aktivering kræver (håndhæves af `set_quiz_status`): ≥1 opgave, ≥1 rigtigt hold, fasit på alle mc/tekst/tal.
Aktivering rydder testhold.

## Nødudgang (GPS driller)
Hvert stop har en 4-cifret **nødkode** (kunde/admin ser den i editoren, kan lave ny, og kunden kan printe et **quizmaster-ark** i trin 3).
Holdet trykker "🆘 Problemer med GPS? Brug nødkode" → vælger stop → indtaster koden → RPC `unlock_stop` → opgaven åbner uden GPS.
Hvis GPS er afvist/ikke findes kan holdet vælge **"Fortsæt uden GPS"** (hvert stop låses så op med nødkode). Oplåsninger huskes
(`get_team_unlocks`) og vises i quizmasterens logbog på scoreboardet (`get_unlocks`). **Nødkoden forlader aldrig serveren til spillere.**

## Kunde-checkliste, resultater, kopiér
- Løbskortet viser en 6-trins checkliste (Rute · Hold · Fasit · Test · Aktiv · Afslut) med "næste skridt"-knap. Aktivering blokeres hvis opgaver mangler fasit.
- `results.html` (RPC `get_results`, kun quizmaster/admin): rangliste, alle svar, **CSV** (semikolon + BOM til dansk Excel, formel-injektion neutraliseret), **diplomer** (top 3 / alle hold, A4 liggende), print, kopiér løb, start ny runde, rundevælger.
- **Kopiér løb** (`copy_quiz`): kopierer stop, opgaver og fasit til en ny **kladde** (nye nødkoder). Hold og resultater kopieres ikke.

## Temaer (pr. løb)
- `quizzes.theme` (tekst-id, format `a-z0-9_-`) vælges af kunden i wizardens trin 1 (live-preview) / admin-editoren. Ukendt eller tomt id → `standard`.
- 7 temaer i `js/themes.js`: standard (mørk/guld), skattejagt (børn, lys), jul, krimi, historie (pergament), natur, firma. Et tema = CSS-variabler (`--accent`, `--night`, `--panel`…), skrifttype, **ord** (fx "Næste skat"/"Næste spor"), emojis, kortstil + tint, konfetti-farver.
- `quizzes.theme_texts` (jsonb) kan overskrive ord pr. løb (kun nøgler fra `JAGTEN_BASE_WORDS`; ingen UI endnu). Alt kundeindhold indsættes som tekst/escapet.
- Spilleren (`quiz.html`), scoreboard og diplomer følger temaet. `get_team_by_token`/`get_scoreboard`/`get_results` returnerer temaet.
- Nyt tema: kopiér et i `themes.js`, giv nyt id. (Lyse temaer kræver kun at `--glass/--fade/--tint` er sat til lyse værdier.)

## Kort (udskiftelig udbyder – js/map-config.js)
- **Standard: `openfreemap`** – gratis, ingen nøgle/registrering, kommerciel brug tilladt (ifølge udbyderen), men **ingen driftsgaranti** (deres vilkår: leveres som den er, kan ændres/lukke). Vektorkort via MapLibre (`vendor/maplibre/`, hentes først når kortet vises; kræver WebGL). Reserve-kæde: ønsket stil → `liberty` + farvefilter → OSM-fliser. **Ved vækst: skift `provider` til `maptiler`/`stadia` + sæt `key` – ingen anden ændring.**
- `MAP_CONFIG.provider`: `openfreemap`, `osm` (KUN test – OSMs tile-servere må ikke bruges til kommerciel drift), `maptiler` (nøgle; gratis plan = ikke-kommerciel, betalt ca. 25 USD/md.), `stadia` (nøgle eller domæne-godkendelse; gratis = ikke-kommerciel, betalt fra ca. 20 USD/md.), `custom`. Manglende nøgle → OpenFreeMap. Tjek aktuelle vilkår hos udbyderen inden køb.
- `js/map.js`: tile-URL pr. udbyder + temaets kortstil (native stil hvis udbyderen har den, ellers lyst kort + CSS-farvefilter), fallback til OSM hvis en raster-udbyder leverer 0 af 6 fliser, adressesøgning (Nominatim kun ved Enter for openfreemap/osm).
- **DAWA lukkede 1. juli 2026.** Nominatim forbyder "søg mens du skriver": OSM-tilstand søger kun ved Enter; MapTiler/Stadia søger med autocomplete (DK-filter).
- Begræns API-nøglen til jeres domæne hos udbyderen (nøglen er synlig i browseren).

## GDPR / opbevaring
- Afsluttede løb får `delete_after` = +90 dage (`set_quiz_status`); genaktivering nulstiller. Løb der aldrig afsluttes: 12 mdr. efter sidste svar.
- Edge Function `purge-data` sletter først **fotos i Storage** (`answers/<team_id>/`, evt. `task-images/<quiz>/`), derefter rækker (`purge_quiz_participant_data`: hold, svar, positioner, oplåsninger). Selve løbet (stop/opgaver/fasit) bevares. Kaldes dagligt af GitHub Action `.github/workflows/purge-data.yml` (header `x-purge-secret`) eller manuelt af quizmaster ("Slet deltagerdata nu" på resultatsiden; kræver session + løb ikke aktivt).
- Sletning af hele løb (dashboard/customers) kalder `purgeQuizData(quizId, true)` først, ellers bliver billeder liggende.
- `cleanup_housekeeping()` rydder loginforsøg (7 d), udløbne sessioner, nødkodeforsøg og fejllogs (30 d).
- `privatliv.html` og `databehandleraftale.html` er UDKAST med gule `[felter]` der skal udfyldes + jurist-gennemlæsning. Samtykke-afkrydsning før start (testhold undtaget; husker i localStorage).
- Selvhostet: `vendor/` (supabase-js, leaflet, maplibre-gl 5.x + bro, nosleep, qrcode; licenser i `vendor/LICENSES.md`) og `fonts/` (Syne, Inter, Fredoka, Playfair Display, Special Elite; OFL via Fontsource). Ingen kald til Google/CDN – kun kortudbyder + Supabase.

## Spillerflow (play/quiz.html)
Velkomst (titel, beskrivelse, regler, **starttid**, GPS-tilladelse; advarsel i Messenger/Instagram-browsere) → fuldskærmskort →
opgave åbner automatisk efter **4 sek. inden for radius** med GPS-nøjagtighed ≤ max(20 m, radius) → kan ikke lukkes før besvaret →
resultat → tilbage til kort (eller "Næste opgave" på samme stop) → færdig-skærm med placering. I **låst** rækkefølge sender serveren
kun stop til og med det aktuelle. Pins er ikke klikbare for rigtige hold (kun testhold) – ellers kunne man svare uden at være der.
Foto: komprimeres til ≤1600 px, uploades til `answers/<team_id>/`, serveren validerer URL'en.

## Scoreboard
Poller `get_scoreboard` hvert 5. sek (ingen realtime – submissions er fjernet fra publication). Tydelig fejl/"ikke åbent endnu".
Quizmaster-bar (kun hvis session må styre løbet): afslut, start ny runde, godkend/afvis fotos. Offentligt vises kun godkendte fotos.

## Deploy-rækkefølge (vigtigt)
1. SQL Editor → kør `001_…`, `002_…`, **`003_temaer_og_gdpr.sql`** (alle kan genkøres). Vælg "Run and enable RLS" hvis spurgt.
2. Edge Functions (dashboard, ikke git): `quiz-check-answer`, `quiz-pin-auth`, **`purge-data`** → Deploy. Secrets: `PURGE_SECRET` (ny, lang tilfældig tekst).
3. GitHub → Settings → Secrets → Actions: `PURGE_SECRET`, `SUPABASE_URL`, `SUPABASE_ANON`. Kør workflowet "Slet udløbne deltagerdata" manuelt én gang (svar: `{"mode":"cron",…}`).
4. `js/map-config.js`: vælg kortudbyder + nøgle (standard = OSM, kun test).
5. Udfyld de gule felter i `privatliv.html` og `databehandleraftale.html`.
6. `git push`. Hård genindlæsning (Ctrl+Shift+R) pga. ny service worker (`jagten-v4`).
Edge Functions og SQL følger **ikke** med git push. GitHub slår planlagte jobs fra i offentlige repos efter 60 dages inaktivitet – kør dem manuelt ved pauser, eller brug pg_cron + pg_net mod `purge-data`.

## Konventioner
- PowerShell: `;` mellem git-kommandoer. Hele filer, ikke fragmenter.
- Statusværdier danske. Alle stier relative. Kun `config.js` har anon-nøglen.
- Scoreboard bruger sin egen klient (ikke api.js).
- Ny SQL gemmes i `supabase/migrations/NNN_navn.sql` (ikke kun i dashboardet).

## Status
**Færdigt:** auth pr. kunde, kunde-wizard, admin-editor, løbskort med checkliste/hold-deling/QR/print, test via skjult testhold, spilside (**nyt design: tema, kompas, varm/kold, målcirkel + rute, "Fremme!"-øjeblik, konfetti, samtykke**), scoreboard (**tema + live-ticker**), foto-godkendelse, låst/fri rækkefølge server-side, sikkerhedslukning, runder, nødudgang, resultatside med CSV/diplomer, kopiér løb, **temaer (7), udskiftelig kortudbyder, GDPR-sletning (90 dage) + udkast til privatlivspolitik/databehandleraftale, selvhostede biblioteker/skrifttyper.**

**Verificeret 26/10 (ikke mod rigtige Supabase/telefon):** migration 001+002+003 (003 kørt 2×) på lokal Postgres med skema-stub – 64 + 37 + 31 adgangs-/runde-/PIN-/foto-/nødkode-/resultat-/kopi-/tema-/sletnings-tests ok; Edge Functions (inkl. `purge-data`) mod mock; alle sider i jsdom. **Ikke testet: rigtige kortfliser fra en betalt udbyder, kompas på rigtig telefon (iOS kræver tilladelse), udskrift af diplomer, GitHub-jobbet, det faktiske udseende på telefon.**

## Backlog (prioriteret)
1. **Før første betalende kunde:** overvej en betalt kortudbyder (OpenFreeMap har ingen driftsgaranti – `js/map-config.js`), udfyld + få privatlivspolitik/databehandleraftale gennemlæst af jurist, bekræft Supabase-region (EU) og at `update_team_position` kun gemmer seneste position (PK `team_id`), skift kontaktmail på forsiden (står som en Verdo-mailadresse).
2. **"Find mit login" via mail** i stedet for at vise linket (kræver SMTP); i dag kan man via mail gætte et kunde-id (PIN beskytter stadig).
3. Server-side GPS-tjek (en snyder kan kalde `quiz-check-answer` direkte med et token – nødkoden håndhæves heller ikke server-side); rate-limit på `quiz-check-answer`; `anon_insert_errors` kan spammes.
4. Admin-PIN kan låses af 5 forkerte gæt (DoS). Storage-SELECT-policy tillader listing af bucket (billeder er offentlige via URL).
5. Versionering: dump hele det historiske skema (`supabase db dump`) til `supabase/schema.sql`.
6. `overview.html`: ret redirect for ikke-admin (`editor.html?q=${session.quiz_id}` → `customer-overview.html`).
7. Kunde kan ikke slette løb selv (kun admin). Overvej "Slet kladde" for kunder.
8. UI til `theme_texts` (egne ord/velkomsttekst pr. løb) og evt. flere temaer (påske, halloween, escape room).
9. Sjovere konkurrence: bonus for hurtigste hold, hints mod pointfradrag, holdfarver, lyd.
10. Escape room/indendørs (`qr_token` på stops er klar), Stripe, push (`teams.push_token`, `notifications` klar), eget domæne + separat Supabase, betalt Supabase-plan før drift.
