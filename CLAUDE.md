# CLAUDE.md – "Jagten" (GPS-quizplatform) projektkort

> Indsæt i starten af en ny chat for hurtig kontekst. Opdateret 25. oktober 2026 (efter sikkerheds- og spilbarhedsrunden).

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
| Kort | Leaflet + OpenStreetMap-tiles + Nominatim (søgning) – se licens-noter nederst |
| Storage | Bucket `quiz-uploads` (public; kun billeder, max 5 MB) |

## Sider
| Side | Fil | Hvem |
|---|---|---|
| Forside + "Find mit login" | `index.html` | alle |
| Login | `app/login.html` (admin) · `?c=<customer-id>` (kunde) | – |
| Admin | `overview.html`, `customers.html`, `dashboard.html`, `editor.html?q=` | admin |
| Kunde | `customer-overview.html`, `customer-editor.html[?q=]` | kunde |
| Spil | `play/quiz.html?t=<hold-token>` | hold |
| Scoreboard | `board/scoreboard.html?q=<quiz-id>[&r=<runde>][&tv=1]` | alle (+ quizmaster-bar) |
| PWA | `sw.js`, `manifest.json` (relative stier!) | – |

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
- `stops`: `lat,lng,radius_m` (default 15, kun admin redigerer), `sort`, `qr_token`
- `activities`: `type` mc/tekst/tal/foto/info, `options`, `points`, `media_url`, `approval` auto/manuel/vis_kun
- `submissions`: `status` ok/pending/rejected, **`round_no`**, unik (team_id, activity_id, round_no)
- `team_runs`: starttid pr. hold pr. runde (via `start_team_run`)
- `teams`: `token` (nu 16 hex + slug), testhold hedder præcis `🧪 Testhold` (serveren bygger på navnet)

## Runder
Genaktivering af et afsluttet løb = **ny runde** (`round_no+1`): alle hold starter forfra, gamle resultater bevares og kan ses via
rundevælgeren på scoreboardet. Aktivering kræver (håndhæves af `set_quiz_status`): ≥1 opgave, ≥1 rigtigt hold, fasit på alle mc/tekst/tal.
Aktivering rydder testhold.

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
1. SQL Editor → kør `supabase/migrations/001_sikkerhed_og_runder.sql` (kan genkøres). Vælg "Run and enable RLS" hvis spurgt.
2. Edge Functions (dashboard, ikke git): indsæt `quiz-check-answer` og `quiz-pin-auth` → Deploy. (pin-auth: Verify JWT = fra.)
3. `git push`. Første gang efter push: hård genindlæsning (Ctrl+Shift+R) pga. ny service worker (`jagten-v3`).
Edge Functions og SQL følger **ikke** med git push.

## Konventioner
- PowerShell: `;` mellem git-kommandoer. Hele filer, ikke fragmenter.
- Statusværdier danske. Alle stier relative. Kun `config.js` har anon-nøglen.
- Scoreboard bruger sin egen klient (ikke api.js).
- Ny SQL gemmes i `supabase/migrations/NNN_navn.sql` (ikke kun i dashboardet).

## Status
**Færdigt:** auth pr. kunde, kunde-wizard (+ omdøb/flyt stop, kort-søgning), admin-editor, løbskort med hold-deling/QR/print,
test via skjult testhold, spilside (se ovenfor), scoreboard (rangliste, tid, fremgang, fotos, vinder, runder, TV-tilstand),
foto-godkendelse, låst/fri rækkefølge håndhævet server-side, sikkerhedslukning, runder.

**Verificeret 25/10 (ikke mod rigtige Supabase):** migration kørt 2× på lokal Postgres med skema-stub (64 adgangs-/runde-/PIN-/foto-tests ok);
Edge Functions kørt mod mock-DB; spil/scoreboard/kunde-oversigt kørt i jsdom. **Første rigtige test = en fuld kørsel med en telefon.**

## Backlog (prioriteret)
1. **Nødudgang ved GPS-problemer** (quizmaster-kode til manuel oplåsning) – ellers kan et hold sidde fast.
2. **Kunde-checkliste på løbskortet** (Byg → Hold → Test → Aktivér → Del) + resultatside/CSV/diplom efter afslutning + "Kopiér løb".
3. **GDPR:** privatlivspolitik, databehandleraftale, samtykketekst, auto-sletning (`delete_after` findes, bruges ikke), positioner/fotos.
4. **Kort-licens:** OSM-tiles er ikke til kommerciel trafik → egen tile-udbyder før salg. Nominatim forbyder søg-mens-du-skriver → DAWA/Dataforsyningen.
5. **"Find mit login" via mail** i stedet for at vise linket (kræver SMTP); i dag kan man via mail gætte et kunde-id (PIN beskytter stadig).
6. Server-side GPS-tjek (i dag kan en snyder kalde `quiz-check-answer` direkte med et token); rate-limit på `quiz-check-answer`; `anon_insert_errors` kan spammes.
7. Admin-PIN kan låses af 5 forkerte gæt (DoS) – tilføj IP/forsinkelse. Storage-SELECT-policy tillader listing af bucket.
8. Versionering: dump hele det historiske skema (`supabase db dump`) til `supabase/schema.sql`.
9. `overview.html`: ret redirect for ikke-admin (`editor.html?q=${session.quiz_id}` → `customer-overview.html`).
10. Escape room/indendørs (qr_token på stops er klar), temaer (`themes/standard.json` ubrugt), Stripe, push (`teams.push_token`, `notifications` klar), eget domæne + separat Supabase, betalt Supabase-plan før drift.
