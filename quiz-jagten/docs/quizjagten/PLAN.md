# Quizjagten – implementeringsplan

> **Til Codex:** Dette er den samlede plan for den næste udvikling af Quizjagten. Læs afsnit 1–5, før du skriver kode. Udfør én opgave ad gangen (fx `F1.2`), og opdatér statuslisten i afsnit 12, når en opgave er færdig.

| Felt | Værdi |
| --- | --- |
| Produkt | Quizjagten – dansk quiz- og selskabsspil som PWA |
| Hosting | GitHub Pages: repoet `quiz-platform`, appmappe `quiz-jagten/` · Supabase (delt projekt med GPS Jagten) |
| Ejer | Rasmus |
| Version af planen | 1.1 · 28. november 2026 (tilpasset efter kortlægningen i F0.1) |
| Referencefiler | `docs/quizjagten/reference/` (se afsnit 13) |
| Eksempeldata | `docs/quizjagten/data/` |
| Kortlægning | `docs/quizjagten/NOTES.md` (resultatet af F0.1) |

> **Stier:** alle stier i planen er relative til appmappen `quiz-jagten/`. `docs/quizjagten/PLAN.md` betyder altså `quiz-jagten/docs/quizjagten/PLAN.md`. Repo-roden tilhører GPS Jagten (`index.html`, `sw.js`, `board/`, `supabase/`) og må ikke forveksles med Quizjagtens filer.

---

## 0. Sådan bruger du planen (til Rasmus)

1. Mappen ligger i `quiz-jagten/docs/quizjagten/`.
2. Giv Codex én opgave pr. kørsel. Kortlægningen (`F0.1`) er udført – næste opgave er `F0.2`.
3. Gennemse ændringerne, test på telefon og tv, og bed derefter om næste opgave.

**Promptskabeloner til Codex**

```text
Læs quiz-jagten/docs/quizjagten/PLAN.md (afsnit 1–5) og NOTES.md, og udfør opgave F0.2.
```

```text
Implementér opgave F1.1 fra quiz-jagten/docs/quizjagten/PLAN.md.
Følg arbejdsreglerne i afsnit 1. Når du er færdig: opdatér status i afsnit 12,
skriv en linje i quiz-jagten/docs/quizjagten/CHANGELOG.md og beskriv, hvordan jeg tester det manuelt.
```

```text
Brug quiz-jagten/docs/quizjagten/reference/tidslinjen-prototype.html som visuel reference
og implementér opgave F4.4. Port logikken til moduler – kopiér ikke demo-UI'et.
```

---

## 1. Arbejdsregler for Codex

1. **Kortlæg før du ændrer.** Læs den eksisterende struktur, spilformer, Supabase-tabeller, realtime-løsning, service worker og styles. Genbrug det, der findes.
2. **Behold stakken.** Statisk PWA i vanilla HTML/CSS/JS med en klassisk `app.js` (ingen bundler, ingen `package.json` i appen) og Supabase via `supabase-js` fra jsDelivr. Ny funktionalitet lægges i separate filer, der indlæses uden build-trin og kaldes fra `app.js`. Omskriv ikke `app.js` på én gang. Ingen tunge biblioteker.
3. **Kun gratis tjenester.** Projektet skal kunne køre uden betalte tjenester. Ingen betalt analyse, fejllogning eller hosting.
4. **Små, afgrænsede ændringer.** Én opgave pr. ændring. Ingen store omskrivninger, som opgaven ikke beder om.
5. **Bryd ikke det eksisterende.** Dagens quiz, Træning, Survival, Spørg løs, Duel på én telefon, Udfordr en ven, Live på storskærm, Deltag i live-spil og Quizmaster skal virke som før.
6. **Database.** Supabase-projektet deles med GPS Jagten, som bruger schemaet `quiz` – rør det ikke. Quizjagten bruger `public`. Nye tabeller og funktioner får præfikset `qj_`. Migrationer lægges i repoets `supabase/migrations/` med en entydig tidsstempel-version (fx `20261128120000_qj_events.sql`), fordi versionen `002` allerede er brugt to gange. Kun additive ændringer: ingen `DROP` eller omdøbning af kolonner med data. RLS på alle nye tabeller. Klienten skriver kun via `security definer`-RPC'er med inputvalidering (som `log_answers`). Rollback-kommentar i hver migration. Vis SQL'en, før noget destruktivt køres. Opdatér også `quiz-jagten/supabase.sql`, så den beskriver Quizjagtens samlede opsætning.
7. **Sprog.** Dansk er primært sprog. Appen har også engelsk (`UI_EN` i `app.js` og `questions.en.json`), så nye tekster tilføjes på både dansk og engelsk. Brug tekstnøgler uden æøå og tegnsætning. Kode, filnavne, funktioner og kommentarer på engelsk.
8. **Tilgængelighed.** Respektér `prefers-reduced-motion`. Farve er aldrig eneste kendetegn (altid figur, navn eller tekst med). Touch-mål mindst 44 × 44 px. Kontrast mindst WCAG AA.
9. **Ydelse.** Animationer på `<canvas>` eller med CSS transforms. Mål 60 fps. Loft over partikler. Skal virke på en 3 år gammel Android-telefon og i en smart-tv-browser.
10. **Test.** Hver opgave har acceptkriterier. Tilføj eller opdatér Playwright-tests, hvor opgaven siger det, og kør de eksisterende tests.
11. **Afslutning af en opgave.** Opdatér status (afsnit 12), skriv én linje i `docs/quizjagten/CHANGELOG.md`, og beskriv en manuel testvejledning i dit svar.
12. **Afvigelser.** Hvis planen ikke passer til repoet, vælg den løsning, der passer til repoet, og skriv afvigelsen i `CHANGELOG.md` og `NOTES.md`.
13. **Service worker.** Når en fil, der caches, ændres eller tilføjes: øg versionen i `quiz-jagten/sw.js` (i dag `quizjagten-shell-v27`), og tilføj nye filer til shell-listen.
14. **Validering.** Kør `node tools/check-project.mjs` efter hver opgave, og udvid scriptet, når nye datafiler kommer til (fx `timeline.json`).

---

## 2. Mål og principper

**Quizjagten** er en dansk quiz- og selskabsspilsplatform med tre grupper af spil: **Alene**, **To spillere** og **Selskab**. Spørgsmålsbanken har 1.702 spørgsmål i 9 emner (november 2026).

**Produktmål**

- **Hurtigt i gang:** højst 30 sekunder fra QR-kode til første spørgsmål.
- **Flere runder:** det skal være let at fortsætte med næste spil i samme rum.
- **Lyst til at komme igen:** stimer, rekorder, synlige fremskridt og noget, der kan deles.

**Designprincipper**

- **Rytme pr. spørgsmål:** opladning (1,6 s), så afsløring, så reaktion. Pointtavlen opdaterer aldrig med det samme.
- **Én identitet:** hver spiller har en farve og et dyr, som er ens på tv, telefon og delte billeder.
- **Storskærmen er scenen:** de store effekter samles på tv'et. Telefonen er spillerens personlige feedback.
- **Visuel stil som GPS Jagten:** gul accent på næsten sort baggrund.
- **Lav vedligeholdelse:** når noget er lanceret, skal det kunne køre uden løbende arbejde fra Rasmus.

---

## 3. Designsystem

`style.css` har allerede farvetokens i `:root` (bl.a. `--nat`, `--tavle`, `--papir`, `--guld`, statusfarver, kanter og `--font`) og bruger Inter til brødtekst og Syne til overskrifter. **Genbrug dem.** Tabellerne herunder beskriver rollerne; brug de eksisterende tokens, hvor rollen allerede findes (fx `--guld` som accent), og tilføj kun de manglende (svarfarver, spillerfarver, bevægelse).

