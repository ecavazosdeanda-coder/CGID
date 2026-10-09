#!/usr/bin/env python3
"""Generate the citable Bible and Points of Faith corpus."""

import argparse
from collections import defaultdict
from datetime import date
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

SKIP = {"f", "x", "fig", "fm", "ef", "ex"}


def compact(value):
    return re.sub(r"\s+", " ", value).strip()


def read_bible(path):
    root = ET.parse(path).getroot()
    documents = []
    for book in root.findall("book"):
        book_id = book.attrib["id"]
        heading = book.find("h")
        name = compact("".join(heading.itertext())) if heading is not None else book_id
        chapter = None
        current = None
        buffer = []
        verses = defaultdict(list)

        def flush():
            nonlocal current, buffer
            if current is not None and chapter is not None:
                text = compact("".join(buffer))
                if text:
                    verses[chapter].append((current, text))
            current, buffer = None, []

        def walk(element):
            nonlocal current, buffer
            if current is not None and element.text:
                buffer.append(element.text)
            for child in element:
                tag = child.tag.split("}")[-1]
                if tag == "v":
                    flush()
                    current = child.attrib.get("id", "")
                elif tag == "ve":
                    flush()
                elif tag not in SKIP:
                    walk(child)
                if current is not None and child.tail:
                    buffer.append(child.tail)

        for child in book:
            tag = child.tag.split("}")[-1]
            if tag == "c":
                flush()
                chapter = child.attrib.get("id")
            elif chapter is not None:
                walk(child)
        flush()

        for chapter_id, chapter_verses in verses.items():
            for index in range(0, len(chapter_verses), 6):
                group = chapter_verses[index:index + 6]
                start, end = group[0][0], group[-1][0]
                verse_range = start if start == end else f"{start}-{end}"
                documents.append({
                    "id": f"bible-{book_id.lower()}-{chapter_id}-{start}-{end}",
                    "sourceType": "bible",
                    "sourceTitle": "Santa Biblia - Reina-Valera 1909",
                    "reference": f"{name} {chapter_id}:{verse_range}",
                    "bookId": book_id,
                    "book": name,
                    "chapter": chapter_id,
                    "verseStart": start,
                    "verseEnd": end,
                    "text": " ".join(f"{n} {text}" for n, text in group),
                })
    return documents


def read_faith(path):
    library = json.loads(path.read_text(encoding="utf-8"))
    result = []
    for item in library["faith"]:
        number = int(item["number"])
        title = str(item["title"])
        result.append({
            "id": f"faith-{number}",
            "sourceType": "faith",
            "sourceTitle": "Puntos de Fe oficiales",
            "reference": f"Punto de Fe {number}: {title}",
            "pointNumber": number,
            "printedNumber": item.get("printedNumber"),
            "page": item.get("page"),
            "title": title,
            "text": compact(str(item["text"])),
        })
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--usfx", type=Path, required=True)
    parser.add_argument("--library", type=Path,
                        default=Path("assets/library_content_v6.json"))
    parser.add_argument("--output", type=Path,
                        default=Path("assets/data/doctrinal_corpus.json"))
    args = parser.parse_args()
    faith = read_faith(args.library)
    bible = read_bible(args.usfx)
    unresolved = sum(item["text"].count("�") for item in faith)
    payload = {
        "schemaVersion": 1,
        "generatedAt": date.today().isoformat(),
        "sources": [
            {
                "id": "faith",
                "title": "Puntos de Fe oficiales",
                "localDocument": "assets/pdfs/fe.pdf",
                "documentCount": len(faith),
            },
            {
                "id": "bible",
                "title": "Santa Biblia - Reina-Valera 1909",
                "edition": "spaRV1909",
                "license": "Public Domain",
                "sourceUrl": "https://ebible.org/bible/details.php?id=spaRV1909",
                "documentCount": len(bible),
            },
        ],
        "quality": {
            "unresolvedFaithReplacementCharacters": unresolved,
            "note": "Los glifos sin mapa Unicode proceden del PDF doctrinal original.",
        },
        "documents": faith + bible,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"{len(faith)} faith documents; {len(bible)} Bible chunks")


if __name__ == "__main__":
    main()
