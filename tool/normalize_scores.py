#!/usr/bin/env python3
"""Conservative batch cleanup for the CGDI Audiveris MusicXML catalog.

The script never overwrites the raw OMR files.  It writes corrected MXL files
to ``assets/scores/auto_corrected`` and records every automatic action and
remaining risk in ``assets/scores/review_report.json``.  The generated catalog
continues to require a human musical verification before a score is treated as
authoritative.
"""

from __future__ import annotations

import argparse
import copy
import difflib
import json
import re
import unicodedata
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
SCORES_DIR = ROOT / "assets" / "scores"
CATALOG_PATH = SCORES_DIR / "catalog.json"
CONTENT_PATH = ROOT / "assets" / "library_content_v6.json"
OVERRIDES_PATH = SCORES_DIR / "manual_overrides.json"
OUTPUT_DIR = SCORES_DIR / "auto_corrected"
REPORT_PATH = SCORES_DIR / "review_report.json"

WORD_RE = re.compile(
    r"[¿¡\(\[\{\"'“‘]*[0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+"
    r"(?:[’'][0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+)?[.,;:!?…\)\]\}\"'”’]*"
)
CHORD_RE = re.compile(
    r"^[A-G](?:#|b)?(?:m|maj|min|dim|aug|sus|add)?\d*"
    r"(?:\([^)]+\))?(?:/[A-G](?:#|b)?)?$",
    re.IGNORECASE,
)
TEMPO_WORDS = (
    "Adagio",
    "Andante",
    "Andantino",
    "Allegretto",
    "Allegro",
    "Largo",
    "Larghetto",
    "Lento",
    "Moderato",
    "Presto",
    "Vivace",
    "Majestuoso",
)
SUSPICIOUS_DYNAMICS = {"sf", "sfz", "sffz", "rf", "rfz", "fp"}
SUSPICIOUS_ORNAMENTS = {
    "inverted-mordent",
    "mordent",
    "schleifer",
    "shake",
    "turn",
    "delayed-turn",
    "inverted-turn",
    "delayed-inverted-turn",
}


def normalized(value: str) -> str:
    decomposed = unicodedata.normalize("NFD", value.lower())
    return "".join(
        char for char in decomposed if unicodedata.category(char) != "Mn"
    )