### 3.1 Farver

| Token | Værdi | Brug |
| --- | --- | --- |
| `--bg` | `#0d0f15` | Baggrund |
| `--panel` | `#151821` | Kort og paneler |
| `--line` | `#262b38` | Kanter |
| `--txt` | `#f2f3f7` | Brødtekst |
| `--mut` | `#8b91a3` | Sekundær tekst |
| `--accent` | `#f2c94c` | Quizjagtens gule (tal, fremhævning, primærknap) |
| `--ok` | `#2fb67c` | Rigtigt |
| `--bad` | `#e5484d` | Forkert |

### 3.2 Svarmuligheder (ens på tv og telefon)

| Svar | Farve | Figur | Tekstfarve |
| --- | --- | --- | --- |
| A | `#e5484d` | ▲ trekant | hvid |
| B | `#3e8ee8` | ◆ ruder | hvid |
| C | `#f2b632` | ● cirkel | `#2a1d00` |
| D | `#2fb67c` | ■ firkant | hvid |

### 3.3 Spilleridentitet

Spilleren vælger selv sit navn. Farve og dyr tildeles automatisk og kan skiftes i lobbyen.

| Dyr | Farve | Dyr | Farve |
| --- | --- | --- | --- |
| Ræven | `#ff4d6d` | Ulven | `#b388ff` |
| Uglen | `#4dabff` | Lossen | `#ff8c42` |
| Bjørnen | `#ffd23f` | Ørnen | `#00e5ff` |
| Haren | `#3ddc97` | Grævlingen | `#ff6ec7` |

Ved flere end 8 spillere genbruges farverne med et andet dyr (udvid listen efter behov).

### 3.4 Typografi og størrelser på storskærm

Storskærmen designes til 1920 × 1080 og skaleres med container query-enheder (`cqh`/`cqw`) eller `transform: scale()`.

| Element | Størrelse ved 1080p |
| --- | --- |
| Spørgsmålstekst (kun spørgsmål) | 72–76 px, vægt 900 |
| Svartekst i felter | 54–60 px |
| Navne | mindst 28 px |
| Point og tal | mindst 48 px, `font-variant-numeric: tabular-nums` |

### 3.5 Bevægelse

| Konstant | Værdi | Brug |
| --- | --- | --- |
| `SUSPENSE_MS` | 1600 | Opladning før afsløring |
| `REVEAL_MS` | 1300 | Pointanimation |
| `BANNER_MS` | 2600 | "Ny fører"-banner |
| Easing, størrelser | easeOutBack | Bobler, kerner, raketter |
| Easing, tal | easeOutCubic | Tal der tæller op |

Ved `prefers-reduced-motion: reduce`: ingen screen shake, ingen konfetti, halve varigheder.

### 3.6 Lyd

- Al lyd laves med Web Audio (ingen lydfiler).
- Lyd spilles fra storskærm, quizmaster og solospil – ikke fra alle telefoner i et live-spil på én gang.
- Lydknap altid synlig for værten (tasten `M`). Valget huskes i `localStorage`.
- `AudioContext` startes ved første tryk (browserkrav).

### 3.7 Tastaturgenveje på storskærmen

| Tast | Funktion |
| --- | --- |
| Mellemrum | Næste / vis svar nu |
| `G` | Skift visning (kun spørgsmål → delt → kun grafik) |
| `V` eller `1`–`5` | Skift pointtavle-visual |
| `M` | Lyd til/fra |
| `F` | Fuldskærm |
| `P` | Pause |

---

## 4. Arkitektur

### 4.1 Filstruktur (tilpasset den eksisterende app)

```text
quiz-jagten/
  index.html · app.js · style.css · config.js · sw.js   eksisterende
  scoreboard.html                     eksisterende canvas-scoreboard (iframe) → opgraderes i F2.1
  questions.json · questions.en.json  spørgsmålsbanken (1.702 hver)
  timeline.json                       nyt: tidslinjekort (F4.1)
  js/live-protocol.js                 nyt: beskeder, snapshot, genforbindelse (F1)
  js/timeline-core.js                 nyt: Tidslinjens rene funktioner (F4.2)
  js/timeline-live.js                 nyt: Tidslinjen på tv og telefon (F4.3–F4.5)
  editor.html · js/editor.js          nyt: indholdsværktøj (F3)
  tools/check-project.mjs             eksisterende validering – udvides
  tests/                              nyt: Playwright med egen package.json (F1.5)
  docs/quizjagten/                    plan, noter, referencer og data
```

Nye filer indlæses med `<script>`-tags (eller `type="module"`) uden build-trin. `app.js` kalder dem via små, tydelige funktioner, så den eksisterende kode ikke skal omskrives.

### 4.2 Pointtavle-motoren

Referenceimplementering: `reference/scoreboard-lab-v2.html`. I dag ligger scoreboardet i `scoreboard.html` og indlejres i appen som iframe. **Behold iframe-løsningen**, opgradér indholdet med v2-motoren, og styr den med `postMessage` – med samme kommandoer som API'et herunder (fx `{ cmd: 'reveal', results }`, `{ cmd: 'setAnswered', id }`). Lærredets `ResizeObserver` virker inde i iframen, når iframen ændrer størrelse.

```js
const board = createScoreboard(canvas, {
  visual: 'bubbles',            // bubbles | rockets | tug | cores | mountain
  goal: 10000,                  // målscore (raketter og bjerg)
  teams: [{ id, name, color, animal }],
  sound: true,
});
board.setAnswered(playerId);    // live "har svaret"-tilstand
board.reveal([{ id, gain, correct, ms }]); // opladning → afsløring → førertjek
board.setVisual('tug');
board.resetRound();
board.on('leader', team => {});
board.on('winner', team => {});
board.destroy();
```

**Visual-plugin-interface:** `init()`, `update(dt)`, `draw(time)`, `anchor(team)` og valgfrit `onResize(sx, sy)`, `onAnswer(team)`, `onReveal()`, `onLeader()`.

**Lærredet tilpasser sig selv:**

- En `ResizeObserver` på lærredets container opdaterer størrelsen. Pixeltæthed højst 2×.
- Under 80 px i højde eller bredde: lærredet regnes som skjult. Tegning og opdatering af visualet pauser, men stillingen regnes stadig ud.
- Ved størrelsesændring skaleres positioner proportionalt, så boblerne ikke hopper.
- Hver visual vælger selv layout ud fra lærredets form (se afsnit 8).

### 4.3 Live-spillets tilstandsmaskine

```text
lobby → intro → question → suspense → reveal → scoreboard
      ↖────────────── næste spørgsmål ─────────────┘
scoreboard (efter sidste spørgsmål) → podium → [næste spil | slut]
```

- **Værten er autoritativ:** værtens enhed (tv eller værtens telefon) beregner point og afgør overgange.
- **Tilstanden gemmes på værtens enhed** (`localStorage`, nøgle `qj-host-<kode>`) efter hver overgang, så værten kan genindlæse uden at miste spillet. Det kræver ingen database. En tabel (`qj_rooms`) indføres først, hvis værten skal kunne skifte enhed midt i et spil.
- **Spillerne** sender kun deres svar og modtager tilstand.

### 4.4 Realtime-beskeder

I dag bruger live-spillet Supabase Realtime: værten opretter kanalen `quiz-<4-tegns-kode>` og sender tilstand som broadcast, deltagerne sender svar, og presence viser, hvem der er tilsluttet. En `hello`-besked får værten til at sende den aktuelle offentlige tilstand. **Byg videre på dette** – behold kanalnavn og 4-tegns-koden.

Nye beskeder får formen `{ type, seq, sentAt, payload }`. Klienter ignorerer beskeder med `seq` lavere end eller lig med den sidst sete. Ved genforbindelse sender klienten `hello` med sit `playerId`, og værten svarer med et fuldt `snapshot`.

