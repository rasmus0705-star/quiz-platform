# English question bank

The app uses a separate, generated `questions.en.json` file. The DeepL key is
used only by GitHub Actions and is never sent to the browser or saved in the
repository. The English file keeps the Danish question IDs and metadata so
daily quizzes, reports, and saved results continue to work.

## Generate the translation

1. In the GitHub repository, open **Settings → Secrets and variables → Actions**.
2. Add a repository secret named `DEEPL_API_KEY` with the DeepL API key.
3. Open **Actions → Translate Quizjagten questions to English → Run workflow**.
4. The workflow creates and commits `quiz-jagten/questions.en.json`. Review the
   translated questions before making the deployment available.

DeepL Free keys ending in `:fx` use the Free API endpoint automatically. Other
keys use the Pro endpoint. For a local run, set `DEEPL_API_KEY` in the shell
environment and run `python tools/translate_questions_deepl.py` from this
directory. Do not put the key in `config.js`, the app, or a committed file.

Once the English JSON file is deployed, the home page shows a **Dansk / English**
selector. The selection is saved on the device and the English bank is cached
for offline use.

## Without DeepL

The bank can also be translated manually in small batches with an editor or an AI assistant. Keep the Danish file as the source of truth, preserve the question order, IDs, categories, difficulty, status and type, and translate only the text fields (`spoergsmaal`, `korrekt`, `forkerte`, and `forklaring`). Save the result as `questions.en.json`, then run:

```sh
node tools/check-project.mjs
```

This checks ID/order parity and answer counts. Review factual names, dates and answer meanings before deploying the English bank. No translation API key is needed for this route.
