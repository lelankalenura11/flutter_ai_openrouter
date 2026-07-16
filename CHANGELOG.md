# Changelog

All notable changes to this project are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/), versions follow [Semantic Versioning](https://semver.org/) (`0.x.y` pre-1.0).

## [Unreleased]
- Nothing yet.

## [0.2.0] — Chat organization, error handling & UX improvements
### Added
- Folder management UI: create, rename, delete folders; move chats between folders via the drawer.
- Star tracking fixed: `isStarred` state correctly passed to `MessageBubble`; dedicated "Starred" section in drawer.
- Fork chat: create a new chat from any message with copy-on-write references.
- Smart auto-title: after the first AI response, a lightweight model generates a short chat title (ChatGPT-style).
- User-friendly error messages: raw errors mapped to clear descriptions (network, auth, rate-limit).
- Failed message state: messages that fail to send display a **Retry** button.
- "Jump to latest" floating button appears when scrolled up in the chat view.
- Thinking indicator during message send.
- Error banner with dismiss button.

### Changed
- Rewrote README.md to accurately reflect implemented vs planned features.
- Rewrote CHANGELOG.md to match actual implementation state.

## [0.1.0] — Core text chat, settings, skills
### Added
- Local database setup (Drift/SQLite) with `chats`, `folders`, `messages`, `stars`, `skills`, `message_embeddings`, `settings` tables.
- Secure API key storage via `flutter_secure_storage`.
- Model, max tokens, temperature, and theme settings with UI.
- "Test connection" button against OpenRouter `/api/v1/models`.
- 5 built-in skills: Code Expert, Summarizer, Analyst, Creative Writer, Teacher.
- Custom skill creation with name + system prompt.
- Basic text-only chat loop (send message → OpenRouter chat completion → display response).
- Per-message and per-chat token usage display (input/output tokens from the API `usage` object).
- Collapsible "Show reasoning" section under assistant messages, shown only when the model returns reasoning content.
- Copy message to clipboard (text only).
- Star messages (DB toggle + UI button).

## Planned
The following features are planned for future releases (see README.md for details):
- **v0.3.0** — File & image input (picker, compression, isolate processing)
- **v0.4.0** — Audio recording + transcription (OpenRouter endpoint)
- **v0.5.0** — Scanned PDF + video via vision models
- **v0.6.0** — Export/import (versioned zip manifest + media folder)
- **v0.7.0** — RAG memory (embedding similarity search, context injection)
- **v1.0.0** — Hardened production release (error handling, retry/backoff, cross-platform testing)