| Besked | Fra → til | Indhold |
| --- | --- | --- |
| `hello` (udvidet) | telefon → vært | navn, ønsket dyr, `playerId` (fra `localStorage`, hvis spilleren har været med før) |
| `player_assigned` | vært → telefon | playerId, farve, dyr |
| `presence` | telefon → vært | heartbeat hvert 5. sekund |
| `question_start` | vært → alle | spørgsmålsnr., svarmuligheder, tidsgrænse, `startsAt` |
| `answer` | telefon → vært | valgt svar, svartid i ms |
| `answer_ack` | vært → telefon | bekræftelse (låser svaret) |
| `question_end` | vært → alle | rigtigt svar, point, placering, stime pr. spiller |
| `timeline_round_start` | vært → alle | kort (uden årstal), tidslinjens kort, tidsgrænse |
| `timeline_answer` | telefon → vært | hul-indeks, årstalsgæt, svartid |
| `timeline_reveal` | vært → alle | årstal, rigtige huller, point pr. spiller |
| `game_switch` | vært → alle | næste spil og dets indstillinger |
| `final` | vært → alle | slutstilling og højdepunkter |
| `snapshot` | vært → telefon | fuld tilstand ved (gen)forbindelse |

Tilpas beskednavnene til de eksisterende, hvor de allerede findes i `app.js`.

---

## 5. Data

### 5.1 Det, der findes i dag (fra F0.1)

| Hvad | Hvor | Note |
| --- | --- | --- |
| Spørgsmål | `questions.json` og `questions.en.json` (1.702 hver) | Statiske filer, caches af service workeren og virker offline |
| Svarstatistik | `public.question_stats` (tabel) | RLS, ingen direkte klientadgang |
| Fejlmeldinger | `public.question_reports` (tabel) | RLS, ingen direkte klientadgang |
| Indsendelse | RPC `log_answers(answers jsonb)` og `report_question(...)` | `security definer` |
| Kvalitet | View `public.question_quality` | Beregner svarprocent og **foreslået sværhedsgrad** |
| Live-rum | Supabase Realtime-kanal `quiz-<kode>` | Ingen tabel – værten holder alt i hukommelsen |

### 5.2 Beslutninger

- **Spørgsmål og tidslinjekort forbliver statiske JSON-filer.** Det er gratis, hurtigt, virker offline og kræver ingen vedligeholdelse af en database. Editoren (F3) eksporterer opdaterede JSON-filer, som committes til repoet.
- **Svardata og fejlmeldinger** bruger de eksisterende tabeller, RPC'er og `question_quality`. Lav ikke nye tabeller til det.
- **Live-spillet** klarer genforbindelse og værtsgenoptagelse uden database (afsnit 4.3–4.4).
- **Nye tabeller** oprettes først, når en opgave kræver det, og får præfikset `qj_`.

### 5.3 JSON-format

**Spørgsmål** – behold det eksisterende format i `questions.json`. Tilføj kun disse felter, hvis de mangler, og lad dem være valgfrie, så gamle poster stadig virker:

| Felt | Type | Note |
| --- | --- | --- |
| `explanation` | string | vises ved afsløring |
| `source` | string | påkrævet for nye spørgsmål |
| `status` | string | `draft`, `review`, `live`, `retired` (mangler feltet = `live`) |
| `tags` | string[] | fx `jul`, `em2028` |

**Tidslinjekort** – `timeline.json` er et array af objekter:

| Felt | Type | Note |
| --- | --- | --- |
| `id` | string | stabilt id, fx `tl-0001` |
| `event` / `event_en` | string | begivenheden uden årstal (engelsk valgfri – mangler den, vises dansk) |
| `year` | number | mellem 1000 og indeværende år |
| `month`, `day` | number \| null | tiebreak og forklaring |
| `category` | string | Historie, Kultur, Sport, Videnskab, Teknologi, Musik, Film, Danmark … |
| `region` | string | `dk` eller `world` |
| `difficulty` | number | 1–4 |
| `explanation` / `explanation_en` | string | én linje ved afsløring |
| `source_url` | string | påkrævet før `live` |
| `is_anchor` | boolean | må bruges som startkort |
| `status` | string | kun `live` bruges i spillet |

### 5.4 Nye tabeller (kun når opgaven kræver det)

| Tabel | Opgave | Indhold |
| --- | --- | --- |
| `qj_events` | T1 | statistik uden persondata: `type`, `game`, `at`, `props` (jsonb). Indsættes via RPC `qj_log_event` |
| `qj_client_errors` | T2 | `message`, `stack` (højst 2 kB), `url`, `ua_short`, `app_version`. Indsættes via RPC `qj_log_error` |
| `qj_custom_quizzes` | F8 | `code`, `edit_secret_hash`, `title`, `questions` (jsonb), `status`, `reports_count`, `expires_at` (90 dage) |
| `qj_rooms` | senere | kun hvis værten skal kunne skifte enhed eller tv-parring kræver det |

**Sikkerhed:** RLS på alle tabeller, ingen direkte klientadgang, kun RPC'er med inputvalidering og længdegrænser. Hemmeligheder gemmes kun som hash. Læg aldrig en service-nøgle i klientkoden.

**Oprydning:** udløbne brugerquizzer slettes automatisk (`pg_cron`, hvis den er tilgængelig; ellers ved oprettelse af nye).

---

## 6. Faser og opgaver

Faserne er i den anbefalede rækkefølge: fundamentet først, derefter de spil, der bygger på det. Hver opgave er lavet til at være én Codex-kørsel.

**Oversigt**

| Fase | Indhold | Hvorfor her |
| --- | --- | --- |
| F0 | Kortlægning og designtokens | Codex skal kende repoet, før der ændres noget |
| F1 | Robust live-spil | Går live-spillet ned midt i en fest, kommer folk ikke igen |
| F2 | Storskærm 2.0 og pointtavle-motor | Selve oplevelsen på tv'et og telefonerne |
| F3 | Indholdsværktøj | Tidslinjen kræver mange kort; kvaliteten skal kunne styres |
| F4 | Tidslinjen v1 | Den mest særprægede spilform |
| F5 | Spilleaften v1 og delbar afslutning | Binder spillene sammen og spreder appen |
| F6 | To spillere | Duel og Udfordr en ven får visuals og deling |
| F7 | Alene | Stimer, fremskridt og rekorder |
| F8 | Lav din egen quiz | Foreninger, fødselsdage, skoler – og senere betaling |
| F9 | Quizmaster | Én enhed, ingen storskærm |
| F10 | Udvidelser | Backlog, prioriteret |
| T | Tværgående | Statistik, fejllog, GDPR, offline, kvalitet |

---

### F0 – Kortlægning

#### F0.1 Kortlæg repoet

**Mål:** Codex og Rasmus har et fælles overblik, før der ændres kode.

**Omfang:** Skriv `docs/quizjagten/NOTES.md` med:

- mappestruktur og indgangsfiler
- eksisterende spilformer, og hvor de ligger i koden
- Supabase: tabeller, views, RPC-funktioner, RLS og realtime-løsning
- service worker: hvad der caches, og hvordan versioner håndteres
- styles: farver, skrifttyper, eksisterende komponenter
- eksisterende tests (hvis nogen)
- afvigelser fra denne plan og forslag til tilpasning

**Acceptkriterier**

- [ ] `NOTES.md` findes og dækker alle punkter.
- [ ] Ingen kodeændringer.

#### F0.2 Designtokens

**Mål:** Ét sted for farver, størrelser og bevægelse.

