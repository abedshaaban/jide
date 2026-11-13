#!/usr/bin/env python3
"""Regenerate shared/data/words.json and shared/data/characters.json.

Usage:
    python3 -I shared/data/scripts/build_data.py [--cache DIR] [--count 1000]

Downloads (cached in --cache, default: a temp dir) and joins:
  * Wiktionary "Appendix:Mandarin Frequency lists" (CC BY-SA)  -> word order
  * CC-CEDICT (CC BY-SA)                                        -> pinyin + definitions
  * complete-hsk-vocabulary (MIT)                               -> HSK levels
  * Tatoeba cmn/eng sentences + links (CC BY)                   -> example sentences
  * Make Me a Hanzi dictionary.txt (LGPL) + graphics.txt (Arphic PL)
                                                                -> decomposition + strokes

Only the Python standard library is used. Output is deterministic for a given
set of inputs so diffs stay readable.
"""
import argparse
import bz2
import gzip
import json
import os
import re
import sys
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.dirname(HERE)

SOURCES = {
    "wikt1.json": "https://en.wiktionary.org/w/api.php?action=parse&page=Appendix:Mandarin_Frequency_lists/1-1000&prop=wikitext&format=json",
    "wikt2.json": "https://en.wiktionary.org/w/api.php?action=parse&page=Appendix:Mandarin_Frequency_lists/1001-2000&prop=wikitext&format=json",
    "cedict.txt.gz": "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz",
    "hsk.json": "https://raw.githubusercontent.com/drkameleon/complete-hsk-vocabulary/main/complete.json",
    "cmn_sentences.tsv.bz2": "https://downloads.tatoeba.org/exports/per_language/cmn/cmn_sentences.tsv.bz2",
    "eng_sentences.tsv.bz2": "https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2",
    "cmn-eng_links.tsv.bz2": "https://downloads.tatoeba.org/exports/per_language/cmn/cmn-eng_links.tsv.bz2",
    "mmah_dictionary.txt": "https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt",
    "mmah_graphics.txt": "https://raw.githubusercontent.com/skishore/makemeahanzi/master/graphics.txt",
}

# Bump when the output changes so installed apps refresh dictionary fields.
DATA_VERSION = 2
MAX_SENTENCES = 3
MAX_SENTENCE_LEN = 18

# ---------------------------------------------------------------- pinyin utils

TONE_MARKS = {
    "a": "āáǎà", "e": "ēéěè", "i": "īíǐì", "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ",
}
MARK_TO_PLAIN = {}
for base, marks in TONE_MARKS.items():
    for i, m in enumerate(marks):
        MARK_TO_PLAIN[m] = (base, i + 1)
        MARK_TO_PLAIN[m.upper()] = (base.upper(), i + 1)


def numbered_to_marks(syl):
    """'hao3' -> 'hǎo', 'lu:4' -> 'lǜ', 'ma5' -> 'ma'. Non-syllables pass through."""
    m = re.fullmatch(r"([A-Za-zü:]+)([1-5])", syl)
    if not m:
        return syl.replace("u:", "ü").replace("U:", "Ü")
    body, tone = m.group(1).replace("u:", "ü").replace("U:", "Ü"), int(m.group(2))
    if tone == 5:
        return body
    low = body.lower()
    if "a" in low:
        idx = low.index("a")
    elif "e" in low:
        idx = low.index("e")
    elif "ou" in low:
        idx = low.index("o")
    else:
        idx = max(low.rfind(v) for v in "iouü")
        if idx < 0:
            return body
    ch = body[idx]
    mark = TONE_MARKS[ch.lower()][tone - 1]
    if ch.isupper():
        mark = mark.upper()
    return body[:idx] + mark + body[idx + 1:]


def strip_tones(s):
    out = []
    for ch in s:
        out.append(MARK_TO_PLAIN[ch][0] if ch in MARK_TO_PLAIN else ch)
    return "".join(out)


def norm_marks(s):
    """Lowercase, no spaces/apostrophes, ü kept. Used to compare readings."""
    return re.sub(r"[\s'·\-]", "", s.lower())


# ---------------------------------------------------------------- loaders


def fetch(cache, name):
    path = os.path.join(cache, name)
    if not os.path.exists(path):
        print(f"downloading {name} ...", file=sys.stderr)
        req = urllib.request.Request(SOURCES[name], headers={"User-Agent": "jide-data-builder/1.0"})
        with urllib.request.urlopen(req) as r, open(path, "wb") as f:
            f.write(r.read())
    return path


