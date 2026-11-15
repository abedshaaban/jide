#!/usr/bin/env python3
"""Report data-quality problems in words.json / characters.json. Exit 1 on hard errors.

    python3 -I shared/data/scripts/check_data.py
"""
import collections
import json
import os
import re
import sys

DATA = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = re.compile(r"^(variant of|old variant|used in|see )")
SYL = re.compile(r"[A-Za-z:]+[1-5]")


def main():
    data = json.load(open(os.path.join(DATA, "words.json"), encoding="utf-8"))
    words, components = data["words"], data["components"]
    chars = json.load(open(os.path.join(DATA, "characters.json"), encoding="utf-8"))["characters"]
    hard = {}
    soft = {}

    hard["empty meaning"] = [w["simplified"] for w in words if not any(d.strip() for d in w["definitions"])]
    hard["stub-only meaning"] = [w["simplified"] for w in words if all(STUB.match(d) for d in w["definitions"])]
    hard["pinyin syllable without tone"] = [
        w["simplified"] for w in words
        if not w["pinyinNumbered"] or not all(SYL.fullmatch(s) for s in w["pinyinNumbered"].split())]
    hard["pinyin/hanzi count mismatch"] = [
        w["simplified"] for w in words
        if len(w["pinyinNumbered"].split()) != len(w["simplified"]) and not w["pinyinNumbered"].endswith("r5")]
    hard["duplicate word"] = [k for k, v in collections.Counter(w["simplified"] for w in words).items() if v > 1]
    hard["duplicate rank"] = [k for k, v in collections.Counter(w["rank"] for w in words).items() if v > 1]
    word_chars = sorted({c for w in words for c in w["simplified"]})
    hard["character without stroke data"] = [c for c in word_chars if "strokes" not in chars.get(c, {})]
    hard["strokes/medians mismatch"] = [
        c for c, v in chars.items() if "strokes" in v and len(v["strokes"]) != len(v["medians"])]

    word_set = {w["simplified"] for w in words}
    hard["component isWord flag wrong"] = [c["char"] for c in components if c["isWord"] != (c["char"] in word_set)]
    hard["component without meaning or strokes"] = [
        c["char"] for c in components if not c["definition"].strip() or "strokes" not in chars.get(c["char"], {})]
    hard["duplicate component"] = [k for k, v in collections.Counter(c["char"] for c in components).items() if v > 1]

    soft["component without pinyin"] = [c["char"] for c in components if not c["pinyinNumbered"]]
    soft["word without example sentence"] = [w["simplified"] for w in words if not w["sentences"]]
    soft["word without HSK level"] = [w["simplified"] for w in words if w["hsk"] is None]
    soft["neutral-tone single character"] = [w["simplified"] for w in words if w["pinyinNumbered"].endswith("5")
                                             and len(w["simplified"]) == 1]

    print(f"{len(words)} words, {len(components)} components, {len(chars)} characters ({len(word_chars)} used by words)")
    for title, group in (("errors", hard), ("info", soft)):
        print(f"-- {title}")
        for k, v in group.items():
            print(f"{k}: {len(v)}" + (f"  {''.join(v[:40]) if all(len(x) == 1 for x in v) else ' '.join(map(str, v[:15]))}" if v else ""))
    return 1 if any(hard.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
