# 记得 Jìde — project notes

Personal Mandarin learning app. Single user (the owner). No backend, no accounts.

## Layout
- `ios/` — SwiftUI + SwiftData, iOS 17+. Built first.
- `android/` — Kotlin + Jetpack Compose. Built later; should match iOS features and share the same data format.
- `shared/data/` — source data shared by both apps (word list, dictionary, stroke data). Keep the export/import JSON format identical on both platforms.

## Constraints (iOS free developer account)
- App must be re-signed every 7 days: owner re-runs from Xcode. Keep the same bundle ID so on-device data survives. Never require deleting the app.
- No iCloud/CloudKit, no push notifications, no App Groups. Local notifications are fine.
- Max 3 sideloaded apps on the device.
- Must have export/import of all user data (progress, notes, recordings) to a file as backup.

## Features
- Flashcards: 汉字→meaning, meaning→汉字, audio→汉字.
- Pinyin with tone colors (1 red, 2 green, 3 blue, 4 purple, neutral gray).
- Audio via `AVSpeechSynthesizer` `zh-CN` (owner has the premium Chinese voice installed; prefer it when available).
- Record own voice and play it back next to the TTS audio to compare tones (high priority, owner wants this).
- Personal notes and mnemonics per card.
- Character breakdown into components.
- Stroke order animation + writing practice (PencilKit).
- Tone quiz (hear audio, pick tone).
- Example sentences.
- Decks: frequency rank, HSK level, custom.
- Streak, daily review count, leech detection.
- Scheduling: FSRS.

## Data sources (open licenses, personal use)
- Word order: Wiktionary Mandarin frequency list 1–1000 (CC BY-SA).
- Pinyin + definitions: CC-CEDICT (CC BY-SA).
- Stroke order: Make Me a Hanzi / Hanzi Writer data.
- Example sentences: Tatoeba (CC BY).
- Do not copy Quizlet or other proprietary deck content.