def load_frequency(cache, count, cedict):
    by_trad = {}
    for simp, es in cedict.items():
        for e in es:
            by_trad.setdefault(e["traditional"], simp)
    words, seen = [], set()
    for name in ("wikt1.json", "wikt2.json"):
        with open(fetch(cache, name), encoding="utf-8") as f:
            text = json.load(f)["parse"]["wikitext"]["*"]
        text = re.sub(r"\{\{audio[^}]*\}\}", "", text)
        for line in text.split("\n"):
            if not line.startswith("|"):
                continue
            parts = line[1:].split("|", 3)
            if len(parts) < 4:
                continue
            trad, simp, pinyin, gloss = (p.strip() for p in parts)
            if simp not in cedict and simp in by_trad:
                simp = by_trad[simp]  # list gives a traditional form, e.g. 旅遊 -> 旅游
            if not simp or simp in seen:
                continue
            seen.add(simp)
            gloss = re.sub(r"\{\{[^}]*\}\}", "", gloss).replace("_", " ").strip()
            words.append({"traditional": trad, "simplified": simp, "wiktPinyin": pinyin, "gloss": gloss})
            if len(words) == count:
                return words
    return words


def load_cedict(cache):
    entries = {}
    pat = re.compile(r"^(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$")
    with gzip.open(fetch(cache, "cedict.txt.gz"), "rt", encoding="utf-8") as f:
        for line in f:
            if line.startswith("#"):
                continue
            m = pat.match(line)
            if not m:
                continue
            trad, simp, py, defs = m.groups()
            entries.setdefault(simp, []).append({
                "traditional": trad,
                "pinyinNumbered": py,
                "definitions": [d for d in defs.split("/") if d],
            })
    return entries


def load_hsk(cache):
    with open(fetch(cache, "hsk.json"), encoding="utf-8") as f:
        data = json.load(f)
    out = {}
    for item in data:
        old = [int(l.split("-")[1]) for l in item.get("level", []) if l.startswith("old-")]
        new = [int(l.split("-")[1]) for l in item.get("level", []) if l.startswith("new-")]
        out[item["simplified"]] = (min(old) if old else None, min(new) if new else None)
    return out


def load_mmah(cache):
    chars = {}
    with open(fetch(cache, "mmah_dictionary.txt"), encoding="utf-8") as f:
        for line in f:
            d = json.loads(line)
            chars[d["character"]] = d
    graphics = {}
    with open(fetch(cache, "mmah_graphics.txt"), encoding="utf-8") as f:
        for line in f:
            d = json.loads(line)
            graphics[d["character"]] = d
    return chars, graphics


# ---------------------------------------------------------------- joining


STUB_DEF = re.compile(r"^(variant of|old variant|used in|see |Taiwan pr\.|also pr\.|CL:|surname )")
BRACKET_PINYIN = re.compile(r"\[([A-Za-z:]+[1-5](?: [A-Za-z:]+[1-5])*)\]")


def choose_entry(simp, wikt_pinyin, cedict, trad=None, gloss=""):
    cands = cedict.get(simp, [])
    if not cands:
        return None
    # Same traditional form as the list first: 着 -> 著 has real senses, 着 -> 着 only "variant of".
    cands = [e for e in cands if e["traditional"] == trad] or cands
    target = norm_marks(wikt_pinyin)

    def marks(e):
        return norm_marks("".join(numbered_to_marks(s) for s in e["pinyinNumbered"].split()))

    lower = [e for e in cands if not e["pinyinNumbered"][:1].isupper()] or cands
    for e in lower:
        if marks(e) == target:
            return e
    target_tones = [MARK_TO_PLAIN[ch][1] for ch in target if ch in MARK_TO_PLAIN]

    def score(e):
        # Shared tones with the Wiktionary reading, then real senses over "variant of"/"used in"
        # stubs, then number of senses. The list's own pinyin is sometimes off (e.g. 吗 "mā").
        tones = [int(s[-1]) for s in e["pinyinNumbered"].split() if s[-1].isdigit()]
        pool = list(target_tones)
        shared = 0
        for t in tones:
            if t in pool:
                pool.remove(t)
                shared += 1
        real = sum(1 for d in e["definitions"] if not STUB_DEF.match(d))
        # Function words: if the list calls it a particle, prefer the particle reading (吗 ma5, not ma2).
        particle = ("particle" in gloss) == any("particle" in d for d in e["definitions"])
        return (shared, real > 0, particle, real)

    same = [e for e in lower if strip_tones(marks(e)) == strip_tones(target)]
    return max(same or lower, key=score)


