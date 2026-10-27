# CLAUDE.md – "GPS Jagten" (GPS-quizplatform) projektkort

> Indsæt i starten af en ny chat for hurtig kontekst. Opdateret 28. oktober 2026 (efter live-kort, afsløring, 4-trins opretter, bestilling, admin-værktøjer).

## Hvad er dette?
Dansk selvbetjeningsplatform til GPS-quiz (escape room kommer senere), brandet **GPS Jagten** (arbejdsnavn – kan ændres, se backlog).
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
| Brand/PWA | `favicon.svg`, `icons/` (app-ikoner, delingsbillede), `404.html`, `manifest.json` | – |
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

## Kunde-oversigt, resultater, kopiér
- `customer-overview.html` (redesign 26/10): SVG-ikoner (ingen emojis), filtre (Alle/Aktive/Kladder/Afsluttede), aktive øverst. Hvert løbskort har **ét** "næste skridt" (primær knap), trinrække kun for kladder, hold som foldbar liste (kopiér link / QR / mail), fem sekundære handlinger og "Afslut løbet…" som diskret tekstknap. Toasts i stedet for alert().
- **Velkomstguide** (3 trin) til nye kunder: vises altid uden løb, ellers én gang (`localStorage jagten-guide-<kunde>`); (?)-knappen i headeren viser den igen.
- Aktivering blokeres hvis opgaver mangler fasit. `results.html` (RPC `get_results`): rangliste, alle svar, **CSV** (semikolon + BOM, formel-injektion neutraliseret), **diplomer** (top 3/alle, i løbets tema), print, kopiér løb, ny runde, "Slet deltagerdata nu".
- **Kopiér løb** (`copy_quiz`): stop, opgaver og fasit → ny **kladde** (nye nødkoder). Hold og resultater kopieres ikke.
- Opgavebilleder uploades **automatisk** ved valg (komprimeret til max 1600 px i browseren; "Gem opgave" venter på igangværende upload). Leaflet-lag er isoleret (`#map{isolation:isolate}`), vinduer har z-index 2000.

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
- **Aktivering (26/10, efter første feltest):** inden for stoppets radius + GPS-nøjagtighed ok. Tæt på midten (≤ 60 % af radius) åbner opgaven efter 0,8 sek., ellers 2,5 sek. med nedtælling ("Åbner om N sek…").
- **Færdig-skærm viser bevidst IKKE placering**, scoreboard-link eller "del resultat" – vinderen skal være en overraskelse. (Selve scoreboardet er stadig offentligt for den der har linket → se backlog: afsløringstilstand.)
- Kort: klassisk og firma bruger lyst kort (vejene var svære at se på mørkt kort i dagslys).

## Scoreboard
Poller `get_scoreboard` hvert 5. sek (ingen realtime – submissions er fjernet fra publication). Tydelig fejl/"ikke åbent endnu".
Quizmaster-bar (kun hvis session må styre løbet): afslut, start ny runde, godkend/afvis fotos. Offentligt vises kun godkendte fotos.

## Deploy-rækkefølge (vigtigt)
1. SQL Editor → kør `001_…`, `002_…`, `003_…`, **`004_arrangoer_og_drift.sql`** (alle kan genkøres). **Kør SQL FØR siderne pushes** – editoren bruger nye kolonner (`hide_results`, `opens_at`, `closes_at`). Vælg "Run and enable RLS" hvis spurgt.
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

## Tidligere status (26/10)
**Færdigt:** auth pr. kunde, kunde-wizard, admin-editor, løbskort med checkliste/hold-deling/QR/print, test via skjult testhold, spilside (**nyt design: tema, kompas, varm/kold, målcirkel + rute, "Fremme!"-øjeblik, konfetti, samtykke**), scoreboard (**tema + live-ticker**), foto-godkendelse, låst/fri rækkefølge server-side, sikkerhedslukning, runder, nødudgang, resultatside med CSV/diplomer, kopiér løb, **temaer (7), udskiftelig kortudbyder, GDPR-sletning (90 dage) + udkast til privatlivspolitik/databehandleraftale, selvhostede biblioteker/skrifttyper.**

**Verificeret 26/10 (ikke mod rigtige Supabase/telefon):** migration 001+002+003 (003 kørt 2×) på lokal Postgres med skema-stub – 64 + 37 + 31 adgangs-/runde-/PIN-/foto-/nødkode-/resultat-/kopi-/tema-/sletnings-tests ok; Edge Functions (inkl. `purge-data`) mod mock; alle sider i jsdom. **Ikke testet: rigtige kortfliser fra en betalt udbyder, kompas på rigtig telefon (iOS kræver tilladelse), udskrift af diplomer, GitHub-jobbet, det faktiske udseende på telefon.**

