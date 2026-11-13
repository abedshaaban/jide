# Backup format (`jide-backup`, version 1)

One UTF-8 JSON file. iOS writes it from Settings › Export backup; Android must read and write the
same structure. Dates are ISO 8601 strings in UTC with milliseconds
(`2026-11-13T08:00:00.123Z`); readers must also accept them without fractional seconds. Binary data is standard base64.

```jsonc
{
  "format": "jide-backup",
  "version": 1,
  "exportedAt": "2026-11-13T08:00:00Z",
  "platform": "ios",                      // or "android"; informational
  "settings": {                            // only known keys, scalar values
    "newPerDay": 15,
    "enabledDirections": "hanzi_meaning,meaning_hanzi,audio_hanzi",
    "autoPlayAudio": true,
    "slowRate": 0.3,                       // iOS AVSpeechUtterance rate; Android maps it
    "voiceIdentifier": "",                 // platform specific, ignore if unknown
    "desiredRetention": 0.9,
    "leechThreshold": 8,
    "suspendLeeches": false,
    "reminderEnabled": true,
    "reminderHour": 19,
    "reminderMinute": 0,
    "toneQuizCorrect": 0,
    "toneQuizTotal": 0
  },
  "words": [{                              // bundled words with notes, and all custom words
    "id": "zh:我",                         // bundled: "zh:" + simplified; custom: "custom:" + UUID
    "isCustom": false,
    "note": "",
    "mnemonic": "",
    "createdAt": "...",
    // custom words only:
    "rank": 100000, "simplified": "...", "traditional": "...", "pinyinNumbered": "wo3",
    "gloss": "...", "definitions": ["..."], "hsk": null, "hsk3": null
  }],
  "cards": [{                              // cards that are not untouched-new
    "id": "zh:我|hanzi_meaning",           // wordId + "|" + direction
    "wordId": "zh:我",
    "direction": "hanzi_meaning",          // hanzi_meaning | meaning_hanzi | audio_hanzi
    "state": 2,                            // 0 new, 1 learning, 2 review, 3 relearning
    "step": 0,                             // index into learning/relearning steps
    "stability": 12.3,                     // FSRS, days
    "difficulty": 5.2,                     // FSRS, 1-10
    "due": "...",
    "reps": 4,
    "lapses": 0,
    "lastReview": "...",                   // or null
    "suspended": false,
    "leech": false
  }],
  "reviewLogs": [{
    "id": "UUID",
    "date": "...",
    "cardId": "zh:我|hanzi_meaning",
    "rating": 3,                           // 1 again, 2 hard, 3 good, 4 easy
    "stateBefore": 2,
    "elapsedDays": 3.1,
    "scheduledDays": 8.0,
    "durationMs": 4200
  }],
  "decks": [{ "id": "UUID", "name": "Food", "wordIds": ["zh:吃"], "createdAt": "..." }],
  "recordings": [{ "wordId": "zh:我", "mimeType": "audio/mp4", "data": "<base64 AAC .m4a>" }]
}
```

## Import rules

- Merge, file wins: entries with an ID that exists locally are overwritten; others are added.
- Review logs are added only if their `id` is not already present.
- Words that are neither custom nor in the bundled list are skipped.
- A recording replaces the local recording for that word.
- Reject files whose `format` differs, whose `version` is not supported (only 1 exists), or that do not
  decode. Validate fully before changing anything; a failed import must leave local data untouched.
- Recordings for words that do not exist after the import are ignored.

## Scheduler

FSRS-5 with default weights, learning steps 1 min / 10 min, relearning step 10 min.
See `ios/Jide/Logic/FSRS.swift`; Android should port it as-is so intervals match.
