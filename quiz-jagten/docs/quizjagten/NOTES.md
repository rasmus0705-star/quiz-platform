# F0.1 – Kortlægning af Quizjagten

Kortlægningen er udført uden ændringer i appens kode. Planpakken var allerede pakket ud i `quiz-jagten/docs/quizjagten/`, som vist på skærmbilledet. Det er Quizjagtens appmappe under det samlede `quiz-platform`-repo; planens `docs/quizjagten/...`-stier skal derfor læses relativt til `quiz-jagten/`.

## Mappestruktur og indgangsfiler

- Repo-roden indeholder også GPS Jagten, dens `index.html`, `sw.js`, `board/` og Supabase-projekt. Quizjagten ligger som selvstændig statisk PWA i `quiz-jagten/`.
- `quiz-jagten/index.html` indlæser `config.js`, `app.js`, `style.css` og lokale skrifttyper. Der er ingen bundler eller `package.json`; appen er vanilla HTML/CSS/JS.
- `quiz-jagten/app.js` indeholder UI, spiltilstande, spørgsmålspulje, scoring, Supabase-klient og live-vært/-deltager-flow.
- `quiz-jagten/scoreboard.html` er canvas-scoreboardet, indlejret i appen via iframe. `board/scoreboard.html` i repo-roden tilhører den øvrige GPS Jagten-app.
- Spørgsmålene er lokale JSON-filer: `questions.json` og `questions.en.json`, begge med 1.702 poster. `config.js` indeholder klientkonfiguration; nøgleværdier er ikke kopieret ind i disse noter.
- Planens prototyper og data ligger under `quiz-jagten/docs/quizjagten/{reference,data}/`. CSV'en har 37 tidslinjekort, heraf 3 startkort; alle står som `draft`, og ingen har en `source_url` endnu.

## Spilformer og placering i koden

- Forside og routing: `home()` i `app.js`.
- Dagens quiz: `dagens()`, `dailyQuestions()`, `dagResultat()`.
- Træning: `traening()` og de fælles opsætnings-/spørgsmålsfunktioner.
- Survival: `survival()`.
- Spørg løs: `spoergSetup()` og `spoergPlay()`.
- Duel på én telefon: `duelSetup()`, `duelPlay()`.
- Udfordr en ven: `udfordrSetup()`, `playChallenge()`, `receiveChallenge()` og `compareView()`.
- Quizmaster: `quizmasterSetup()` og `quizmasterPlay()`.
- Live på storskærm: `liveHostSetup()` og `liveHost()`.
- Deltagerflow: `liveJoin()`, `scanLiveQr()` og `livePlayer()`.
- Spørgsmålsvalg, historik og sværhedsfordeling ligger samlet omkring `pick()`, `pickMixed()` og `pickSet()`.

## Supabase: tabeller, views, RPC, RLS og realtime

Quizjagtens aktuelle statistik-/fejlmeldings-setup står i `quiz-jagten/supabase.sql`:

- `public.question_stats` og `public.question_reports`, begge med RLS slået til og uden direkte klientadgang.
- RPC-funktionerne `public.log_answers(answers jsonb)` og `public.report_question(...)` er `security definer` og har begrænset inputvalidering.
- Viewet `public.question_quality` beregner svarprocenter og foreslået sværhedsgrad. README beskriver, hvordan ejer kan slå resultater og fejlmeldinger op.

Livequizzen bruger Supabase Realtime gennem `supabase-js` fra jsDelivr. Værten opretter en kanal `quiz-<4-tegns-kode>` og sender spiltilstand som broadcast. Deltagere sender svar; presence viser, hvem der er tilsluttet. Værten beregner point og holder spillere, svar og spiltilstand i hukommelsen. Der findes ikke en `rooms`- eller `room_players`-tabel for Quizjagten, ingen gemt versioneret room-state og ingen fuld snapshot-/sync-request-protokol. `hello` får værten til at sende den aktuelle offentlige tilstand, men værten kan ikke gendanne spillet efter genindlæsning.

