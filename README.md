# flutter_ai_chat_app_openrouter

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# AI Chatbot (Flutter + OpenRouter)

A cross-platform (Windows, Android, iOS) multimodal AI chatbot built with Flutter and Dart, using OpenRouter as the LLM backend. Local-first: each device keeps its own data, with manual export/import for portability between devices (no cloud sync).

## Features

### 1. Multimodal input
- **Text** — standard text field input.
- **Images / photos** — via file picker, sent directly to vision-capable models.
- **Video** — via file picker. Frames are sampled client-side (~1 frame per 2–3 seconds, capped at 20–30 frames) and sent as an image sequence to a vision-capable model. Hard cap on video duration/size at the picker level. Estimated token/cost shown before sending.
- **PDF** — via file picker.
  - Text-based PDFs: text extracted locally (no API call needed for extraction).
  - Scanned PDFs: rendered to page images and sent to a vision-capable model, batched in groups of 20 pages (batches >20 pages are split and processed sequentially).
- **Audio** — via file picker, or recorded in-app.
  - Recordings are chunked client-side to respect the ~60s upstream provider timeout.
  - Sent to OpenRouter's dedicated `/api/v1/audio/transcriptions` endpoint.
  - Transcribed text is placed into the text input field for review before sending.

All heavy processing (PDF splitting, image/video compression, frame extraction, embedding generation) runs in Dart isolates (`compute()`) to keep the UI thread responsive.

### 2. Chats
- Chats can be organized into folders or left unfiled.
- Messages can be **starred** and viewed in a dedicated Starred section.
- Messages can be **copied** (to clipboard) or **forked** into a new chat.
  - Forking copies message *references*, not full deep copies of attachments — copy-on-write only when a forked message is edited.
- **Token usage** is shown on the chat screen:
  - Per-message: input/output token count on each assistant reply (small label under the bubble).
  - Per-chat: a running total (input + output) visible in the chat header or app bar, so the user has an ongoing sense of cost as the conversation grows.
  - Values come directly from the `usage` object OpenRouter returns with each chat completion response (`prompt_tokens`, `completion_tokens`) — no local estimation needed for the primary count. Client-side estimation is only used *before* sending, for the video/scanned-PDF cost-preview mentioned below.
