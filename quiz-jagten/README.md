# Quizjagten

Quizjagten er en selvstændig webapp i GPS Jagten-repositoriet. Den kan installeres som PWA og spiller uden konto eller server. Supabase er valgfrit og bruges til live-spil, svarstatistik og fejlmeldinger.

## Supabase

1. Opret et nyt projekt på Supabase, fx **quizjagten**. Vælg region **Central EU (Frankfurt)**.
2. Åbn **SQL Editor**, indsæt hele `supabase.sql`, og vælg **Run**. Filen er idempotent og kan køres igen uden at slette data.
3. Find **Project URL** og en **publishable key** (eller den ældre anon public key) under **Project Settings → API Keys**. Brug aldrig en `service_role`- eller secret key i browseren.
4. Sæt værdierne i `config.js`:

   ```js
   SUPABASE_URL: "https://dit-projekt.supabase.co",
   SUPABASE_ANON_KEY: "sb_publishable_...",
   ```

5. For live-spil skal Realtime være aktiveret. Kontrollér **Realtime → Settings**, hvis klienter ikke kan oprette forbindelse.

Statistik og fejlmeldinger bruger kun de to RPC-funktioner i SQL-filen. RLS er slået til på tabellerne, anon kan ikke læse tabellerne direkte, og klienten får aldrig en privilegeret nøgle.

## Hvad appen gemmer

- Svar fra træning, dagens quiz, survival, duel, udfordringer og live-spil sendes samlet efter cirka fire sekunder eller straks, når køen når ti svar. Uden Supabase gemmes svarene ikke på serveren.
- I **Spørg løs** registreres point, men ikke når spilleren bruger hjælpen med svarmuligheder. Uden spillere logges intet.
- I **Quizmaster** tæller hvert hold som ét svar. Hold, værten ikke markerer, tæller som forkerte.
- Fejlmeldinger indeholder spørgsmåls-id, kategori og en valgfri kommentar på højst 500 tegn.

## Statistik i SQL Editor

Svarprocent og foreslået niveau (vises efter mindst 30 svar):

```sql
select * from question_quality order by answered desc;
```

Nye fejlmeldinger:

```sql
select * from question_reports order by created_at desc;
```

Når et spørgsmål er rettet i `questions.json`, kan dets fejlmeldinger ryddes sådan:

```sql
delete from question_reports where question_id = 'his-0001';
```

Det foreslåede niveau er kun en tommelfingerregel. Tilfældige gæt rammer i gennemsnit 25 % ved fire svarmuligheder og 50 % ved sandt/falsk.

## Kør lokalt

Start en lokal webserver fra denne mappe:

```sh
python -m http.server 8000
```

Åbn `http://localhost:8000`. Service worker og installation virker på localhost eller HTTPS.

## Udgiv

Mappen kan udgives som undermappe på GitHub Pages, fx `/quiz-platform/quiz-jagten/`. Stierne i appen er relative. `questions.json` indeholder en lille startbank; udvid den med spørgsmål i samme format, før du deler quizzen bredt.

## Spørgsmålsformat

Hvert spørgsmål har et id i formatet `abc-0001`, en kategori, niveau 1–4, `status` (`godkendt` eller `kladde`), spørgsmålet, korrekt svar, tre forkerte svar og en forklaring. Id-formatet bruges også ved indsendelse af statistik og fejlmeldinger.

## Kreditering af eksterne spørgsmål

73 spørgsmål er oversat og bearbejdet fra [The Trivia API](https://the-trivia-api.com/), som er udgivet under [Creative Commons Attribution-NonCommercial 4.0](https://creativecommons.org/licenses/by-nc/4.0/). Oversættelser og forklaringer er redigeret. De enkelte poster i `questions.json` indeholder API-id og eventuelle kildehenvisninger.

## Danske Trivia-spørgsmål

38 spørgsmål er hentet via API fra [psch.dk - Trivia Quizdatabase](https://psch.dk/?v=quiz). API’ets svar indeholder et obligatorisk `credit_html`; appens forside viser kildeangivelsen: ?Spørgsmål er hentet fra psch.dk - Trivia Quizdatabase?. De enkelte poster i `questions.json` gemmer API-id, men aldrig API-nøglen.