Repoets `supabase/migrations/` indeholder migrations til GPS Jagten i schemaet `quiz` og peger på samme Supabase-projekt som Quizjagtens klientkonfiguration. Quizjagtens statistik bruger derimod `public`-schemaet. Ved nye Quizjagt-DB-ændringer skal migrationerne lægges i den eksisterende mappe og afgrænses til de relevante `public`-objekter. Der findes allerede to migrationsfiler med versionspræfikset `002`; brug en ny entydig, tidsstempelbaseret version til kommende ændringer, og følg planens additive/RLS-regler.

## Service worker og cache

`quiz-jagten/sw.js` registreres fra appens `init()`. Den aktuelle shell-cache hedder `quizjagten-shell-v27`; ved aktivering slettes ældre caches med præfikset `quizjagten-`. Navigation forsøger netværk først og falder tilbage til cache. Øvrige lokale assets bruger cache først. Spørgsmåls-JSON hentes netværk-først og gemmes efter et vellykket svar, med cache som offline-fallback. `questions.json` er i shell-listen; engelsk JSON caches, når den er hentet. Ved ændringer af cachede appfiler skal cacheversionen øges.

## Styles og komponenter

- Primære styles ligger i `quiz-jagten/style.css`; der findes ikke en separat tokens-fil.
- `:root` har allerede farvetokens, bl.a. `--nat`, `--tavle`, `--papir`, `--guld`, statusfarver, kanter og `--font`.
- Typografi er lokal: Inter til brødtekst og Syne til overskrifter (`fonts/fonts.css`).
- Genbrugelige klasser omfatter `.screen`, `.top`, `.btn`, `.mode`, `.tile`, `.qmeta`, `.board`, `.teams` samt live-/scoreboard-layouts.
- Der er responsive regler og fokusmarkeringer. `prefers-reduced-motion` slår CSS-overgange fra, men canvas-/JavaScript-animationer har ikke en samlet reduceret-bevægelse-indstilling endnu.

## Eksisterende tests

- `quiz-jagten/tools/check-project.mjs` validerer spørgsmål, oversættelser og syntaks i app/scoreboard.
- Der er ingen `package.json`, Playwright-konfiguration eller automatiserede browser-/multiklienttests i repoet.
- `quiz-jagten/README.md` dokumenterer manuel lokal kørsel via en HTTP-server.

## Afvigelser fra planen og tilpasninger

1. Planens mappestruktur er et forslag. Den nuværende app er en klassisk `app.js` uden ES-moduler. Moduler kan indføres gradvist uden et build-trin; undgå en stor omskrivning af alle spil på én gang.
2. Repoet indeholder både GPS Jagten og Quizjagten. Planens `docs/quizjagten/` ligger under Quizjagtens projektmappe, som skærmbilledet viser. Repoets fælles migrationsmappe og `board/` må ikke forveksles med Quizjagtens `supabase.sql` og `scoreboard.html`.
3. Planens varige rum, spilleridentiteter, reconnect og værtsgenoptagelse kræver ny, additiv database-/RPC-funktionalitet. Det findes ikke i den nuværende broadcast-/presence-løsning. Brug unikke migrationsversioner, RLS på nye tabeller og rollback-kommentarer; slet eller omdøb ikke eksisterende data.
4. De 37 tidslinjekort er kun udkast uden kilder. De skal gennemgås og have kildehenvisninger via editor-/reviewflow, før status ændres til live.
5. UI-tekster lokaliseres i dag primært gennem `UI_EN`-opslag i `app.js`, mens den nye plan kræver dansk UI. Nye flows bør tilføje komplette tekster for de understøttede sprog og undgå tekstnøgler, der fejler ved tegnsætning/æøå.
6. Den nuværende animationstilgængelighed dækker kun CSS-overgange. Nye storskærms-/scoreboard-effekter skal også kunne reduceres eller slås fra i JavaScript.

## Anbefalet rækkefølge

Følg planens faser, men begynd F1 med en konkret besked-/room-state-protokol og entydige migrationsversioner. Byg derefter editorens kildekrav og validering, før tidslinjekort publiceres. Genbrug eksisterende farvetokens, fonte, spilopsætning, QR-/rumflow og scoreboard, og port referenceprototypernes logik frem for demo-UI.
