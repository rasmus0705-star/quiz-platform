# Ændringslog – Quizjagten

Én linje pr. færdig opgave: `ÅÅÅÅ-MM-DD · opgave-id · kort beskrivelse`. Afvigelser fra planen noteres med **Afvigelse:**.

- 2026-11-28 · PLAN · Implementeringsplan v1.0 oprettet med referencefiler og eksempeldata.
- 2026-11-28 · F0.1 · Kortlægning udført af Codex (NOTES.md).
- 2026-11-28 · PLAN v1.1 · Planen tilpasset kortlægningen: stier relativt til `quiz-jagten/`, spørgsmål og tidslinjekort som JSON, live-genforbindelse uden database, scoreboard via iframe/postMessage, `qj_`-præfiks og tidsstempel-migrationer, engelsk med, service worker-version.
- 2026-11-28 · F0.2 · Tilføjet semantiske svar-/spillerfarver, fælles bevægelsestokens og reduced-motion-hjælper til app og scoreboard; eksisterende standardvisning bevaret.
- 2026-11-28 · Oprydning · Samlet plan og ændringslog i docs/quizjagten, flyttet motion-helper til js/ og tilføjet mangler-forklaring-filter til F3.4.
- 2026-11-28 · F1.1 · Tilføjet spilleridentitet pr. rum, automatisk genforbindelse via hello/snapshot, låst-svar-visning og diskret forbindelsesbanner uden database.
