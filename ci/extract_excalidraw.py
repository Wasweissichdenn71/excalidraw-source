#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


def is_excalidraw_json(obj: object) -> bool:
    """
    Prüft, ob ein JSON-Objekt plausibel eine Excalidraw-Datei ist.
    """
    return (
        isinstance(obj, dict)
        and (
            obj.get("type") == "excalidraw"
            or "elements" in obj
            or "appState" in obj
        )
    )


def try_parse_json(text: str):
    try:
        obj = json.loads(text)
        if is_excalidraw_json(obj):
            return obj
    except json.JSONDecodeError:
        return None
    return None


def extract_from_fenced_code_blocks(text: str):
    """
    Sucht JSON in Markdown-Codeblöcken, z.B.:

    ```json
    { ... }
    ```

    oder:

    ```
    { ... }
    ```
    """
    code_blocks = re.findall(
        r"```(?:json|excalidraw)?\s*(.*?)\s*```",
        text,
        flags=re.DOTALL | re.IGNORECASE,
    )

    for block in code_blocks:
        block = block.strip()
        if not block.startswith("{"):
            continue

        obj = try_parse_json(block)
        if obj is not None:
            return obj

    return None


def extract_from_raw_text_json_object(text: str):
    """
    Fallback: Sucht grob nach einem JSON-Objekt im Text.
    Das hilft bei Markdown-Dateien, die das JSON nicht sauber in einem
    Codeblock enthalten.
    """
    first = text.find("{")
    last = text.rfind("}")

    if first == -1 or last == -1 or last <= first:
        return None

    candidate = text[first:last + 1].strip()
    return try_parse_json(candidate)


def load_excalidraw(input_path: Path) -> dict:
    text = input_path.read_text(encoding="utf-8")

    # Fall 1: Datei ist direkt Excalidraw-JSON
    obj = try_parse_json(text)
    if obj is not None:
        return obj

    # Fall 2: Markdown mit JSON-Codeblock
    obj = extract_from_fenced_code_blocks(text)
    if obj is not None:
        return obj

    # Fall 3: Markdown mit eingebettetem JSON ohne sauberen Codeblock
    obj = extract_from_raw_text_json_object(text)
    if obj is not None:
        return obj

    raise ValueError(
        f"Keine gültige Excalidraw-JSON-Struktur gefunden: {input_path}"
    )


def main() -> None:
    if len(sys.argv) != 3:
        print(
            "Usage: extract_excalidraw.py INPUT OUTPUT",
            file=sys.stderr,
        )
        sys.exit(2)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    if not input_path.exists():
        print(f"Input-Datei existiert nicht: {input_path}", file=sys.stderr)
        sys.exit(1)

    obj = load_excalidraw(input_path)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(obj, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"OK: {input_path} -> {output_path}")


if __name__ == "__main__":
    main()