- **Reasoning display**: when a model returns reasoning content (OpenRouter's `reasoning` field, via `include_reasoning`/`reasoning` request params on reasoning-capable models), it's shown separately from the main answer as a **collapsed-by-default expandable section** under the assistant's message (e.g. "Show reasoning ▾"). Kept collapsed by default so it doesn't dominate the chat view, but available on tap for users who want the model's work shown. Not all models return this field — the toggle only appears when a message actually has reasoning content.

### 3. Settings
- OpenRouter API key (stored via `flutter_secure_storage`, never in plaintext prefs).
- Model selection.
- **Test connection** button — hits a lightweight OpenRouter endpoint (not a full completion) to validate the key/model without burning tokens.
- Max tokens, temperature.
- Theme (light/dark/system).
- **Memory injection (RAG)**: relevant past messages are retrieved via embedding similarity and injected into context alongside the recent-message sliding window. See [Memory / RAG](#memory--rag-vector-search) below.

### 4. Skills
Built-in: Code Expert, Summarizer, Analyst, Creative Writer, Teacher.
Users can add their own custom skills. Skills are just named system-prompt presets, stored in the same table as built-ins (`is_builtin` flag) so the UI doesn't need to branch on origin.

### 5. Export / Import
Since there's no cloud sync, export/import is the sole path for moving data between devices:
- Exported as a `.zip` containing:
  - `manifest.json` — chats, folders, messages, stars, skills, settings (**excluding the API key**), with a `schemaVersion` field for forward compatibility.
  - `/media/` — attachments referenced by relative path (not base64-embedded, to keep the file small and parsing fast).
- Embeddings are **not** exported — they're treated as a derived/rebuildable cache and recomputed on import, avoiding lock-in to a specific embedding model.
- API key is never included in the export; it's re-entered per device.

## Screens
- **Chat screen** — main conversation view.
- **Settings drawer**, containing:
  - Chats (with folders)
  - Settings
  - Skills
  - Starred
  - Export data
  - Import data

## Architecture

### Local-first, no cloud sync
Each device's local database is the source of truth. No Firebase or other backend — this avoids conflict resolution, multi-device merge logic, and cloud costs entirely. Data moves between devices only via manual export/import.

### Local database
Use a relational or object database with proper relations — **`drift`** (SQL, type-safe) or **`Isar`** (NoSQL, fast, good embedding support) — rather than flat JSON blobs. Core tables:
- `chats`
- `folders`
- `messages`
- `stars` (join table: `message_id`, `starred_at`)
- `skills` (`is_builtin` flag)
- `message_embeddings` (see below)

Media files (images, video, audio, PDFs) are stored on-device in app storage; the DB holds file paths/references, not blobs.

### Memory / RAG (vector search)
Given the app's realistic scale (thousands, not millions, of messages), a dedicated vector database is unnecessary:
- Generate embeddings (via OpenRouter/OpenAI embeddings endpoint, or an on-device model for full offline support) when a message is saved.
- Store each embedding as a vector column alongside the message in the local DB.
- At query time, brute-force cosine similarity over the relevant embeddings (scoped to the current chat, or all chats for cross-chat memory) in Dart.
- Retrieve top-K similar past messages and inject them into context alongside the recent-message sliding window.
- If brute-force scanning becomes a bottleneck at higher message counts, migrate to an indexed option (e.g., `sqlite-vec`, or Isar/ObjectBox vector indexing) — not needed for v1.

### Multimodal cost awareness
Video and scanned-PDF paths are the most token-expensive. The UI should show an estimated token/cost count before sending video or large scanned PDFs, so users aren't surprised by API cost.

## Suggested build order

1. **Text + settings + skills core** — local DB, secure API key storage, model/token/temperature settings, test-connection call, built-in + custom skills. Get one solid text chat loop working end to end first.
2. **Chat organization** — folders, star, copy, fork (local-only).
3. **File & image input** — file picker, local text extraction for text PDFs, compression pipeline, isolate-based processing.
4. **Audio recording + transcription** — chunking, OpenRouter transcription endpoint, text field population.
5. **Scanned PDF + video via vision models** — page-image batching, video frame sampling, cost estimation UI.
6. **Export/import** — versioned manifest + media folder.
7. **RAG memory** — embedding generation and storage, similarity retrieval, context injection.

## Tech notes
- **Secure storage**: `flutter_secure_storage` for the API key — never `SharedPreferences`.
- **Isolates**: `compute()` for PDF splitting, image/video compression, embedding generation, and similarity search over large message sets.
- **Video processing**: `ffmpeg_kit_flutter` or `video_thumbnail` for frame extraction.
- **Image compression**: `flutter_image_compress`.
- **PDF text extraction**: e.g. `syncfusion_flutter_pdf` or similar, with fallback to page-image rendering when extracted text is empty (indicating a scanned PDF).

## Local DB schema

Illustrative schema (works for either `drift` or `Isar`; column names shown as SQL-style for clarity).

### `folders`
| Column | Type | Notes |
|---|---|---|
| `id` | text/uuid, PK | |
| `name` | text | |
| `created_at` | datetime | |
| `sort_order` | integer | for manual reordering in UI |

### `chats`
| Column | Type | Notes |
|---|---|---|
| `id` | text/uuid, PK | |
| `folder_id` | text, FK → folders.id, nullable | null = unfiled |
| `title` | text | auto-generated or user-renamed |
| `skill_id` | text, FK → skills.id, nullable | active skill/system prompt for this chat |
| `forked_from_message_id` | text, FK → messages.id, nullable | set if this chat was created via fork |
| `total_input_tokens` | integer | running sum across all turns, updated on each response |
| `total_output_tokens` | integer | running sum across all turns, updated on each response |
| `created_at` | datetime | |
| `updated_at` | datetime | for sorting chat list by recency |

### `messages`
| Column | Type | Notes |
|---|---|---|
| `id` | text/uuid, PK | |
| `chat_id` | text, FK → chats.id | |
| `role` | text | `user` / `assistant` / `system` |
| `content` | text | message text (or transcript, for audio) |
| `input_type` | text | `text` / `image` / `video` / `audio` / `pdf` |
| `attachment_path` | text, nullable | relative path to media file on device |
| `input_tokens` | integer, nullable | prompt tokens billed for this turn (assistant messages only) |
| `output_tokens` | integer, nullable | completion tokens billed for this turn (assistant messages only) |
| `reasoning` | text, nullable | model's reasoning content, if the API returned one (assistant messages only) |
| `created_at` | datetime | |
| `edited_at` | datetime, nullable | |

### `stars` (join table)
| Column | Type | Notes |
|---|---|---|
| `message_id` | text, FK → messages.id | |
| `starred_at` | datetime | |

### `skills`
| Column | Type | Notes |
|---|---|---|
| `id` | text/uuid, PK | |
| `name` | text | e.g. "Code Expert" |
| `system_prompt` | text | |
| `is_builtin` | boolean | true for the 5 defaults |
| `created_at` | datetime | |

### `message_embeddings`
| Column | Type | Notes |
|---|---|---|
| `message_id` | text, FK → messages.id, PK | one embedding per message |
| `vector` | blob (float array) | embedding vector |
| `model` | text | embedding model used, for cache invalidation if model changes |
| `created_at` | datetime | |

### `settings` (single row or key-value table)
| Column | Type | Notes |
|---|---|---|
| `openrouter_model` | text | |
| `max_tokens` | integer | |
| `temperature` | real | |
| `theme` | text | `light` / `dark` / `system` |

*(API key lives in `flutter_secure_storage`, not this table.)*

**Relations at a glance:** `folders 1—* chats 1—* messages 1—1 message_embeddings`, `messages *—* stars` (via join), `chats *—1 skills`.

## Message-send pipeline

End-to-end flow when the user sends a message (text, with or without an attachment):

1. **Capture input**
   - Text typed directly, or
   - Attachment picked (image/video/PDF/audio) → routed to the relevant pre-processor before reaching this pipeline:
     - Image → compress (`flutter_image_compress`).
     - Video → sample frames (~1 per 2–3s, capped at 20–30 frames).
     - PDF → extract text locally; if empty, render pages to images and batch in groups of 20.
     - Audio → chunk if long, send to OpenRouter transcription endpoint, populate text field with returned transcript for user review.
   - All of the above run inside `compute()` isolates.

2. **Persist the user message**
   - Insert a row into `messages` (role = `user`) immediately, with `attachment_path` set if applicable, so the message is saved even if the network call later fails.

3. **Generate embedding**
   - Fire off an embedding request for the new message's text/transcript.
   - Store the result in `message_embeddings`. This can run concurrently with step 4 — it doesn't block sending.

4. **Retrieve context**
   - Pull the recent-message sliding window for the current chat (last N messages, token-budget aware).
   - Run similarity search: brute-force cosine similarity between the new message's embedding and stored embeddings (scoped to this chat, or cross-chat if cross-chat memory is enabled) → top-K most relevant past messages.
   - Deduplicate anything already in the sliding window.

5. **Assemble the request**
   - System prompt = active skill's `system_prompt`.
   - Inject top-K retrieved messages (labeled as "relevant earlier context") ahead of the recent sliding window.
   - Append the new user message (plus any image/video frames/PDF page-images as content blocks, per OpenRouter's multimodal message format).
   - Apply `max_tokens` / `temperature` from settings.

6. **Call OpenRouter**
   - POST to `/api/v1/chat/completions` (or the dedicated audio/transcription endpoint for audio-only cases, handled earlier in step 1).
   - Show a cost/token estimate before sending for video or large scanned-PDF batches (per the cost-awareness note above).
   - On failure: retry with exponential backoff; if it still fails, mark the message with an error state in the UI (don't lose the user's already-persisted message).

7. **Persist and display the response**
   - Insert the assistant's reply into `messages` (role = `assistant`), reading `input_tokens`/`output_tokens` straight from the response's `usage.prompt_tokens` / `usage.completion_tokens`, and `reasoning` from the response's `reasoning` field if present.
   - Generate and store its embedding (same as step 3) so it's retrievable in future turns.
   - Update `chats.updated_at`, `chats.total_input_tokens`, and `chats.total_output_tokens` (increment by this turn's values) for chat-list sorting and the running-total display.
   - Render the per-message token count under the bubble and refresh the chat-header running total.
   - If `reasoning` is present, render the collapsed "Show reasoning" toggle under the message; omit it entirely when absent.

8. **Post-send**
   - User can star, copy, or fork either message at this point — all local DB operations, no API calls involved.

## Explicitly out of scope (for now)
- Cloud sync (Firebase or otherwise) — removed by design; export/import covers cross-device portability.
- Dedicated cloud vector database — brute-force local similarity search is sufficient at this scale.