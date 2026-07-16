# flutter_ai_chat_app_openrouter

A cross-platform (Windows, Android, iOS) AI chatbot built with Flutter and Dart, using **OpenRouter** as the LLM backend. Local-first: each device keeps its own data, with manual export/import planned for portability between devices (no cloud sync).

Current version: **v0.2.0** — Core text chat, settings, skills, and chat organization.

---

## Current Features (v0.2.0)

### ✅ Text chat
- Text input with send button, auto-scroll, and thinking indicator.
- Messages persisted locally in a Drift (SQLite) database.
- Chat history displayed in a scrollable list.

### ✅ Settings
- OpenRouter API key (stored via `flutter_secure_storage`, never in plaintext prefs).
- Model selection (any OpenRouter model identifier).
- Max tokens slider (256–16,384).
- Temperature slider (0.0–2.0) with descriptive labels.
- Theme toggle (light / dark / system).
- **Test connection** button — hits OpenRouter's `/api/v1/models` endpoint to validate the key without burning tokens.

### ✅ Skills
- 5 built-in skills: Code Expert, Summarizer, Analyst, Creative Writer, Teacher.
- Custom skill creation (name + system prompt).
- Skills are injected as `system` messages in the chat completion call. Select one from the skills sheet (tap 🧠 in the app bar).

### ✅ Token usage display
- Per-message: input/output token count shown under each assistant reply (from OpenRouter's `usage` object).
- Per-chat: running total (input + output) visible server-side; the provider updates `total_input_tokens` / `total_output_tokens` on the `chats` table.

### ✅ Reasoning display
- When a model returns reasoning content (OpenRouter's `reasoning` field via `include_reasoning`), it's shown as a **collapsed-by-default expandable section** under the assistant's message.

### ✅ Chat organization (v0.2.0)
- **Folders**: create, rename, delete folders on the drawer; move chats between folders.
- **Star messages**: star individual messages; view all starred messages in a dedicated Starred section.
- **Copy messages**: copy message text to clipboard.
- **Fork chats**: create a new chat from any message (copy-on-write references).
- **Smart auto-title**: after the first AI response, a lightweight model generates a short title for the chat (ChatGPT-style).

### ✅ Error handling & UX (v0.2.0)
- User-friendly error messages (no raw stack traces or JSON error bodies).
- Failed messages show a **Retry** button.
- **Jump-to-latest** button appears when scrolled up.

---

## Screens

| Screen | Description |
|---|---|
| **Chat** — main conversation view | Message list, input area, skill indicator, error banner |
| **Settings** | API key, model, max tokens, temperature, theme, test connection |
| **Skills sheet** (modal bottom sheet) | List + create skills |
| **Drawer** | Chat list, folders, starred messages, new chat |

---

## Architecture

### Local-first, no cloud sync
Each device's local database is the source of truth. No Firebase or other backend — this avoids conflict resolution, multi-device merge logic, and cloud costs entirely. Data moves between devices only via manual export/import (planned).

### Local database
Drift (SQLite, type-safe) with 7 tables and DAO-style extension methods:

| Table | Purpose |
|---|---|
| `folders` | Chat folder organization |
| `chats` | Chat sessions with token totals |
| `messages` | Individual messages (text + metadata) |
| `stars` | Join table: `message_id`, `starred_at` |
| `skills` | System prompt presets (`is_builtin` flag) |
| `message_embeddings` | Reserved for future RAG memory feature |
| `settings` | Single-row key-value for app preferences |

Media files (images, video, audio, PDFs) are stored on-device in app storage; the DB holds file paths/references, not blobs.

### State management
- **Provider** for reactive UI updates.
- `ChatProvider` — chat list, messages, sending state, error state.
- `SettingsProvider` — API key, model params, theme.
- `SkillProvider` — skill list, create/delete.

---

## Planned Features (Roadmap)

These are documented in the [suggested build order](https://github.com/lelankalenura11/flutter_ai_openrouter) and will be implemented in future releases:

| Phase | Feature | Status |
|---|---|---|
| 3 | File & image input (picker, compression, isolate processing) | 📅 Planned |
| 4 | Audio recording + transcription (OpenRouter endpoint) | 📅 Planned |
| 5 | Scanned PDF + video via vision models | 📅 Planned |
| 6 | Export/import (versioned zip manifest + media folder) | 📅 Planned |
| 7 | RAG memory (embedding similarity search, context injection) | 📅 Planned |

---

## Tech Stack

| Category | Choice |
|---|---|
| Framework | Flutter 3.x, Dart 3.x |
| State management | `provider` |
| Database | `drift` (SQLite, type-safe) |
| Secure storage | `flutter_secure_storage` |
| HTTP client | `http` |
| UUID | `uuid` |
| Date formatting | `intl` |
| Markdown rendering | `flutter_markdown` |
| Math rendering | `flutter_math_fork` |

---

## Getting Started

### Prerequisites
- Flutter SDK 3.x
- An OpenRouter API key (get one at [openrouter.ai](https://openrouter.ai/keys))

### Setup
```bash
# Clone the repository
git clone https://github.com/lelankalenura11/flutter_ai_openrouter.git
cd flutter_ai_openrouter

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### First use
1. Open the app → tap the ⚙️ icon.
2. Paste your OpenRouter API key.
3. Tap **Test Connection** to verify.
4. Go back and start chatting!

---

## Tech notes
- **Secure storage**: `flutter_secure_storage` for the API key — never `SharedPreferences`.
- **Isolates**: Reserved for future `compute()` use with PDF splitting, image/video compression, embedding generation.
- **Drift generator**: After modifying any table file, run `dart run build_runner build` to regenerate `app_database.g.dart`.
- **Code style**: Standard Flutter/Dart conventions with `flutter_lints`.