**Omfang:** Genbrug de eksisterende tokens i `:root` i `style.css`. Tilføj kun de manglende fra afsnit 3 (svarfarver A–D, spillerfarver, bevægelseskonstanter) samme sted, og dokumentér dem i en kommentarblok. Tilføj samtidig en fælles `reducedMotion`-hjælper i JavaScript (læser `prefers-reduced-motion`), som scoreboard og nye animationer bruger.

**Acceptkriterier**

- [ ] Ingen synlige ændringer på eksisterende sider.
- [ ] Tokens dokumenteret i toppen af filen.

---

### F1 – Robust live-spil

#### F1.1 Genforbindelse for spillere

**Mål:** En spiller, der mister forbindelsen eller genindlæser, kommer automatisk tilbage med samme navn, farve og point.

**Omfang**

- Gem `playerId`, navn og rumkode i `localStorage` (nøgle `qj-player-<kode>`).
- Ved indlæsning eller tabt forbindelse: tilslut kanalen igen, og send `hello` med `playerId`. Værten genkender spilleren (samme navn, farve og point) og svarer med `snapshot`.
- Ingen database – det bygger på den eksisterende kanal.
- Vis et diskret banner "Forbinder igen …", mens forbindelsen genoprettes.
- Har spilleren allerede svaret på det aktuelle spørgsmål, vises "Svar låst".

**Acceptkriterier**

- [ ] Genindlæsning af telefonen midt i et spørgsmål: spilleren er tilbage inden for 3 sekunder med uændret navn, farve og point.
- [ ] Flytilstand i 10 sekunder og tilbage: spilleren kommer automatisk ind igen.
- [ ] Ingen dubletter af spilleren på storskærmen.

**Test:** Udvid Playwright-testen fra F1.5 med en genindlæsning.

#### F1.2 Værten kan genoptage spillet

**Mål:** Værten kan genindlæse tv'et eller værtens telefon uden at miste spillet.

**Omfang**

- Værtens fulde tilstand (rumkode, spillere, point, spørgsmålsliste, aktuel skærm, `startsAt`) gemmes i `localStorage` (`qj-host-<kode>`) efter hver overgang.
- Ved genindlæsning på samme enhed: tilbyd "Fortsæt spillet", tilslut samme kanal, og send `snapshot` til alle.
- Nedtællingen genskabes ud fra `startsAt`.
- Gemte værtstilstande ældre end 12 timer slettes.

**Acceptkriterier**

- [ ] Genindlæsning af værten under et spørgsmål: samme spørgsmål og korrekt resttid.
- [ ] Genindlæsning under pointtavlen: samme stilling.
- [ ] Spillerne mærker højst et kort "Forbinder igen …".

#### F1.3 Tilstedeværelse

**Mål:** Værten kan se, hvem der stadig er med.

**Omfang**

- Heartbeat hvert 5. sekund.
- Efter 15 sekunder uden heartbeat: spilleren vises gråt med "mistet forbindelse".
- Værten kan fjerne en spiller fra lobbyen.
- "X af Y har svaret" tæller kun forbundne spillere. Spørgsmålet slutter, når alle forbundne har svaret.

**Acceptkriterier**

- [ ] En lukket telefon vises som "mistet forbindelse" inden for 20 sekunder.
- [ ] Spillet venter ikke på frakoblede spillere.

#### F1.4 Testspillere

**Mål:** Live-spillet kan testes uden at samle folk.

**Omfang:** Med `?debug=1` får værten en skjult menu: "Tilføj 8 testspillere". De opfører sig som rigtige spillere og svarer på tilfældige tidspunkter med ca. 60 % rigtige.

**Acceptkriterier**

- [ ] Testspillere kan tilføjes i lobbyen og spiller et helt spil.
- [ ] Menuen er usynlig uden `?debug=1`.

#### F1.5 Automatisk live-test (Playwright)

**Mål:** Et automatisk tjek af, at live-spillet holder.

**Omfang:** `tests/live.spec.js` med 1 vært og 6 spillere i hver sin browserkontekst. `tests/package.json` med `@playwright/test` som devDependency – den påvirker ikke appen, som stadig ikke har en `package.json`. Siden køres lokalt med en HTTP-server (som beskrevet i README). Scenarie: tilmelding via kode, 3 spørgsmål, én spiller genindlæser, værten genindlæser, pointtavle, podie.

**Acceptkriterier**

- [ ] `npx playwright test` kører grønt lokalt.
- [ ] Testen tjekker, at point er ens på vært og telefoner.
- [ ] Kort vejledning i `docs/quizjagten/NOTES.md`.

#### F1.6 Grænser for antal spillere

**Mål:** Ingen ubehagelige overraskelser ved større arrangementer.

**Omfang:** Dokumentér jeres Supabase-plans grænser for samtidige realtime-forbindelser i `NOTES.md`. Indfør et loft over spillere pr. rum (fx 50) med en venlig besked: "Rummet er fuldt".

**Acceptkriterier**

- [ ] Loftet virker og kan ændres ét sted i koden.

---

### F2 – Storskærm 2.0 og pointtavle-motor

#### F2.1 Pointtavle-motor

**Mål:** Én genbrugelig motor med fem visuals, som selv tilpasser sig lærredet.

**Omfang:** Opgradér den eksisterende `scoreboard.html` (iframe) med motoren fra `reference/scoreboard-lab-v2.html`, styret via `postMessage` med kommandoerne fra afsnit 4.2 og opførslen fra afsnit 8. Behold de eksisterende kommandoer, appen sender i dag, så intet går i stykker. Dette indgår:

- de fem visuals: Bobler, Raketter, Tovtræk, Energikerner og Bjergetapen
- automatisk størrelse via `ResizeObserver`, pause når lærredet er skjult
- live "har svaret"-tilstand: dæmpet og stiplet, mens spilleren tænker; tændt, når der er svaret
- opladning, +point der svæver op, "Ny fører"-banner, konfetti, screen shake og vinder-sekvens
- loft over boblestørrelse, så én spiller aldrig fylder hele lærredet
- reduceret bevægelse i JavaScript (ingen screen shake, konfetti eller partikler; kortere animationer) og lyd via Web Audio

**Acceptkriterier**

- [ ] Alle fem visuals virker med 1–12 spillere uden konsolfejl.
- [ ] Raketterne flyver vandret, når lærredet er mere end dobbelt så bredt som højt.
- [ ] Energikernerne ligger på én række på brede lærreder.
- [ ] Skift mellem visuals og størrelser midt i en animation giver ingen fejl eller hop.

#### F2.2 Storskærmens forløb

**Mål:** Et komplet forløb med seks skærme. Se afsnit 7.

**Acceptkriterier**

- [ ] Lobby, intro, svar, afsløring, pointtavle og podie virker i rækkefølge.
- [ ] Svarfordelingen vises først ved afsløringen.
- [ ] Podiet viser 3., 2. og 1. plads én ad gangen og derefter den fulde rangliste.

#### F2.3 Visninger under spørgsmålet

**Mål:** Værten vælger mellem **Kun spørgsmål**, **Delt** og **Kun grafik**. Se `reference/storskaerm-mockup.html`.

**Omfang**

- Tasten `G` skifter visning. Valget huskes til næste spil.
- Layoutet skiftes med CSS grid – grafikken nulstilles ikke.
- **Delt:** spørgsmål og fire svarfelter i et bånd øverst (ca. 40 % af højden), grafikken under.
- **Kun grafik:** spørgsmålet som én linje øverst med en lille nedtællingsring og fire små svarmærker.
- **Kun spørgsmål:** fuld version med 2 × 2 svarfelter og en række af spillerikoner, der lyser op ved svar.

**Acceptkriterier**

- [ ] Skift med `G` under en animation virker uden hop.
- [ ] Teksten kan læses på 5 meters afstand i alle tre visninger (1080p).

#### F2.4 Værtskontroller

**Mål:** Publikum ser ikke værtens knapper.

