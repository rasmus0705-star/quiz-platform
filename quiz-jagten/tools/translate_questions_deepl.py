#!/usr/bin/env python3
"""Create the English question bank from questions.json with the DeepL API.

Set DEEPL_API_KEY in the environment. Free API keys ending in :fx use the
DeepL Free endpoint automatically. No credentials are written to disk.
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "questions.json"
TARGET = ROOT / "questions.en.json"
FIELDS = ("spoergsmaal", "korrekt", "forklaring")
BATCH_SIZE = 40


def translate_batch(texts: list[str], key: str) -> list[str]:
    endpoint = os.environ.get("DEEPL_API_URL")
    if not endpoint:
        endpoint = "https://api-free.deepl.com" if key.endswith(":fx") else "https://api.deepl.com"
    payload = json.dumps({
        "text": texts,
        "source_lang": "DA",
        "target_lang": "EN",
        "context": "Danish general-knowledge quiz. Preserve names, numbers, and factual meaning.",
    }).encode("utf-8")
    request = Request(
        endpoint.rstrip("/") + "/v2/translate",
        data=payload,
        headers={"Authorization": f"DeepL-Auth-Key {key}", "Content-Type": "application/json"},
        method="POST",
    )
    for attempt in range(5):
        try:
            with urlopen(request, timeout=90) as response:
                result = json.load(response)
            translated = [item["text"] for item in result["translations"]]
            if len(translated) != len(texts):
                raise RuntimeError("DeepL returned a different number of texts than requested")
            return translated
        except HTTPError as error:
            body = error.read().decode("utf-8", "replace")[:500]
            if error.code == 429 or error.code >= 500:
                if attempt < 4:
                    time.sleep(2 ** attempt)
                    continue
            raise RuntimeError(f"DeepL API error {error.code}: {body}") from error
        except URLError as error:
            if attempt == 4:
                raise RuntimeError(f"Could not reach DeepL: {error}") from error
            time.sleep(2 ** attempt)
    raise RuntimeError("Translation failed after retries")


def main() -> int:
    key = os.environ.get("DEEPL_API_KEY", "").strip()
    if not key:
        print("Set the DEEPL_API_KEY environment variable first.", file=sys.stderr)
        return 2
    questions = json.loads(SOURCE.read_text(encoding="utf-8"))
    targets: list[tuple[int, str, int | None]] = []
    texts: list[str] = []
    for qi, question in enumerate(questions):
        for field in FIELDS:
            value = question.get(field)
            if isinstance(value, str) and value.strip():
                targets.append((qi, field, None))
                texts.append(value)
        for oi, value in enumerate(question.get("forkerte", [])):
            if isinstance(value, str) and value.strip():
                targets.append((qi, "forkerte", oi))
                texts.append(value)

    translated: list[str] = []
    for start in range(0, len(texts), BATCH_SIZE):
        translated.extend(translate_batch(texts[start:start + BATCH_SIZE], key))
        done = min(start + BATCH_SIZE, len(texts))
        print(f"Translated {done}/{len(texts)} text fields", flush=True)

    english = json.loads(json.dumps(questions))
    for (qi, field, oi), value in zip(targets, translated):
        if oi is None:
            english[qi][field] = value
        else:
            english[qi][field][oi] = value
    temporary = TARGET.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(english, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(TARGET)
    print(f"Wrote {TARGET} ({len(english)} questions). Review translations before publishing.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
