# English question bank

The app uses `questions.en.json`, which contains the English version of all
1,702 questions. The app offers a **Dansk / English** selector when this file
is available. The selected language is saved on the device, and the English
bank is cached for offline use. Danish IDs and metadata are preserved so daily
quizzes, reports, and saved results continue to work.

## Optional DeepL workflow

DeepL is not needed for the existing English bank. Use this workflow only if
you specifically want to regenerate it with DeepL.

1. In the GitHub repository, open **Settings → Secrets and variables → Actions**.
2. Add a repository secret named `DEEPL_API_KEY` with the DeepL API key.
3. Open **Actions → Translate Quizjagten questions to English → Run workflow**.
4. The workflow creates and commits `quiz-jagten/questions.en.json`. Review the
   translated questions before making the deployment available.

DeepL Free keys ending in `:fx` use the Free API endpoint automatically. Other
keys use the Pro endpoint. For a local run, set `DEEPL_API_KEY` in the shell
environment and run `python tools/translate_questions_deepl.py` from this
directory. Do not put the key in `config.js`, the app, or a committed file.

## Maintain the bank without DeepL

Keep the Danish file as the source of truth. Preserve question order, IDs, categories, difficulty, status, and type, and translate only the text fields (`spoergsmaal`, `korrekt`, `forkerte`, and `forklaring`). Save the result as `questions.en.json`, then run the check from the repository root:

```sh
node quiz-jagten/tools/check-project.mjs
```

This checks ID/order parity and answer counts. Review factual names, dates and answer meanings before deploying the English bank. No translation API key is needed for this route.