def normalized_word(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", normalized(value))


def tokens(value: str) -> list[str]:
    return WORD_RE.findall(value.replace("//", " ").replace("||", " "))


def local_asset_path(catalog_path: str) -> Path:
    relative = catalog_path.replace("\\", "/")
    if relative.startswith("assets/assets/"):
        relative = relative[len("assets/") :]
    return ROOT / relative


def catalog_asset_path(path: Path) -> str:
    relative = path.relative_to(ROOT).as_posix()
    return f"assets/{relative}"


def xml_payload(archive: zipfile.ZipFile) -> tuple[str, bytes]:
    for name in archive.namelist():
        lower = name.lower()
        if lower.endswith(".xml") and not lower.startswith("meta-inf/"):
            return name, archive.read(name)
    raise ValueError("El MXL no contiene una partitura XML")


def first(parent: ET.Element, name: str) -> ET.Element | None:
    return parent.find(name)


def child_text(parent: ET.Element, name: str, default: str = "") -> str:
    child = first(parent, name)
    return (child.text or "").strip() if child is not None else default


def ensure_child(parent: ET.Element, name: str, before: str | None = None) -> ET.Element:
    child = first(parent, name)
    if child is not None:
        return child
    child = ET.Element(name)
    if before is None:
        parent.append(child)
        return child
    children = list(parent)
    for index, candidate in enumerate(children):
        if candidate.tag == before:
            parent.insert(index, child)
            return child
    parent.append(child)
    return child


def parse_credits(raw: str) -> list[tuple[str, str]]:
    compact = re.sub(r"\s+", " ", raw).strip()
    shared = re.search(r"(?:letra\s+y\s+m[uú]sica|letra\s*,?\s*m[uú]sica)\s*:\s*(.+)", compact, re.I)
    if shared:
        person = shared.group(1).strip(" .")
        return [("composer", person)]

    lyric = re.search(r"letra\s*:\s*(.+?)(?:(?:\s*[·|/]\s*|\s+)m[uú]sica\s*:|$)", compact, re.I)
    music = re.search(r"m[uú]sica\s*:\s*(.+)$", compact, re.I)
    result: list[tuple[str, str]] = []
    if lyric and lyric.group(1).strip():
        result.append(("lyricist", lyric.group(1).strip(" .·|/")))
    if music and music.group(1).strip():
        result.append(("composer", music.group(1).strip(" .·|/")))
    if result:
        return result
    return [("composer", compact)] if compact else []


def title_is_usable(current: str, number: int, official: str) -> bool:
    current_words = set(tokens(normalized(current)))
    official_words = set(tokens(normalized(official)))
    return str(number) in current or len(current_words & official_words) >= max(1, len(official_words) - 1)


@dataclass
class LyricGroup:
    elements: list[ET.Element] = field(default_factory=list)

    @property
    def text(self) -> str:
        return "".join(child_text(element, "text") for element in self.elements)


@dataclass
class CleanupStats:
    metadata_fields: int = 0
    credits_removed: int = 0
    tempo_words_fixed: int = 0
    pedal_artifacts_removed: int = 0
    dynamics_removed: int = 0
    ornaments_removed: int = 0
    chord_lyric_layers_removed: int = 0
    lyric_words_corrected: int = 0
    lyric_regions_rebuilt: int = 0
    lyric_layers_skipped: int = 0
    metric_issues: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    manual_overrides: list[str] = field(default_factory=list)


def group_lyrics(root: ET.Element) -> dict[str, list[LyricGroup]]:
    by_number: dict[str, list[LyricGroup]] = defaultdict(list)
    open_groups: dict[str, LyricGroup] = {}
    for note in root.findall("./part/measure/note"):
        for lyric in note.findall("lyric"):
            number = lyric.get("number", "1")
            syllabic = child_text(lyric, "syllabic", "single").lower()
            if syllabic in {"begin", "single"} or number not in open_groups:
                group = LyricGroup([lyric])
                by_number[number].append(group)
                open_groups[number] = group
            else:
                open_groups[number].elements.append(lyric)
            if syllabic in {"single", "end"}:
                open_groups.pop(number, None)
    return by_number


def is_chord_layer(groups: list[LyricGroup]) -> bool:
    words = [normalized_word(group.text) for group in groups]
    words = [word for word in words if word]
    if len(words) < 3:
        return False
    hits = sum(bool(CHORD_RE.fullmatch(group.text.strip())) for group in groups)
    return hits / len(words) >= 0.65


def remove_element(root: ET.Element, target: ET.Element) -> bool:
    for parent in root.iter():
        for child in list(parent):
            if child is target:
                parent.remove(child)
                return True
    return False


def split_token_for_slots(target: str, source_slots: list[str]) -> list[str]:
    count = len(source_slots)
    if count <= 1:
        return [target]
    prefix_match = re.match(r"^[¿¡\(\[\{\"'“‘]+", target)
    suffix_match = re.search(r"[.,;:!?…\)\]\}\"'”’]+$", target)
    prefix = prefix_match.group(0) if prefix_match else ""
    suffix = suffix_match.group(0) if suffix_match else ""
    start = len(prefix)
    end = len(target) - len(suffix) if suffix else len(target)
    core = target[start:end]
    if len(core) < count:
        return [target] + [""] * (count - 1)

    weights = [max(1, len(normalized_word(slot))) for slot in source_slots]
    total = sum(weights)
    boundaries: list[int] = []
    consumed = 0
    previous = 0
    for index, weight in enumerate(weights[:-1]):
        consumed += weight
        proposed = round(len(core) * consumed / total)
        minimum = previous + 1
        maximum = len(core) - (count - index - 1)
        boundary = max(minimum, min(maximum, proposed))
        boundaries.append(boundary)
        previous = boundary
    pieces: list[str] = []
    cursor = 0
    for boundary in boundaries + [len(core)]:
        pieces.append(core[cursor:boundary])
        cursor = boundary
    pieces[0] = prefix + pieces[0]
    pieces[-1] += suffix
    return pieces


def replace_group(group: LyricGroup, target: str) -> bool:
    old = [child_text(element, "text") for element in group.elements]
    pieces = split_token_for_slots(target, old)
    changed = False
    for index, element in enumerate(group.elements):
        text = ensure_child(element, "text")
        new_text = pieces[index] if index < len(pieces) else ""
        if (text.text or "") != new_text:
            text.text = new_text
            changed = True
        syllabic = ensure_child(element, "syllabic", before="text")
        desired = (
            "single"
            if len(group.elements) == 1
            else "begin"
            if index == 0
            else "end"
            if index == len(group.elements) - 1
            else "middle"
        )
        if (syllabic.text or "") != desired:
            syllabic.text = desired
            changed = True
    return changed


def section_number(label: str) -> int | None:
    match = re.search(r"(?:estrofa|verso)\s*(\d+)", normalized(label))
    return int(match.group(1)) if match else None


def official_words_for_layer(sections: list[dict], number: int) -> list[str]:
    stanzas = {
        value: section["text"]
        for section in sections
        if (value := section_number(str(section.get("label", "")))) is not None
    }
    refrains = [
        str(section.get("text", ""))
        for section in sections
        if any(
            name in normalized(str(section.get("label", "")))
            for name in ("coro", "estribillo", "refran")
        )
    ]
    if number in stanzas:
        text_parts = [stanzas[number]]
        if number == 1:
            text_parts.extend(refrains)
        return tokens("\n".join(text_parts))
    if number == 1 and not stanzas:
        return tokens("\n".join(str(section.get("text", "")) for section in sections))
    return []


@dataclass
class SungSyllable:
    text: str
    word_index: int
    syllabic: str


def _is_vowel(word: str, index: int) -> bool:
    char = word[index].lower()
    if char not in "aeiouáéíóúü":
        return False
    # In que/qui and gue/gui, an unmarked u is orthographic, not a nucleus.
    if char == "u" and index > 0 and index + 1 < len(word):
        previous = word[index - 1].lower()
        following = word[index + 1].lower()
        if previous in "qg" and following in "eiéí":
            return False
    return True


def _strong_vowel(char: str) -> bool:
    return char.lower() in "aeoáéóíú"


def syllabify_word(token: str, word_index: int) -> list[SungSyllable]:
    prefix_match = re.match(r"^[¿¡\(\[\{\"'“‘]+", token)
    suffix_match = re.search(r"[.,;:!?…\)\]\}\"'”’]+$", token)
    prefix = prefix_match.group(0) if prefix_match else ""
    suffix = suffix_match.group(0) if suffix_match else ""
    start = len(prefix)
    end = len(token) - len(suffix) if suffix else len(token)
    core = token[start:end]
    if not core:
        return [SungSyllable(token, word_index, "single")]

    nuclei: list[tuple[int, int]] = []
    index = 0
    while index < len(core):
        if not _is_vowel(core, index):
            index += 1
            continue
        nucleus_start = index
        nucleus_end = index + 1
        while nucleus_end < len(core) and _is_vowel(core, nucleus_end):
            left = core[nucleus_end - 1]
            right = core[nucleus_end]
            if _strong_vowel(left) and _strong_vowel(right):
                break
            nucleus_end += 1
        nuclei.append((nucleus_start, nucleus_end))
        index = nucleus_end
    if len(nuclei) <= 1:
        return [SungSyllable(token, word_index, "single")]

    legal_onsets = {
        "bl", "br", "ch", "cl", "cr", "dr", "fl", "fr", "gl", "gr",
        "gu", "ll", "pl", "pr", "qu", "rr", "tl", "tr",
    }
    boundaries: list[int] = []
    for nucleus_index in range(len(nuclei) - 1):
        left_end = nuclei[nucleus_index][1]
        right_start = nuclei[nucleus_index + 1][0]
        cluster = core[left_end:right_start].lower()
        if len(cluster) <= 1:
            boundary = left_end
        elif len(cluster) == 2:
            boundary = left_end if cluster in legal_onsets else left_end + 1
        elif cluster[-2:] in legal_onsets:
            boundary = right_start - 2
        else:
            boundary = right_start - 1
        boundaries.append(max(left_end, boundary))

    pieces: list[str] = []
    cursor = 0
    for boundary in boundaries + [len(core)]:
        pieces.append(core[cursor:boundary])
        cursor = boundary
    pieces[0] = prefix + pieces[0]
    pieces[-1] += suffix
    return [
        SungSyllable(
            piece,
            word_index,
            "begin" if i == 0 else "end" if i == len(pieces) - 1 else "middle",
        )
        for i, piece in enumerate(pieces)
    ]


def syllabify_text(value: str) -> list[SungSyllable]:
    result: list[SungSyllable] = []
    for word_index, token in enumerate(tokens(value)):
        result.extend(syllabify_word(token, word_index))
    return result


def fit_syllables_to_notes(
    syllables: list[SungSyllable], note_count: int
) -> list[SungSyllable]:
    fitted = list(syllables)
    while len(fitted) > note_count and len(fitted) > 1:
        boundaries = list(range(len(fitted) - 1))
        # Prefer natural vocal elisions between short adjacent words.  Only if
        # those are insufficient do we join syllables within one written word.
        merge_at = min(
            boundaries,
            key=lambda i: (
                fitted[i].word_index == fitted[i + 1].word_index,
                len(normalized_word(fitted[i].text))
                + len(normalized_word(fitted[i + 1].text)),
            ),
        )
        left = fitted[merge_at]
        right = fitted[merge_at + 1]
        separator = " " if left.word_index != right.word_index else ""
        fitted[merge_at : merge_at + 2] = [
            SungSyllable(
                left.text + separator + right.text,
                left.word_index,
                "single" if separator else left.syllabic,
            )
        ]
    return fitted


def eligible_notes(measures: list[ET.Element]) -> list[ET.Element]:
    result: list[ET.Element] = []
    for measure in measures:
        for note in measure.findall("note"):
            if note.find("rest") is not None or note.find("chord") is not None:
                continue
            if note.find("grace") is not None:
                continue
            if any(tie.get("type") == "stop" for tie in note.findall("tie")):
                continue
            result.append(note)
    return result


def clear_lyrics(measures: list[ET.Element], stats: CleanupStats) -> None:
    layers = group_lyrics_in_measures(measures)
    stats.chord_lyric_layers_removed += sum(
        1 for groups in layers.values() if is_chord_layer(groups)
    )
    for measure in measures:
        for note in measure.findall("note"):
            for lyric in list(note.findall("lyric")):
                note.remove(lyric)


def group_lyrics_in_measures(measures: list[ET.Element]) -> dict[str, list[LyricGroup]]:
    by_number: dict[str, list[LyricGroup]] = defaultdict(list)
    open_groups: dict[str, LyricGroup] = {}
    for measure in measures:
        for note in measure.findall("note"):
            for lyric in note.findall("lyric"):
                number = lyric.get("number", "1")
                syllabic = child_text(lyric, "syllabic", "single").lower()
                if syllabic in {"begin", "single"} or number not in open_groups:
                    group = LyricGroup([lyric])
                    by_number[number].append(group)
                    open_groups[number] = group
                else:
                    open_groups[number].elements.append(lyric)
                if syllabic in {"single", "end"}:
                    open_groups.pop(number, None)
    return by_number


def detect_refrain_from_lyrics(
    measures: list[ET.Element], refrain_text: str
) -> int | None:
    targets = [
        normalized_word(word)
        for word in tokens(refrain_text)
        if len(normalized_word(word)) >= 3
    ][:5]
    if len(targets) < 2:
        return None
    measure_by_lyric = {
        id(lyric): measure_index
        for measure_index, measure in enumerate(measures)
        for note in measure.findall("note")
        for lyric in note.findall("lyric")
    }
    best: tuple[float, int] | None = None
    for groups in group_lyrics_in_measures(measures).values():
        words = [normalized_word(group.text) for group in groups]
        for start in range(max(0, len(words) - len(targets) + 1)):
            candidate = words[start : start + len(targets)]
            if len(candidate) < len(targets):
                continue
            similarities = [
                difflib.SequenceMatcher(a=left, b=right, autojunk=False).ratio()
                for left, right in zip(candidate, targets)
            ]
            score = sum(similarities) / len(similarities)
            if score < 0.62 or similarities[0] < 0.55:
                continue
            measure_index = measure_by_lyric.get(id(groups[start].elements[0]))
            if measure_index is None or measure_index < max(1, len(measures) // 5):
                continue
            if best is None or score > best[0]:
                best = (score, measure_index)
    return best[1] if best is not None else None


def write_lyric_layer(
    notes: list[ET.Element],
    text: str,
    number: int,
    name: str,
    stats: CleanupStats,
) -> bool:
    syllables = syllabify_text(text)
    if not syllables or not notes:
        return False
    ratio = len(syllables) / len(notes)
    if ratio < 0.55 or ratio > 1.65:
        stats.lyric_layers_skipped += 1
        stats.warnings.append(
            f"{name}: {len(syllables)} sílabas oficiales para {len(notes)} ataques musicales"
        )
        return False
    fitted = fit_syllables_to_notes(syllables, len(notes))
    if len(fitted) == 1:
        note_indexes = [0]
    else:
        note_indexes = [
            round(index * (len(notes) - 1) / (len(fitted) - 1))
            for index in range(len(fitted))
        ]
    for syllable, note_index in zip(fitted, note_indexes):
        lyric = ET.Element("lyric", {"number": str(number), "name": name})
        syllabic = ET.SubElement(lyric, "syllabic")
        syllabic.text = syllable.syllabic
        lyric_text = ET.SubElement(lyric, "text")
        lyric_text.text = syllable.text
        notes[note_index].append(lyric)
    stats.lyric_words_corrected += len(tokens(text))
    return True


def correct_lyrics(root: ET.Element, sections: list[dict], stats: CleanupStats) -> None:
    parts = root.findall("part")
    if len(parts) != 1:
        stats.lyric_layers_skipped += 1
        stats.warnings.append("Partitura con múltiples partes: letra conservada para revisión manual")
        return
    measures = parts[0].findall("measure")
    if not measures:
        return
    stanzas = {
        value: section
        for section in sections
        if (value := section_number(str(section.get("label", "")))) is not None
    }
    refrains = [
        section
        for section in sections
        if any(
            marker in normalized(str(section.get("label", "")))
            for marker in ("coro", "estribillo", "refran")
        )
    ]
    refrain_index = next(
        (
            index
            for index, measure in enumerate(measures)
            if any(
                marker in normalized(" ".join((word.text or "") for word in measure.findall(".//direction-type/words")))
                for marker in ("coro", "estribillo", "refran")
            )
        ),
        None,
    )

    if refrains and refrain_index is None:
        refrain_text = "\n".join(str(section.get("text", "")) for section in refrains)
        refrain_index = detect_refrain_from_lyrics(measures, refrain_text)

    if refrains and refrain_index is None:
        stats.lyric_layers_skipped += 1
        stats.warnings.append("Hay coro oficial, pero Audiveris no detectó con seguridad su inicio")
        return

    verse_measures = measures if refrain_index is None else measures[:refrain_index]
    refrain_measures = [] if refrain_index is None else measures[refrain_index:]
    verse_notes = eligible_notes(verse_measures)
    planned: list[tuple[list[ET.Element], str, int, str]] = []
    for number, section in sorted(stanzas.items()):
        planned.append(
            (
                verse_notes,
                str(section.get("text", "")),
                number,
                str(section.get("label", f"Estrofa {number}")),
            )
        )
    if not stanzas and not refrains:
        combined = "\n".join(str(section.get("text", "")) for section in sections)
        planned.append((verse_notes, combined, 1, "Letra"))
    if refrain_measures and refrains:
        refrain_text = "\n".join(str(section.get("text", "")) for section in refrains)
        planned.append((eligible_notes(refrain_measures), refrain_text, 1, "Coro"))

    # Validate every region before deleting the OMR underlay.  One unsafe layer
    # leaves the original lyrics in place and is highlighted in the report.
    for notes, text, _, name in planned:
        syllables = syllabify_text(text)
        ratio = len(syllables) / len(notes) if notes else 999
        if ratio < 0.55 or ratio > 1.65:
            stats.lyric_layers_skipped += 1
            stats.warnings.append(
                f"{name}: {len(syllables)} sílabas oficiales para {len(notes)} ataques musicales"
            )
            return

    clear_lyrics(measures, stats)
    for notes, text, number, name in planned:
        if write_lyric_layer(notes, text, number, name, stats):
            stats.lyric_regions_rebuilt += 1


def cleanup_metadata(
    root: ET.Element,
    entry: dict,
    hymn: dict,
    stats: CleanupStats,
) -> None:
    number = int(entry["number"])
    official_title = str(hymn.get("title") or entry.get("title") or "").strip()
    movement = ensure_child(root, "movement-title", before="identification")
    current_title = (movement.text or "").strip()
    if not title_is_usable(current_title, number, official_title):
        movement.text = f"{number} {official_title}"
        stats.metadata_fields += 1

    identification = ensure_child(root, "identification", before="defaults")
    for creator in list(identification.findall("creator")):
        identification.remove(creator)
    creators = parse_credits(str(hymn.get("credits", "")))
    insert_at = next(
        (index for index, node in enumerate(list(identification)) if node.tag == "encoding"),
        len(list(identification)),
    )
    for creator_type, name in creators:
        creator = ET.Element("creator", {"type": creator_type})
        creator.text = name
        identification.insert(insert_at, creator)
        insert_at += 1
        stats.metadata_fields += 1

    source = ensure_child(identification, "source")
    page_label = ", ".join(str(page) for page in entry.get("sourcePages", []))
    official_source = f"Partituras originales CGDI - página {page_label}"
    if (source.text or "") != official_source:
        source.text = official_source
        stats.metadata_fields += 1

    miscellaneous = identification.find("miscellaneous")
    if miscellaneous is None:
        miscellaneous = ET.SubElement(identification, "miscellaneous")
    if miscellaneous is not None:
        for field_node in list(miscellaneous.findall("miscellaneous-field")):
            if field_node.get("name") == "source-file":
                miscellaneous.remove(field_node)
                stats.metadata_fields += 1
        credits_field = next(
            (
                field_node
                for field_node in miscellaneous.findall("miscellaneous-field")
                if field_node.get("name") == "official-credits"
            ),
            None,
        )
        if credits_field is None:
            credits_field = ET.SubElement(
                miscellaneous,
                "miscellaneous-field",
                {"name": "official-credits"},
            )
        credits_field.text = str(hymn.get("credits", "")).strip()

    official_credits = str(hymn.get("credits", "")).strip()
    official_label = (
        official_credits.split(":", 1)[0].strip() + ":"
        if "letra y musica" in normalized(official_credits)
        else ""
    )
    creator_names = [name for _, name in creators]

    for credit in list(root.findall("credit")):
        credit_words = credit.findall("credit-words")
        words = " ".join((node.text or "").strip() for node in credit_words)
        compact = re.sub(r"\s+", "", words)
        if compact and re.fullmatch(r"[0-9!|Il.:-]{1,6}", compact):
            root.remove(credit)
            stats.credits_removed += 1
            continue
        normalized_credit = normalized(words)
        if (
            official_label
            and "musica" in normalized_credit
            and len(words) <= 45
            and credit_words
        ):
            if credit_words[0].text != official_label:
                credit_words[0].text = official_label
                stats.metadata_fields += 1
            continue
        for creator_name in creator_names:
            similarity = difflib.SequenceMatcher(
                a=normalized_word(words),
                b=normalized_word(creator_name),
                autojunk=False,
            ).ratio()
            if similarity >= 0.72 and credit_words:
                if credit_words[0].text != creator_name:
                    credit_words[0].text = creator_name
                    stats.metadata_fields += 1
                break


def apply_manual_overrides(
    root: ET.Element, override: dict, stats: CleanupStats
) -> None:
    tempo = override.get("tempo")
    if not isinstance(tempo, dict):
        return
    metronome = root.find(".//metronome")
    if metronome is None:
        first_measure = root.find("./part/measure")
        if first_measure is None:
            return
        direction = ET.Element("direction", {"placement": "above"})
        direction_type = ET.SubElement(direction, "direction-type")
        metronome = ET.SubElement(direction_type, "metronome")
        first_measure.insert(1, direction)

    beat_unit = ensure_child(metronome, "beat-unit", before="per-minute")
    beat_unit.text = str(tempo.get("beatUnit", "quarter"))
    for dot in list(metronome.findall("beat-unit-dot")):
        metronome.remove(dot)
    if bool(tempo.get("dotted")):
        beat_index = list(metronome).index(beat_unit)
        metronome.insert(beat_index + 1, ET.Element("beat-unit-dot"))
    per_minute = ensure_child(metronome, "per-minute")
    per_minute.text = str(int(tempo["perMinute"]))

    quarter_bpm = float(tempo["perMinute"])
    if tempo.get("beatUnit") == "half":
        quarter_bpm *= 2
    elif tempo.get("beatUnit") == "eighth":
        quarter_bpm /= 2
    if bool(tempo.get("dotted")):
        quarter_bpm *= 1.5
    direction = next(
        (
            candidate
            for candidate in root.findall(".//direction")
            if candidate.find(".//metronome") is metronome
        ),
        None,
    )
    if direction is not None:
        sound = ensure_child(direction, "sound")
        sound.set("tempo", f"{quarter_bpm:g}")
    stats.manual_overrides.append("tempo")


def cleanup_directions_and_ornaments(root: ET.Element, stats: CleanupStats) -> None:
    score_part = root.find("./part-list/score-part")
    part_name = normalized(
        child_text(score_part if score_part is not None else ET.Element("x"), "part-name")
    )
    vocal_score = "voice" in part_name or "voz" in part_name

    for words in root.findall(".//direction-type/words"):
        raw = (words.text or "").strip()
        compact = normalized_word(raw)
        if not compact or "coro" in normalized(raw):
            continue
        candidates = difflib.get_close_matches(
            compact,
            [normalized_word(word) for word in TEMPO_WORDS],
            n=1,
            cutoff=0.72,
        )
        if not candidates:
            continue
        target_index = [normalized_word(word) for word in TEMPO_WORDS].index(candidates[0])
        replacement = TEMPO_WORDS[target_index]
        if raw != replacement:
            words.text = replacement
            stats.tempo_words_fixed += 1

    if vocal_score:
        for pedal in list(root.findall(".//pedal")):
            if remove_element(root, pedal):
                stats.pedal_artifacts_removed += 1
        for sound in root.findall(".//sound"):
            for attribute in ("damper-pedal", "soft-pedal", "sostenuto-pedal"):
                if attribute in sound.attrib:
                    del sound.attrib[attribute]
        for dynamics in list(root.findall(".//dynamics")):
            suspicious = [child for child in list(dynamics) if child.tag in SUSPICIOUS_DYNAMICS]
            for child in suspicious:
                dynamics.remove(child)
                stats.dynamics_removed += 1
            if not list(dynamics):
                remove_element(root, dynamics)
        for ornaments in list(root.findall(".//ornaments")):
            suspicious = [child for child in list(ornaments) if child.tag in SUSPICIOUS_ORNAMENTS]
            for child in suspicious:
                ornaments.remove(child)
                stats.ornaments_removed += 1
            if not list(ornaments):
                remove_element(root, ornaments)

    # Remove empty wrappers left after deleting a false pedal/dynamic.
    for direction_type in list(root.findall(".//direction-type")):
        if not list(direction_type):
            remove_element(root, direction_type)
    for direction in list(root.findall(".//direction")):
        has_content = bool(list(direction))
        if not has_content:
            remove_element(root, direction)


def validate_metrics(root: ET.Element, stats: CleanupStats) -> None:
    for part in root.findall("part"):
        divisions = 1
        beats = 4
        beat_type = 4
        measures = part.findall("measure")
        for measure_index, measure in enumerate(measures):
            attributes = measure.find("attributes")
            if attributes is not None:
                parsed_divisions = child_text(attributes, "divisions")
                if parsed_divisions.isdigit():
                    divisions = int(parsed_divisions)
                time = attributes.find("time")
                if time is not None:
                    parsed_beats = child_text(time, "beats")
                    parsed_beat_type = child_text(time, "beat-type")
                    if parsed_beats.isdigit() and parsed_beat_type.isdigit():
                        beats = int(parsed_beats)
                        beat_type = int(parsed_beat_type)
            expected = divisions * beats * 4 / beat_type
            totals: Counter[str] = Counter()
            for note in measure.findall("note"):
                if note.find("grace") is not None or note.find("chord") is not None:
                    continue
                duration = child_text(note, "duration")
                if not duration.isdigit():
                    continue
                voice = child_text(note, "voice", "1")
                totals[voice] += int(duration)
            for voice, total in totals.items():
                is_edge_measure = measure_index in {0, len(measures) - 1}
                if total > expected + 0.001 or (total < expected - 0.001 and not is_edge_measure):
                    stats.metric_issues.append(
                        f"Compás {measure.get('number', measure_index + 1)}, voz {voice}: "
                        f"duración {total:g}/{expected:g}"
                    )


def serialize_xml(root: ET.Element) -> bytes:
    document = copy.deepcopy(root)
    ET.indent(document, space="  ")
    return ET.tostring(document, encoding="utf-8", xml_declaration=True)


def write_mxl(source: Path, destination: Path, xml_name: str, xml_bytes: bytes) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source, "r") as source_zip, zipfile.ZipFile(
        destination, "w", compression=zipfile.ZIP_DEFLATED
    ) as target_zip:
        for info in source_zip.infolist():
            content = xml_bytes if info.filename == xml_name else source_zip.read(info.filename)
            target_zip.writestr(info, content)


def process_file(
    source: Path,
    destination: Path,
    entry: dict,
    hymn: dict,
    override: dict,
) -> CleanupStats:
    with zipfile.ZipFile(source, "r") as archive:
        xml_name, raw_xml = xml_payload(archive)
    root = ET.fromstring(raw_xml)
    if root.tag not in {"score-partwise", "score-timewise"}:
        raise ValueError(f"Raíz MusicXML no compatible: {root.tag}")
    stats = CleanupStats()
    cleanup_metadata(root, entry, hymn, stats)
    cleanup_directions_and_ornaments(root, stats)
    correct_lyrics(root, list(hymn.get("sections", [])), stats)
    apply_manual_overrides(root, override, stats)
    validate_metrics(root, stats)
    write_mxl(source, destination, xml_name, serialize_xml(root))
    return stats


def aggregate_stats(file_stats: Iterable[CleanupStats]) -> dict:
    items = list(file_stats)
    return {
        "metadataFields": sum(item.metadata_fields for item in items),
        "creditsRemoved": sum(item.credits_removed for item in items),
        "tempoWordsFixed": sum(item.tempo_words_fixed for item in items),
        "pedalArtifactsRemoved": sum(item.pedal_artifacts_removed for item in items),
        "dynamicsRemoved": sum(item.dynamics_removed for item in items),
        "ornamentsRemoved": sum(item.ornaments_removed for item in items),
        "chordLyricLayersRemoved": sum(item.chord_lyric_layers_removed for item in items),
        "lyricWordsCorrected": sum(item.lyric_words_corrected for item in items),
        "lyricRegionsRebuilt": sum(item.lyric_regions_rebuilt for item in items),
        "lyricLayersSkipped": sum(item.lyric_layers_skipped for item in items),
        "metricIssueCount": sum(len(item.metric_issues) for item in items),
        "metricIssues": [issue for item in items for issue in item.metric_issues],
        "warnings": [warning for item in items for warning in item.warnings],
        "manualOverrides": [value for item in items for value in item.manual_overrides],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hymn", help="Procesa sólo un identificador, por ejemplo h1")
    parser.add_argument(
        "--no-catalog-update",
        action="store_true",
        help="Genera MXL/reporte sin cambiar las rutas del catálogo",
    )
    args = parser.parse_args()

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    content = json.loads(CONTENT_PATH.read_text(encoding="utf-8"))
    overrides_data = (
        json.loads(OVERRIDES_PATH.read_text(encoding="utf-8"))
        if OVERRIDES_PATH.exists()
        else {"entries": {}}
    )
    overrides = overrides_data.get("entries", {})
    hymns = {hymn["id"]: hymn for hymn in content["hymns"]}
    report_entries: list[dict] = []
    failures: list[dict] = []

    for entry in catalog["entries"]:
        hymn_id = entry["id"]
        if args.hymn and hymn_id != args.hymn:
            continue
        hymn = hymns.get(hymn_id)
        if hymn is None:
            failures.append({"id": hymn_id, "error": "Sin letra oficial estructurada"})
            continue
        original_files = list(entry.get("originalFiles") or entry.get("files") or [])
        corrected_files: list[str] = []
        stats_for_files: list[CleanupStats] = []
        try:
            for raw_path in original_files:
                source = local_asset_path(raw_path)
                destination = OUTPUT_DIR / source.name
                stats_for_files.append(
                    process_file(
                        source,
                        destination,
                        entry,
                        hymn,
                        dict(overrides.get(hymn_id, {})),
                    )
                )
                corrected_files.append(catalog_asset_path(destination))
        except Exception as error:  # keep the rest of the catalog usable
            failures.append({"id": hymn_id, "error": str(error)})
            continue

        summary = aggregate_stats(stats_for_files)
        status = "auto_corrected_needs_review"
        entry["originalFiles"] = original_files
        entry["files"] = corrected_files
        entry["status"] = status
        entry["review"] = {
            "automationVersion": 1,
            "verificationRequired": True,
            "metricIssueCount": summary["metricIssueCount"],
            "warningCount": len(summary["warnings"]),
        }
        report_entries.append(
            {
                "id": hymn_id,
                "number": entry["number"],
                "title": entry["title"],
                "status": status,
                "sourcePages": entry.get("sourcePages", []),
                "originalFiles": original_files,
                "correctedFiles": corrected_files,
                "changes": summary,
            }
        )

    generated_at = datetime.now(timezone.utc).isoformat()
    report = {
        "version": 1,
        "generatedAt": generated_at,
        "policy": {
            "reference": "assets/pdfs/partituras_app.pdf",
            "automaticCorrectionsAreAuthoritative": False,
            "humanVerificationRequired": True,
            "notesAndRhythmsChangedAutomatically": False,
        },
        "processed": len(report_entries),
        "failed": len(failures),
        "entries": report_entries,
        "failures": failures,
    }
    REPORT_PATH.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    if not args.no_catalog_update and not args.hymn:
        catalog["version"] = 2
        catalog["generatedAt"] = generated_at
        catalog["status"] = "auto_corrected_needs_review"
        catalog["reviewReport"] = "assets/assets/scores/review_report.json"
        CATALOG_PATH.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    print(
        json.dumps(
            {
                "processed": len(report_entries),
                "failed": len(failures),
                "report": str(REPORT_PATH.relative_to(ROOT)),
            },
            ensure_ascii=False,
        )
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