**Omfang**

- Alle værtsfunktioner via tastatur (afsnit 3.7) eller en lille menu, der vises, når musen bevæges, og skjules efter 3 sekunder.
- Fuldskærmsknap (`F`).
- Indstilling: vis pointtavlen efter hvert, hvert 2. eller hvert 3. spørgsmål.

**Acceptkriterier**

- [ ] Ingen faner, lydknap eller "Vis svar nu" er synlige for publikum under spillet.

#### F2.5 "Åbn på tv" og tv-tilstand

**Mål:** Tv'et kan vise storskærmen uden cast og uden at sløve forbindelsen.

**Omfang**

- En tv-side (fx `#/tv`), hvor tv'ets browser viser en kode/QR. Værten parrer med sin telefon og styrer derfra. Tv'et tilslutter den eksisterende kanal med rollen `display` – der kræves ingen database.
- Tv'et modtager kun små databeskeder og tegner selv animationerne.
- **Tv-tilstand:** falder billedhastigheden under 40 fps i 3 sekunder, skiftes automatisk til færre partikler og ingen skygger.
- Vejledning til brugerne: smart-tv-browser, bærbar via HDMI, eller AirPlay fra en Mac som separat skærm (Apple TV har ingen browser).

**Acceptkriterier**

- [ ] Et tv eller en bærbar kan parres og vise et helt spil styret fra værtens telefon.
- [ ] Tv-tilstand kan også slås til manuelt.

#### F2.6 Telefonens feedback

**Mål:** Telefonen giver hurtig, personlig feedback.

**Omfang**

- Fire store knapper i samme farver og figurer som storskærmen. Spørgsmålsteksten vises som standard. Værten kan vælge "kun figurer".
- Efter svar: "Svar låst" og en rolig venteanimation.
- Afsløring: hele skærmen grøn eller rød, +point, ny placering ("Du er nr. 3, op 2 pladser") og stime-badge ved 2+ rigtige.
- Vibration via `navigator.vibrate` (Android). På iPhone: farve og lyd i stedet.
- Skærmen holdes tændt med Screen Wake Lock, som anmodes igen ved `visibilitychange`.

**Acceptkriterier**

- [ ] Virker på Android (Chrome) og iPhone (Safari).
- [ ] Skærmen slukker ikke under et spil på 15 minutter.

#### F2.7 Lobby

**Mål:** Det skal føles levende, mens folk kommer ind.

**Omfang:** Stor QR-kode og rumkode. Spillerne tikker ind som bobler (pointtavle-motoren) med et blødt "plop". Antal tilmeldte. Startknap til værten.

**Acceptkriterier**

- [ ] Fra scanning af QR til spilleren ses på storskærmen: under 5 sekunder.

---

### F3 – Indholdsværktøj

#### F3.1 Editor

**Mål:** Rasmus kan skrive og rette spørgsmål og tidslinjekort uden at røre koden.

**Omfang:** `editor.html` er en statisk side, der indlæser `questions.json`, `questions.en.json` og `timeline.json`. Lister med søgning og filtre (emne, type, status, sværhedsgrad), en formular pr. element og ændring af status (`draft` → `review` → `live` → `retired`). Ændringer gemmes som kladde i `localStorage`, og knappen "Eksportér" downloader opdaterede JSON-filer, som Rasmus committer til repoet. Siden linkes ikke fra appen og caches ikke af service workeren. Den skriver aldrig til databasen.

**Acceptkriterier**

