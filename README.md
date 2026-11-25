# Quiz Platform

Repoet rummer to statiske webapps:

- **GPS Jagten** ligger i repoets rod.
- **Quizjagten** ligger i `quiz-jagten/`.

Der er intet buildtrin. Kør en lokal webserver fra repoets rod:

```sh
python -m http.server 8000
```

Åbn derefter `http://localhost:8000/` for GPS Jagten eller `http://localhost:8000/quiz-jagten/` for Quizjagten. Quizjagten har en statisk bankkontrol:

```sh
node quiz-jagten/tools/check-project.mjs
```

## Udgivelse og drift

Sitet er beregnet til GitHub Pages på `rasmus0705-star.github.io/quiz-platform/`, hvis Pages er aktiveret på repoets `main`-gren. Push alene ændrer ikke Supabase: SQL-migrationer og Edge Functions skal også være deployed i Supabase-projektet.

Før GPS Jagten bruges kommercielt, skal udkastene til privatlivspolitik, databehandleraftale og vilkår udfyldes med de faktiske virksomheds- og leverandøroplysninger og gennemgås juridisk. Supabase-konfiguration og offentlige skrive-RPC’er kræver også løbende drifts- og misbrugsbeskyttelse.

Quizjagtens engelske bank er valgfri og findes ikke endnu. Dens danske bank har 1.702 spørgsmål; projektkontrollen advarer om 501 tomme forklaringer.
