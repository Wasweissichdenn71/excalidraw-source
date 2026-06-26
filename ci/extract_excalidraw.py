#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="


def is_excalidraw_json(obj: object) -> bool:
    return (
        isinstance(obj, dict)
        and (
            obj.get("type") == "excalidraw"
            or "elements" in obj
            or "appState" in obj
        )
    )


def normalize_excalidraw_json(obj: dict) -> dict:
    if "type" not in obj:
        obj["type"] = "excalidraw"
    if "version" not in obj:
        obj["version"] = 2
    if "source" not in obj:
        obj["source"] = "https://excalidraw.com"
    if "elements" not in obj:
        obj["elements"] = []
    if "appState" not in obj:
        obj["appState"] = {}
    if "files" not in obj:
        obj["files"] = {}
    return obj


def try_parse_json(text: str):
    try:
        obj = json.loads(text)
        if is_excalidraw_json(obj):
            return normalize_excalidraw_json(obj)
    except json.JSONDecodeError:
        return None
    return None


def get_base64_value(char: str) -> int:
    try:
        return BASE64_ALPHABET.index(char)
    except ValueError:
        return 0


def lzstring_decompress_from_base64(data: str) -> str:
    data = re.sub(r"\s+", "", data)

    if not data:
        return ""

    def get_next_value(index: int) -> int:
        if index >= len(data):
            return 0
        return get_base64_value(data[index])

    return lzstring_decompress(len(data), 32, get_next_value)


def lzstring_decompress(length: int, reset_value: int, get_next_value) -> str:
    dictionary = {0: 0, 1: 1, 2: 2}
    enlarge_in = 4
    dict_size = 4
    num_bits = 3
    result = []

    data_val = get_next_value(0)
    data_position = reset_value
    data_index = 1

    def read_bits(n: int) -> int:
        nonlocal data_val, data_position, data_index

        bits = 0
        maxpower = 1 << n
        power = 1

        while power != maxpower:
            resb = data_val & data_position
            data_position >>= 1

            if data_position == 0:
                data_position = reset_value
                data_val = get_next_value(data_index)
                data_index += 1

            if resb > 0:
                bits |= power

            power <<= 1

        return bits

    next_token = read_bits(2)

    if next_token == 0:
        c = chr(read_bits(8))
    elif next_token == 1:
        c = chr(read_bits(16))
    elif next_token == 2:
        return ""
    else:
        return ""

    dictionary[3] = c
    w = c
    result.append(c)

    while True:
        if data_index > length:
            return ""

        c_num = read_bits(num_bits)

        if c_num == 0:
            dictionary[dict_size] = chr(read_bits(8))
            c_num = dict_size
            dict_size += 1
            enlarge_in -= 1
        elif c_num == 1:
            dictionary[dict_size] = chr(read_bits(16))
            c_num = dict_size
            dict_size += 1
            enlarge_in -= 1
        elif c_num == 2:
            return "".join(result)

        if enlarge_in == 0:
            enlarge_in = 1 << num_bits
            num_bits += 1

        if c_num in dictionary:
            entry = dictionary[c_num]
        elif c_num == dict_size:
            entry = w + w[0]
        else:
            return ""

        result.append(entry)

        dictionary[dict_size] = w + entry[0]
        dict_size += 1
        enlarge_in -= 1

        w = entry

        if enlarge_in == 0:
            enlarge_in = 1 << num_bits
            num_bits += 1


def extract_from_fenced_code_blocks(text: str):
    code_blocks = re.findall(
        r"```([^\n\r]*)\r?\n(.*?)```",
        text,
        flags=re.DOTALL,
    )

    for language, block in code_blocks:
        language = language.strip().lower()
        block = block.strip()

        if "compressed-json" in language:
            decompressed = lzstring_decompress_from_base64(block)
            obj = try_parse_json(decompressed)
            if obj is not None:
                return obj

        if block.startswith("{"):
            obj = try_parse_json(block)
            if obj is not None:
                return obj

    return None


def extract_from_raw_text_json_object(text: str):
    first = text.find("{")
    last = text.rfind("}")

    if first == -1 or last == -1 or last <= first:
        return None

    candidate = text[first:last + 1].strip()
    return try_parse_json(candidate)


def load_excalidraw(input_path: Path) -> dict:
    text = input_path.read_text(encoding="utf-8")

    obj = try_parse_json(text)
    if obj is not None:
        return obj

    obj = extract_from_fenced_code_blocks(text)
    if obj is not None:
        return obj

    obj = extract_from_raw_text_json_object(text)
    if obj is not None:
        return obj

    raise ValueError(f"Keine gültige Excalidraw-JSON-Struktur gefunden: {input_path}")


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: extract_excalidraw.py INPUT OUTPUT", file=sys.stderr)
        sys.exit(2)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    if not input_path.exists():
        print(f"Input-Datei existiert nicht: {input_path}", file=sys.stderr)
        sys.exit(1)

    try:
        obj = load_excalidraw(input_path)
    except Exception as exc:
        print(f"SKIP/ERROR: {exc}", file=sys.stderr)
        sys.exit(1)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(obj, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"OK: {input_path} -> {output_path}")


if __name__ == "__main__":
    main()
