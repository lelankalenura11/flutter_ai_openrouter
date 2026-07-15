# Changelog

All notable changes to this project are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/), versions follow [Semantic Versioning](https://semver.org/) (`0.x.y` pre-1.0).

## [Unreleased]
- Nothing yet.

## [0.1.0] — Core text chat, settings, skills
### Added
- Local database setup (`drift`/`Isar`) with `chats`, `folders`, `messages`, `skills`, `settings` tables.
- Secure API key storage via `flutter_secure_storage`.
- Model, max tokens, temperature, and theme settings.
- "Test connection" button against OpenRouter.
- Built-in skills: Code Expert, Summarizer, Analyst, Creative Writer, Teacher.
- Custom skill creation.
- Basic text-only chat loop (send message → OpenRouter chat completion → display response).
- Per-message and per-chat token usage display (input/output tokens from the API `usage` object).
- Collapsible "Show reasoning" section under assistant messages, shown only when the model returns reasoning content.

## [0.2.0] — Chat organization
### Added
- Folders (create, rename, move chats in/out).
- Star messages / Starred section.
- Copy message to clipboard.
- Fork chat (copy-on-write message references).

## [0.3.0] — File & image input
### Added
- File picker for images and text-based PDFs.
- Local text extraction for text PDFs.
- Image compression pipeline.
- Isolate-based processing for all of the above.

## [0.4.0] — Audio recording + transcription
### Added
- In-app audio recording.
- Client-side chunking for long recordings (60s upstream timeout).
- Integration with OpenRouter `/api/v1/audio/transcriptions`.
- Transcribed text populates the text input field.

## [0.5.0] — Scanned PDF + video
### Added
- Scanned PDF detection (empty text extraction) → page-image rendering, batched in groups of 20 pages.
- Video frame sampling (~1 frame per 2–3s, capped at 20–30 frames).
- Pre-send token/cost estimate UI for video and large scanned-PDF batches.
- Hard limits on video duration/size in the file picker.

## [0.6.0] — Export/import
### Added
- Versioned export manifest (`schemaVersion`) + `/media` folder, zipped.
- Import flow, including embedding recomputation (embeddings are not exported).
- API key explicitly excluded from exports.

## [0.7.0] — RAG memory
### Added
- Embedding generation on message save (`message_embeddings` table).
- Brute-force cosine similarity retrieval, scoped per chat (or cross-chat, if enabled).
- Top-K relevant past messages injected into context alongside the recent-message sliding window.

## [1.0.0] — First stable release
### Added
- All of the above, hardened: error handling, retry/backoff on API failures, edge-case testing across Windows/Android/iOS.