def bracket_marks(d):
    """'(courteous 您[nin2])' -> '(courteous 您[nín])'."""
    return BRACKET_PINYIN.sub(lambda m: "[" + "".join(numbered_to_marks(x) for x in m.group(1).split()) + "]", d)


def clean_definitions(defs):
    out = [bracket_marks(d) for d in defs if not d.startswith(("CL:", "variant of", "old variant", "Taiwan pr.", "also pr."))]
    return out or [bracket_marks(d) for d in defs]


def resolve_variants(entry, cedict):
    """'variant of 臺灣|台湾[Tai2 wan1]' only: borrow the senses of the entry it points to."""
    defs = entry["definitions"]
    if not defs or not all(STUB_DEF.match(d) for d in defs):
        return None
    for d in defs:
        m = re.match(r"^(?:old )?variant of ([^\[|]+)(?:\|([^\[]+))?\[([^\]]+)\]", d)
        if not m:
            continue
        trad, simp, py = m.group(1), m.group(2) or m.group(1), m.group(3)
        for e in cedict.get(simp, []):
            if e["traditional"] == trad and e["pinyinNumbered"].lower() == py.lower():
                real = [x for x in e["definitions"] if not STUB_DEF.match(x)]
                if real:
                    return real
    return None


def clean_gloss(gloss, limit=6):
    """Wiktionary glosses are sometimes long synonym dumps; keep the first few items."""
    parts = [p.strip() for p in gloss.split(",") if p.strip()]
    return ", ".join(parts[:limit])


def build_segmenter(cedict, preferred=None, numbered=False):
    reading = {}
    for simp, es in cedict.items():
        lower = [e for e in es if not e["pinyinNumbered"][:1].isupper()] or es
        reading[simp] = max(lower, key=lambda e: len(e["definitions"]))["pinyinNumbered"].lower()
    reading.update(preferred or {})
    maxlen = 6

    def pinyin_for(sentence):
        out, i = [], 0
        while i < len(sentence):
            for n in range(min(maxlen, len(sentence) - i), 0, -1):
                chunk = sentence[i:i + n]
                if chunk in reading:
                    if numbered:
                        out.extend(reading[chunk].split())
                    else:
                        out.extend(numbered_to_marks(s) for s in reading[chunk].split())
                    i += n
                    break
            else:
                ch = sentence[i]
                if out and not re.match(r"[\w]", ch):
                    out[-1] += ch  # attach punctuation
                else:
                    out.append(ch)
                i += 1
        return " ".join(out)

    return pinyin_for