## Arrangør- og driftsfunktioner (migration 004, 28/10)
- **Live-kort** (scoreboard, kun quizmaster): `get_team_positions` → mærker grøn <3 min / orange / rød ≥6 min + advarsler for hold uden signal. Positioner >12 t gamle vises ikke.
- **Afsløring af vinderen:** `quizzes.hide_results` (standard TIL for nye løb, sættes i trin 1) + `results_revealed_at`. Mens skjult returnerer `get_scoreboard` til offentligheden **kun navne + fremdrift** (ingen point/tid/rækkefølge – også ikke i API'et). Quizmasteren ser alt, men scoreboardet viser som standard det skjulte billede også for ham ("Se placeringer (kun mig)" til at kigge) → storskærm røber intet. "Afslør vinderen" → podie-animation på alle skærme. Ny runde nulstiller afsløringen. Spillerens færdig-skærm viser aldrig placering.
- **Planlagt åbning/lukning:** `opens_at`/`closes_at`. Spiller: nedtælling før start (serverens ur via `server_now`), "Løbet er lukket" efter, tid tilbage i topbaren. Server: trigger på `submissions` afviser svar uden for tidsrummet (testhold undtaget).
- **Dårlig dækning (spiller):** svar og fotos prøves automatisk igen (banner med nedtælling), serverfejl (4xx) prøves ikke; næste post hentes når dækningen er tilbage (`online`-hændelse). Ikke varig kø på tværs af genindlæsning.
- **Bestilling:** `bestil.html` → `submit_order` (samtykke, honningkrukke, max 3/mail/døgn, max 30/time) → `orders` (RLS, kun RPC) → admin-forsiden (`app/overview.html`): "Opret kunde" (`create_customer_from_order`, idempotent) → `customers.html?c=<id>` (sæt PIN, send login). Afviste bestillinger slettes efter 90 dage. Betaling ikke bygget (felter `plan`, `amount_dkk` findes).
- **Kunde-selvbetjening:** "Skift PIN" (`change_my_pin`, spærring efter 5 forkerte, logger andre enheder ud). "Glemt PIN" kræver mail → ikke bygget (admin nulstiller).
- **Admin:** `admin_stats` (kunder/løb/hold/svar/fotolager med advarsel ved 70 % af 1 GB), `admin_recent_errors`, `admin_export_all` (backup som JSON – aldrig PIN-hash/deltagerdata; knap + 7-dages påmindelse), `delete_customer_cascade` (+ `purgeQuizData` for fotos først; kræver at man skriver SLET; blokeres ved live løb).
- **Grænser** (triggers): 100 løb/kunde, 200 hold/løb, 100 poster/løb, 300 opgaver/løb.
- **Opretter i 4 trin:** Løbet → Poster (kort; navngiv i panel, "hvad nu?", træk nåle, omdøb/flyt/slet) → Opgaver (status pr. post, fasit-advarsler) → Hold & deling. Fast "Sådan gør du" med afkrydsninger i hvert trin. Oversigten har en fast 3-trins vejledning + "Hjælp". Live-advarsel i editoren når løbet kører.
- **Rettet efter første feltrunde (29/10):** (1) 004 opretter selv `data_purged_at`/`delete_after` (tidligere kun i 003 → "column data_purged_at does not exist" ved aktivering/sletning hvis 003 ikke var kørt helt); `tjek_database.sql` viser hvilke kolonner/funktioner der mangler. (2) Kort: lys stil er nu OpenFreeMap `bright` (liberty var cremefarvet med hvide veje – svær at læse); reserve-kæde ønsket → `liberty` → OSM; skift `light` til `positron` i `js/map-config.js` hvis stadig svær. (3) Nødkoder er flyttet fra opgave-trinnet til trin 4 ("Vis nødkoder"). (4) Poster er større (nummer, navn, antal opgaver, fremhævning når ny). (5) Editoren bruger pladsen på store skærme (to kolonner, kort op til 68vh/820px, skrifter skaleres fra 1500 px). (6) Oversigt: større overskrifter, "Aktivér uden test", og testkontrol: "Genoptag test" (samme testhold) / "Afbryd test" (`end_test_team`) / "Test" starter forfra (spørger først).
- Sider: `bestil.html`, `hjaelp.html` (FAQ), `tjekliste.html` (printbar), `vilkaar.html` (UDKAST med gule felter).

## Runde 29/10 – fire ønsker + foto-løb og skabeloner
- **Skærmlås på velkomstskærmen:** kontakt (TIL som standard) ved siden af samtykket; låsen bedes om i samme tryk som Start, ellers afviser browseren den. Virker den ikke, slås kontakten tavst fra – kun hvis brugeren selv trykker på 🔆 på kortet, kommer der en besked.
- **Nøgletal på alle admin-sider:** `js/admin-stats.js` → `initAdminStats('overview'|'customers'|'quizzes')` tegner stribe i `#admin-stats`. Cacher i sessionStorage i 60 sek.; `refreshAdminStats()` efter handlinger. Erstatter de gamle stat-kort på `overview.html`.
- **Søgning:** pil op/ned vælger, Enter går til det valgte (første er valgt på forhånd), Esc lukker. Uden liste søger Enter.
- **Kunden kan slette eget løb:** `delete_my_quiz` (kun kladde/afsluttet; aldrig et løb der kører), fotos ryddes først via `purgeQuizData`.
- **Foto-løb:** `score_submission(submission, point)` – point 0..opgavens max, NULL = afvist, kan gøres om. Scoreboardets godkendelse er nu en karakterskala (0..max, eller "Godkend" ved 1 point). **Fotovæg** (`get_photo_wall`, knap 📸): quizmaster ser alle fotos med point/max og status; offentligheden kun godkendte. Ny approval-værdi `skjul` (kun quizmasteren ser billedet). Testholdets fotos vises aldrig.
- **Skabelon-løb:** `quizzes.is_template` + `template_tag`. Admin stjernemarkerer et løb i `dashboard.html` (`set_template`). Kunden: "Start fra skabelon" i oversigten → `list_templates` → `copy_template` giver kundens egen kladde (poster, opgaver og fasit; ingen hold) og åbner trin 2. Skabeloner tæller ikke i grænsen på 100 løb.
- **Kortet i editoren var gråt:** vektorkortet blev oprettet på en skjult fane (0 px). `jagtenWhenSized()` venter nu på, at kortet har plads, og enhver fejl giver OSM-fliser i stedet for et tomt kort.
- Alt dette ligger i `004_arrangoer_og_drift.sql` (kan genkøres). `reparation_003.sql` findes, hvis 003 ikke kørte færdigt; `tjek_database.sql` viser hvad der mangler.

## Idéer til senere (fra 29/10)
- **Deltag med kode** i stedet for et link pr. hold (SkoleGPS-greb) – nemmere at råbe op i en forsamling.
- Billige, fordi systemet næsten kan det: **escape room** (kodeord pr. post → samlet kode til sidst), **"Big Talk"** (opgaver uden svar), flere skabeloner.
- Mellem: **GPS-auktion** (point falder, jo flere hold der har været der), **power-ups** mellem hold.
- Store/frarådes nu: **"Among Us" i realtid** (holdene skal se hinandens positioner → ny privatlivsvurdering), **GPS-kunst** (kræver hele ruten gemt).
- **Musikløb:** Spotifys vilkår skal undersøges, før der bygges noget. Virker uden Spotify ved at arrangøren selv lægger lydklip op, som de har rettigheder til.

## Status og hvad der mangler
**Alt er testet i jsdom/lokal Postgres (236 DB-tests, 427 side-tests i 18 suiter, edge functions) – IKKE på rigtige telefoner/Supabase.**

### Skal på plads før første betalende kunde
1. **Supabase Free pauser efter 7 dages inaktivitet og har ingen backups** (Pro ≈ 25 USD/md. løser begge). Det daglige purge-job holder sandsynligvis projektet vågent – verificér.
2. Udfyld + jurist-læs `privatliv.html`, `databehandleraftale.html`, `vilkaar.html`. CVR/moms/faktura. Betaling (Stripe/MobilePay) når det skal koste noget.
3. Bucket `quiz-uploads`: sæt `file_size_limit` (5 MB) og `allowed_mime_types` (image/*) i Supabase (ingen kode).
4. Bekræft at `update_team_position` kun gemmer seneste position (PK `team_id`) og Supabase-region (EU).
5. Forsiden lover "escape room" – findes ikke endnu. Ret teksten eller byg det.
6. "Glemt PIN" via mail (kræver mail-afsendelse: Edge Function + udbyder).

### Halvt/ikke bygget
- Varig offline-kø for svar (kun automatisk genforsøg nu). Import af backup. PDF-holdkort med logo. Eget domæne + mail.
- Server-side GPS-tjek; rate-limit på `quiz-check-answer`; `anon_insert_errors` kan spammes; admin-PIN kan låses af 5 gæt; storage-SELECT tillader listing; `find_login` afslører kunde-id; versionér hele skemaet (`supabase db dump`).
- `theme_texts`-UI, flere temaer, escape room/indendørs, push, eget logo.