- [ ] Et nyt spørgsmål kan oprettes, eksporteres og ses i spillet efter commit, når status er `live`.
- [ ] Eksporterede filer består `node tools/check-project.mjs`.
- [ ] Dansk og engelsk holdes synkroniseret (samme id'er i begge filer).

#### F3.2 Import og eksport (CSV)

**Mål:** Mange spørgsmål eller kort kan skrives i Excel og importeres på én gang – direkte til JSON i editoren.

**Omfang**

- Formater: se afsnit 9.4 og `data/`.
- Understøt både semikolon (dansk Excel) og komma som separator, UTF-8 med og uden BOM.
- Forhåndsvisning og validering før import, med en opsummering: "X nye, Y opdateret, Z med fejl".
- Eksport af de samme felter.

**Acceptkriterier**

- [ ] `data/tidslinje-kort-udkast.csv` og `data/spoergsmaal-skabelon.csv` kan importeres uden fejl.
- [ ] Rækker med fejl importeres ikke, og fejlen vises pr. række.

#### F3.3 Validering

**Omfang:** Påkrævede felter; dubletter (normaliseret tekst); årstallet må ikke stå i begivenhedsteksten; 4 unikke svarmuligheder; det rigtige svar skal være blandt dem; sværhedsgrad 1–4; kilde påkrævet før `live`.

**Acceptkriterier**

- [ ] Hver regel har en tydelig dansk fejlbesked.

#### F3.4 Kvalitetskø

**Mål:** Svardata og fejlmeldinger bliver til konkrete opgaver.

**Omfang:** Data hentes fra viewet `question_quality`. Version 1: Rasmus eksporterer viewet som CSV fra Supabase og indlæser filen i editoren. Version 2 (valgfri): en admin-RPC `qj_admin_quality()`, der kræver login med Supabase Auth og en e-mail på en tilladt-liste. En liste i editoren sorteret efter:

1. flest åbne fejlmeldinger
2. lav svarprocent med mange svar (fx under 25 % ved mindst 30 svar)
3. ét forkert svar, der vælges af flere end det rigtige
4. filter: **Mangler forklaring** (spørgsmål uden forklaring vises først; check-project fandt 501 danske spørgsmål uden forklaring)

Handlinger: Ret, Arkivér, Markér som gennemgået.

**Acceptkriterier**

- [ ] Køen bruger `question_quality`, `question_stats` og `question_reports` – ingen nye tabeller.

#### F3.5 Automatisk sværhedsgrad

**Omfang:** Viewet `question_quality` beregner allerede en foreslået sværhedsgrad – brug den. Editoren viser forslag og nuværende værdi side om side, og Rasmus godkender ændringen, som så eksporteres til JSON. Justér kun viewets grænser, hvis de ikke giver mening (forslag: over 80 % = 1, 60–80 % = 2, 40–60 % = 3, under 40 % = 4, ved mindst 30 svar).

**Acceptkriterier**

- [ ] Forslaget vises for alle spørgsmål med mindst 30 svar.

#### F3.6 Blanding af svarmuligheder

**Omfang:** Svarmulighederne blandes ved visning. Det rigtige svar afgøres ud fra værdien, ikke placeringen.

**Acceptkriterier**

- [ ] Over 100 visninger er det rigtige svar fordelt nogenlunde ligeligt på A–D.

---

### F4 – Tidslinjen v1 (fælles tidslinje)

Visuel reference: `reference/tidslinjen-prototype.html`. Regler: afsnit 9.

#### F4.1 Data

**Omfang:** `timeline.json` i formatet fra afsnit 5.3, oprettet ved at importere `data/tidslinje-kort-udkast.csv` i editoren (status `draft`). Rasmus gennemgår kortene og tilføjer kilder, før de sættes til `live`. I editoren tilføjes handlingen "Opret tidslinjekort fra spørgsmål" til de 38 eksisterende årstalsspørgsmål, med manuel omformulering til en begivenhed. `tools/check-project.mjs` udvides til at validere `timeline.json`, og filen tilføjes service workerens shell-liste.

**Acceptkriterier**

- [ ] Alle 37 udkast kan importeres, og startkortene er markeret med `is_anchor`.
- [ ] Spillet bruger kun kort med status `live` og mindst 3 startkort.

#### F4.2 Spillogik (rene funktioner med enhedstests)

**Omfang:** `js/timeline-core.js`:

- `correctGaps(year, timeline)` – alle huller, hvor årstallet passer. Samme år som et nabokort: begge sider tæller.
- `scoreAnswer({ gap, year }, card, timeline)` – se afsnit 10.
- `pickCards(pool, n)` – højst 2 kort fra samme årti pr. spil, en blanding af Danmark/verden og kategorier, og ingen kort fra de seneste 3 spil på denne enhed.
- `pickAnchors(pool)` – 3 startkort spredt over tid.

**Acceptkriterier**

- [ ] Enhedstests for kanttilfælde: første og sidste hul, samme år, tom tidslinje.

#### F4.3 Live-forløb

**Omfang:** Lobby → 10 runder (placér i 20 s → afsløring, med pointtavle efter hver 3. runde) → podie. Bruger beskederne `timeline_round_start`, `timeline_answer` og `timeline_reveal`. Genbruger rum, QR, genforbindelse og testspillere fra F1.

**Acceptkriterier**

- [ ] Et helt spil med 6 testspillere kører uden fejl.
- [ ] Runden slutter, når alle forbundne har svaret, eller tiden er gået.

#### F4.4 Storskærm

**Omfang:** Som prototypen:

- det nye kort centralt med kategori og "Hvornår skete det?"
- vandret tidslinje, jævnt fordelt (ikke i skala), med huller mellem kortene
- spillerstribe med "har svaret"-tilstand

Afsløringen sker i tre trin:

1. spillernes valg falder ned i hullerne (120 ms forskudt)
2. årstallet tæller op (1,1 s)
3. kortet flyver ind på sin plads (FLIP-animation, 0,75 s), det rigtige hul lyser grønt, og pointene popper op

**Mange kort:** fra 14 kort vises et udsnit på 13 kort centreret om det nye kort, plus en minibjælke over hele tidsrummet.

**Acceptkriterier**

- [ ] Animationerne kører glat på en bærbar koblet til et tv.
- [ ] Teksten på kortene kan læses på 5 meters afstand ved 13 kort.

#### F4.5 Telefon

**Omfang:** Lodret liste med kortene og trykbare huller ("Her?"). Det valgte hul udvides til "Dit kort her". En årstalsskyder, der er begrænset til det valgte huls interval. Knappen "Lås svar". Resultatskærm med årstal, forklaring og point.

**Acceptkriterier**

- [ ] Kan betjenes med én hånd på en 6"-telefon.
- [ ] Hullerne er mindst 44 px høje.

#### F4.6 Regler og uafgjort

**Omfang:** Intet svar = 0 point. Ved lige point afgøres placeringen af (1) samlet årstalsafvigelse – lavest vinder – og derefter (2) samlet svartid.

**Acceptkriterier**

- [ ] Reglerne vises kort på storskærmen før første runde.

---

### F5 – Spilleaften v1 og delbar afslutning

#### F5.1 Næste spil i samme rum

**Omfang:** Efter podiet vælger værten næste spil (Quiz, Tidslinjen, senere flere). Spillerne bliver i rummet med samme identitet. Valgfri samlet aftensstilling.

**Acceptkriterier**

- [ ] Skift fra Quiz til Tidslinjen uden at nogen skal scanne igen.

#### F5.2 Aftensoversigt

**Omfang:** Samlet stilling og højdepunkter: hurtigste svar, længste stime, flest præcise årstal og "tættest på uden at ramme".

#### F5.3 Delbart resultatbillede

**Omfang:** Billede på 1080 × 1350 px tegnet på canvas med logo, dato, podie og højdepunkter. Deles via `navigator.share({ files })`, ellers downloades det.

**Acceptkriterier**

- [ ] Billedet kan deles fra Android og iPhone.

#### F5.4 Planlægger (senere)

Værten vælger 20, 45 eller 90 minutter og en blanding af spil, og Quizjagten fører gruppen videre mellem spillene.

---

### F6 – To spillere

#### F6.1 Duel på én telefon

**Omfang:** Kompakt tovtræk øverst. "Send telefonen"-skærm mellem turene (fuld skærm i næste spillers farve, tryk for at fortsætte), som skjuler forrige svar. Slutskærm med genafspilning af tovtrækket.

#### F6.2 Udfordr en ven

**Omfang:** Afsenderens spørgsmål, svar og svartider gemmes, og der laves et link. Modtageren ser efter hvert eget svar et "spøgelse" (om vennen svarede rigtigt, og hvem der var hurtigst). Slutskærmen genafspiller tovtrækket med ca. 0,6 sekunder pr. spørgsmål. Resultatbillede på 1080 × 1080 px med navne, score og en række grønne og røde felter.

#### F6.3 Spørg løs

**Omfang:** Valgfri tæller pr. spiller (+1 ved tryk), når "med point og tur" er valgt.

---

### F7 – Alene

#### F7.1 Dagens quiz

**Omfang:** Dagsstime i `localStorage`. Delbar tekst: "Quizjagten #N · 8/10" med 10 felter (🟩/🟥). Valgfrit: anonym dagsscore i `qj_events` via RPC, så "Du slog X % af dagens spillere" kan vises.

#### F7.2 Træning

**Omfang:** Fremskridt for hvert af de 9 emner som radardiagram eller ringe (SVG, intet bibliotek). Niveauer – Begynder, Kender, Ekspert – ud fra svarprocenten i de seneste 30 svar pr. emne. Efter en træning vises, hvilke emner der steg.

#### F7.3 Survival

**Omfang:** Raket eller bjerg, hvor hvert rigtigt svar er et trin op. Rekorden vises som en streg på banen. Når man er 2 fra rekorden: hjerteslag-lyd og skiftende baggrund. Ved ny rekord: banner og konfetti. Game over-animation og en Igen-knap.

---

### F8 – Lav din egen quiz

#### F8.1 Quizbygger (uden login)

**Omfang:** Titel og 5–30 spørgsmål (multiple choice eller årstal) med live-forhåndsvisning. Når quizzen gemmes (tabel `qj_custom_quizzes` via RPC), fås en kode, et delelink og et privat redigeringslink (`edit_secret`). Quizzen udløber efter 90 dage og kan forlænges.

#### F8.2 Afspilning

**Omfang:** Kan spilles via kode i Live på storskærm eller alene. Mærket "Lavet af en bruger". Knap til at melde fejl eller upassende indhold.

#### F8.3 Grundlæggende moderation

**Omfang:** Længdegrænser, en enkel liste over blokerede ord, højst 10 nye quizzer pr. enhed pr. døgn. Efter 3 anmeldelser skjules quizzen, indtil Rasmus har kigget på den.

#### F8.4 Betaling (senere)

Ikke nu – alt er gratis, indtil det viser sig at blive en succes.

---

### F9 – Quizmaster

#### F9.1 Quizmaster med visual

**Omfang:** Én enhed viser spørgsmålet og det rigtige svar, som er skjult indtil tryk. Et felt pr. hold: tryk giver point, langt tryk fortryder. Kompakt tovtræk ved 2 hold, ellers bjergetapen eller mini-bobler. En kort fanfare ved ny fører. Valgfrit: samme pointtavle på et tv via tv-siden fra F2.5.

---

### F10 – Udvidelser (backlog, prioriteret)

1. **Tættest på:** spørgsmål med et tal som svar ("Hvor høj er Rundetårn i meter?"). Alle gætter med en skyder, og point gives efter den relative afvigelse.
2. **Personlige tidslinjer:** Hitster-lignende variant, hvor hver spiller har sin egen tidslinje. Først til 10 kort, med mulighed for at udfordre en andens placering.
3. **Hvor ligger det?:** tryk på et Danmarkskort (Leaflet + OpenStreetMap). Point: `round(1000 × max(0, 1 − afstand/300 km))`. Overhold OpenStreetMaps regler for brug af kortfliser.
4. **Billedquiz:** billedet går fra sløret til skarpt, og hurtigere svar giver flere point. Kun egne billeder eller billeder med fri licens, med licensfelt.
5. **Jokere i live-spil:** 50/50, dobbelt point og "frys en modstander".
6. **Temapakker:** jul, påske, EM/VM og Melodi Grand Prix via tags og datovinduer.
7. **Udmærkelser:** fx "10 rigtige i træk" og "Alle 9 emner".
8. **Selskabslege på én telefon:** Spionen, Bomben og Mest tilbøjelig til.
9. **Bilquiz:** telefonen læser spørgsmål op gennem bilens højttalere (`speechSynthesis`, dansk stemme). Passagererne svarer på egne telefoner eller med stemmen (`SpeechRecognition`, hvor det understøttes). Føreren rører ikke skærmen.
10. **Google Cast-knap:** tv-siden registreres som Custom Web Receiver i Google Cast Developer Console. Virker fra Chrome på Android og computer, ikke fra iPhone.

---

### T – Tværgående

| ID | Opgave | Acceptkriterium |
| --- | --- | --- |
| T1 | **Statistik uden cookies:** hændelser i `qj_events` via RPC og en oversigt (spil startet og gennemført, frafald pr. skærm) | Ingen cookies og ingen persondata |
| T2 | **Fejllog:** `window.onerror` og `unhandledrejection` sendes til `qj_client_errors` via RPC (dubletter frasorteres, højst 20 pr. session) | Fejl kan slås op i Supabase |
| T3 | **GDPR:** ingen brugerkonti for spillere; spillernavne gemmes kun i hukommelsen og i `localStorage` på enhederne (slettes efter 12 timer); kort privatlivstekst i footeren; ingen tredjeparts-trackere | Privatlivstekst findes |
| T4 | **Offline:** service workeren cacher allerede app-skallen og `questions.json` (netværk først for spørgsmål). Afprøv og dokumentér, at Alene-tilstandene virker uden net, og tilføj en besked ved ny version: "Ny version – genindlæs" | Dagens quiz og Træning virker i flytilstand efter første besøg |
| T5 | **Kvalitet:** Lighthouse PWA og tilgængelighed på mindst 90 på forsiden og storskærmen | Rapport i `NOTES.md` |
| T6 | **Versionering:** versionsnummer i footeren og `CHANGELOG.md` | Opdateres ved hver opgave |

---

## 7. Spec: Storskærmens forløb

| # | Skærm | Indhold | Effekter og lyd |
| --- | --- | --- | --- |
| 1 | Lobby | Stor QR-kode og rumkode, antal tilmeldte, startknap til værten | Spillerne tikker ind som bobler med et blødt "plop" |
| 2 | Intro | "Spørgsmål 3 af 15", emne og sværhedsgrad (ca. 3 s) | Emnet gløder op, kort stigende tone |
| 3 | Svar | Spørgsmål, 4 farvekodede svar med figurer, nedtællingsring, "X af Y har svaret" | Spillerne lyser op, når de svarer. Svarfordelingen vises først ved afsløringen |
| 4 | Afsløring | Det rigtige svar, antal svar pr. mulighed, hurtigste svar ("Uglen, 1,8 sek.") | Forkerte svar falmer, det rigtige får hvid kant og flueben |
| 5 | Pointtavle | Den valgte visual + placeringsliste med pile op og ned + overskrift ("Uglen overtog føringen") + nedtælling til næste spørgsmål | Opladning, +point, banner og konfetti ved ny fører |
| 6 | Podie | 3., 2. og 1. plads løftes op én ad gangen, derefter den fulde rangliste | Trommehvirvel, konfetti og fanfare til 1. pladsen |

**Visninger under spørgsmålet (F2.3)**

| Visning | Spørgsmål | Grafik | Bedst til |
| --- | --- | --- | --- |
| Kun spørgsmål | Hele skærmen, 2 × 2 svarfelter, række af spillerikoner | Pauser (stillingen regnes stadig) | Lange eller svære spørgsmål |
| Delt | Bånd øverst (ca. 40 %) med 4 svarfelter på én række | Resten af skærmen, live | Standardvisningen |
| Kun grafik | Én linje med nedtællingsring og 4 små svarmærker | Næsten hele skærmen | Når spillerne kan se spørgsmålet på telefonen |

---

## 8. Spec: Pointtavle-visuals

| Visual | Opførsel | Bredt, lavt lærred (delt visning) | "Har svaret" live | Bruges i |
| --- | --- | --- | --- | --- |
| Bobler | Areal = andel af alle point (med loft). Føreren trækkes mod midten og skubber de andre ud. Kronen hopper over ved føringsskifte | Mindre bobler og stærkere lodret tyngdekraft, så de spreder sig vandret | Hvid ring og lille hop | Standard på storskærm, lobby |
| Raketter | Baner, kameraet følger føreren, bagerste får en pil med afstanden | Flyver vandret mod målet til højre (bredde/højde > 2) | Lille pilotflamme tændes | Storskærm med fast mål, Survival |
| Tovtræk | Fuld bjælke delt efter andel, gnist og lyn i hvert skel, screen shake ved store spring | Passer uden ændringer; teksten skalerer med højden | Gnister fra holdets del af bjælken | Duel, Udfordr en ven, Quizmaster |
| Energikerner | Lyskugler (én pr. ca. 70 point), farve fra blå over orange til hvid, ringe drejer hurtigere ved stime | Alle kerner på én række (bredde/højde > 2,2) | Én puls | Alternativt tema |
| Bjergetapen | Ryttere på en farvet stigningsprofil, føreren i prikket bjergtrøje, afstand i point på skiltene | Profilen bliver lavere, skiltene holdes inden for kanten | Rytteren rejser sig i pedalerne | Storskærm, Survival, Quizmaster |

**Fælles for alle:** 1,6 s opladning, +point der svæver op, banner og konfetti ved ny fører, screen shake ved store spring (slås fra ved reduceret bevægelse), stime-badge fra 2 rigtige i træk og vinder-sekvens ved målscore.

---

## 9. Spec: Tidslinjen

### 9.1 Forløb

1. Værten opretter et rum, og spillerne tilmelder sig via QR eller kode.
2. Tidslinjen starter med 3 startkort spredt over tid.
3. Hver runde ser alle den samme nye begivenhed uden årstal.
4. Hver spiller vælger på sin telefon et hul i den fælles tidslinje og gætter et årstal inden for hullets interval (20 sekunder).
5. Afsløring: valgene falder ned i hullerne, årstallet tæller op, kortet flyver ind på sin plads, og pointene vises.
6. Efter hver 3. runde vises pointtavlen. Efter 10 kort: podie.

### 9.2 Regler

- **Rigtigt hul:** kortets årstal ligger mellem nabokortenes årstal (inklusive).
- **Samme år** som et nabokort: begge sider af nabokortet tæller som rigtige.
- **Intet svar:** 0 point.
- **Uafgjort:** (1) lavest samlet årstalsafvigelse, (2) lavest samlet svartid.

### 9.3 Sådan skrives et godt tidslinjekort

| Regel | Dårligt | Godt |
| --- | --- | --- |
| Årstallet må ikke stå i teksten | "Danmark vinder EM 1992" | "Danmark vinder EM i fodbold" |
| Begivenheden skal kun kunne betyde ét år | "Anden Verdenskrig" | "Anden Verdenskrig slutter i Europa" |
| Konkret handling | "Storebæltsbroen" | "Storebæltsbroen åbner for biler" |
| Kort tekst (højst ca. 60 tegn) | En hel sætning med bisætninger | Én klar begivenhed |
| Forklaringen tilføjer noget | "Det skete i 1973" | "Medlemskabet trådte i kraft 1. januar 1973" |
| Kilde før `live` | – | Link til en pålidelig kilde |

Bland Danmark og verden, kategorier og århundreder. Det bliver automatisk sværere, efterhånden som tidslinjen fyldes, og hullerne bliver smallere. Med ca. 20 kort pr. spil skal der groft regnet 200–300 kort til, før det ikke gentager sig for ofte.

### 9.4 CSV-formater

CSV bruges kun til import i editoren, som omsætter til JSON. Separator: semikolon (dansk Excel) eller komma. Tegnsæt: UTF-8. Første række er overskrifter.

**Tidslinjekort** (`data/tidslinje-kort-udkast.csv`)

```text
event;year;month;day;category;region;difficulty;is_anchor;explanation;source_url;status
Danmark bliver medlem af EF;1973;1;1;Historie;dk;1;false;Medlemskabet trådte i kraft 1. januar 1973.;;draft
```

**Spørgsmål** (`data/spoergsmaal-skabelon.csv`)

```text
type;text;option_a;option_b;option_c;option_d;correct;category;difficulty;explanation;source;tags;status
mc;Hvad er det kemiske symbol for ilt?;Ox;I;C;O;O;Videnskab;1;Ilt hedder oxygen på latin.;;;draft
```

`correct` er værdien af det rigtige svar, ikke bogstavet.

---

## 10. Point og formler

| Spil | Regel | Point |
| --- | --- | --- |
| Quiz | Rigtigt svar efter svartid | `round(1000 × (1 − svartid / (2 × tidsgrænse)))`, dvs. 500–1000 |
| Quiz | Stimebonus fra 3. rigtige i træk | +100 pr. rigtigt svar i træk, højst +500 |
| Tidslinjen | Rigtigt hul | +500 |
| Tidslinjen | Årstalsgæt | præcist +500 · ±2 år +300 · ±5 år +100 |
| Tættest på (F10) | Relativ afvigelse | `round(1000 × max(0, 1 − abs(gæt − svar) / abs(svar)))` |
| Hvor ligger det? (F10) | Afstand | `round(1000 × max(0, 1 − afstand/300 km))` |

Point rundes til nærmeste 10.

---

## 11. UI-tekster (dansk)

| Nøgle | Tekst |
| --- | --- |
| `answers.count` | "{n} af {total} har svaret" |
| `answer.locked` | "Svar låst – kig op på skærmen" |
| `reconnecting` | "Forbinder igen …" |
| `player.lost` | "Mistet forbindelse" |
| `room.full` | "Rummet er fuldt" |
| `suspense` | "Svarene tælles op …" |
| `leader.new` | "Ny fører: {navn}" |
| `leader.first` | "Første fører: {navn}" |
| `winner` | "{navn} vinder!" |
| `next.in` | "Næste spørgsmål om {s} sek." |
| `timeline.ask` | "Hvornår skete det? Placér kortet på tidslinjen" |
| `timeline.tap` | "Tryk hvor kortet skal ligge" |
| `timeline.here` | "Dit kort her" |
| `timeline.guess` | "Dit gæt på årstallet" |
| `timeline.right` | "Rigtigt hul!" |
| `timeline.wrong` | "Forkert hul" |
| `timeout` | "Tiden løb ud" |
| `update.available` | "Ny version – genindlæs" |

---

## 12. Status (Codex opdaterer)

- [x] F0.1 Kortlæg repoet
- [x] F0.2 Designtokens
- [x] F1.1 Genforbindelse for spillere
- [ ] F1.2 Værten kan genoptage spillet
- [ ] F1.3 Tilstedeværelse
- [ ] F1.4 Testspillere
- [ ] F1.5 Automatisk live-test
- [ ] F1.6 Grænser for antal spillere
- [ ] F2.1 Pointtavle-motor
- [ ] F2.2 Storskærmens forløb
- [ ] F2.3 Visninger under spørgsmålet
- [ ] F2.4 Værtskontroller
- [ ] F2.5 "Åbn på tv" og tv-tilstand
- [ ] F2.6 Telefonens feedback
- [ ] F2.7 Lobby
- [ ] F3.1 Editor
- [ ] F3.2 Import og eksport (CSV)
- [ ] F3.3 Validering
- [ ] F3.4 Kvalitetskø
- [ ] F3.5 Automatisk sværhedsgrad
- [ ] F3.6 Blanding af svarmuligheder
- [ ] F4.1 Tidslinjen: data
- [ ] F4.2 Tidslinjen: spillogik
- [ ] F4.3 Tidslinjen: live-forløb
- [ ] F4.4 Tidslinjen: storskærm
- [ ] F4.5 Tidslinjen: telefon
- [ ] F4.6 Tidslinjen: regler og uafgjort
- [ ] F5.1 Næste spil i samme rum
- [ ] F5.2 Aftensoversigt
- [ ] F5.3 Delbart resultatbillede
- [ ] F5.4 Planlægger (senere)
- [ ] F6.1 Duel på én telefon
- [ ] F6.2 Udfordr en ven
- [ ] F6.3 Spørg løs
- [ ] F7.1 Dagens quiz
- [ ] F7.2 Træning
- [ ] F7.3 Survival
- [ ] F8.1 Quizbygger
- [ ] F8.2 Afspilning af brugerquizzer
- [ ] F8.3 Grundlæggende moderation
- [ ] F8.4 Betaling (senere)
- [ ] F9.1 Quizmaster med visual
- [ ] T1 Statistik uden cookies
- [ ] T2 Fejllog
- [ ] T3 GDPR
- [ ] T4 Offline
- [ ] T5 Kvalitet (Lighthouse)
- [ ] T6 Versionering

---

## 13. Referencefiler

| Fil | Hvad den viser | Brug den til |
| --- | --- | --- |
| `reference/scoreboard-lab-v2.html` | Alle fem visuals, de tre visninger (`G`), selvtilpassende lærred, live "har svaret", spørgsmålsforløb | F2.1, F2.3, F2.7, F6, F7.3, F9 |
| `reference/storskaerm-mockup.html` | Statisk mockup af storskærmens skærme: kun spørgsmål, delt, kun grafik, afsløring, pointtavle med placeringsliste | F2.2, F2.3, F2.6 |
| `reference/tidslinjen-prototype.html` | Tidslinjen med tv og telefon side om side, simulerede spillere, afsløringssekvens og point | F4.4, F4.5 |
| `data/tidslinje-kort-udkast.csv` | 37 udkast til tidslinjekort (3 startkort), uden kilder | F3.2, F4.1 |
| `data/spoergsmaal-skabelon.csv` | Skabelon til import af spørgsmål | F3.2 |

Referencefilerne er prototyper. Port logikken til rigtige moduler, og fjern demo-knapper og simulerede spillere (undtagen testspillerne fra F1.4).

---

## 14. Åbne beslutninger (Rasmus)

- [x] Hvilken realtime-løsning bruger live-spillet i dag? Supabase Realtime broadcast + presence på kanalen `quiz-<kode>` (F0.1).
- [ ] Skal Tidslinjen findes på engelsk fra start, eller først når kortene er oversat?
- [ ] Skal værten kunne skifte enhed midt i et spil? (kræver tabellen `qj_rooms`)
- [ ] Skal Dagens quiz-resultater gemmes anonymt centralt, så "Du slog X %" bliver muligt?
- [ ] Dyr som avatarer, eller kun navne og farver?
- [ ] Maksimalt antal spillere pr. rum (forslag: 50 – afhænger af Supabase-planens grænser, se F1.6)?
- [ ] Hvilke selskabslege skal med først: Spionen, Bomben eller Mest tilbøjelig til?
- [ ] Hvornår skal "Lav din egen quiz" kunne koste penge – og hvad skal være gratis?