def load_sentences(cache, words, cedict, pinyin_for):
    trad_only = set()
    simp_chars = set()
    for simp, es in cedict.items():
        simp_chars.update(simp)
        for e in es:
            trad_only.update(e["traditional"])
    trad_only -= simp_chars

    cmn = {}
    with bz2.open(fetch(cache, "cmn_sentences.tsv.bz2"), "rt", encoding="utf-8") as f:
        for line in f:
            sid, _, text = line.rstrip("\n").split("\t", 2)
            text = text.strip()
            if len(text) > MAX_SENTENCE_LEN or any(c in trad_only for c in text):
                continue
            cmn[sid] = text
    links = {}
    with bz2.open(fetch(cache, "cmn-eng_links.tsv.bz2"), "rt", encoding="utf-8") as f:
        for line in f:
            a, b = line.split()[:2]
            if a in cmn:
                links.setdefault(a, []).append(b)
    needed = {b for bs in links.values() for b in bs}
    eng = {}
    with bz2.open(fetch(cache, "eng_sentences.tsv.bz2"), "rt", encoding="utf-8") as f:
        for line in f:
            sid, _, text = line.rstrip("\n").split("\t", 2)
            if sid in needed:
                eng[sid] = text.strip()

    pairs = []
    for sid, text in cmn.items():
        ens = [eng[b] for b in links.get(sid, []) if b in eng]
        if ens:
            pairs.append((len(text), int(sid), text, min(ens, key=len)))
    pairs.sort()

    result = {}
    for w in words:
        simp = w["simplified"]
        picked, seen_text = [], set()
        for _, sid, text, en in pairs:
            if simp in text and text not in seen_text and len(text) >= len(simp) + 3:
                picked.append({"id": sid, "zh": text, "pinyin": pinyin_for(text), "en": en})
                seen_text.add(text)
                if len(picked) == MAX_SENTENCES:
                    break
        result[simp] = picked
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "jide-data-cache"))
    ap.add_argument("--count", type=int, default=1000)
    args = ap.parse_args()
    os.makedirs(args.cache, exist_ok=True)

    cedict = load_cedict(args.cache)
    freq = load_frequency(args.cache, args.count, cedict)
    hsk = load_hsk(args.cache)
    chosen = {w["simplified"]: choose_entry(w["simplified"], w["wiktPinyin"], cedict, w["traditional"], w["gloss"])
              for w in freq}
    preferred = {k: e["pinyinNumbered"].lower() for k, e in chosen.items() if e}
    pinyin_for = build_segmenter(cedict, preferred)
    numbered_for = build_segmenter(cedict, preferred, numbered=True)
    sentences = load_sentences(args.cache, freq, cedict, pinyin_for)

    words = []
    missing = []
    for rank, w in enumerate(freq, start=1):
        e = chosen[w["simplified"]]
        if e:
            numbered = e["pinyinNumbered"].lower() if not w["wiktPinyin"][:1].isupper() else e["pinyinNumbered"]
            defs = clean_definitions(resolve_variants(e, cedict) or e["definitions"])
        else:
            # Not a CEDICT headword (e.g. 很多): compose reading from its parts.
            missing.append(w["simplified"])
            numbered = numbered_for(w["simplified"])
            gloss = re.sub(r"^(det|conj)\.:\s*", "", w["gloss"]).strip()
            if gloss:
                defs = [gloss]
            else:
                parts = [chosen.get(c) or (cedict.get(c) or [None])[0] for c in w["simplified"]]
                defs = [" + ".join(f"{c} ({p['definitions'][0]})" for c, p in zip(w["simplified"], parts) if p)]
                w["gloss"] = defs[0]
        marks = " ".join(numbered_to_marks(s) for s in numbered.split()) if numbered else w["wiktPinyin"]
        old, new = hsk.get(w["simplified"], (None, None))
        words.append({
            "rank": rank,
            "simplified": w["simplified"],
            "traditional": w["traditional"],
            "pinyin": marks,
            "pinyinNumbered": numbered,
            "gloss": clean_gloss(w["gloss"]),
            "definitions": defs,
            "hsk": old,
            "hsk3": new,
            "sentences": sentences.get(w["simplified"], []),
        })

    mmah, graphics = load_mmah(args.cache)
    wanted, queue = set(), [c for w in words for c in w["simplified"]]
    stroke_chars = set(queue)
    while queue:
        c = queue.pop()
        if c in wanted or c not in mmah:
            continue
        wanted.add(c)
        for comp in mmah[c].get("decomposition", ""):
            if comp in mmah and comp not in wanted:
                queue.append(comp)
    characters = {}
    for c in sorted(wanted):
        d = mmah[c]
        entry = {
            "definition": d.get("definition", ""),
            "pinyin": d.get("pinyin", []),
            "decomposition": d.get("decomposition", ""),
            "radical": d.get("radical", ""),
        }
        if "etymology" in d:
            entry["etymology"] = d["etymology"]
        if c in stroke_chars and c in graphics:
            entry["strokes"] = graphics[c]["strokes"]
            entry["medians"] = graphics[c]["medians"]
        characters[c] = entry

    with open(os.path.join(OUT_DIR, "words.json"), "w", encoding="utf-8") as f:
        json.dump({"version": DATA_VERSION, "words": words}, f, ensure_ascii=False, indent=0, separators=(",", ":"))
        f.write("\n")
    with open(os.path.join(OUT_DIR, "characters.json"), "w", encoding="utf-8") as f:
        json.dump({"version": DATA_VERSION, "characters": characters}, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")

    with_sent = sum(1 for w in words if w["sentences"])
    with_hsk = sum(1 for w in words if w["hsk"])
    print(f"words: {len(words)}  (no CEDICT match: {missing})", file=sys.stderr)
    print(f"words with sentences: {with_sent}  with HSK level: {with_hsk}", file=sys.stderr)
    print(f"characters: {len(characters)}  with strokes: {sum(1 for v in characters.values() if 'strokes' in v)}", file=sys.stderr)


if __name__ == "__main__":
    main()
