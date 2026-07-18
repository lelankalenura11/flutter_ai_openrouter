# Flutter AI Chat App - Performance Optimization Guide

A comprehensive guide to diagnosing, preventing, and resolving performance issues in Flutter AI chat applications that communicate with LLM APIs via streaming.

---

## Table of Contents

1. [Diagnosing Performance Issues](#1-diagnosing-performance-issues)
2. [Best Practices to Avoid Issues](#2-best-practices-to-avoid-issues)
3. [Optimization Plan](#3-optimization-plan)
4. [Chat-Specific Patterns](#4-chat-specific-patterns)
5. [Tools & Monitoring](#5-tools--monitoring)

---

## 1. Diagnosing Performance Issues

### 1.1 Flutter DevTools (Primary Tool)

| Tab | What to Check | Red Flags |
|-----|--------------|-----------|
| **Performance** | Frame timeline | Red bars = jank (>16ms/frame) |
| **CPU Profiler** | Hot methods | Heavy `build()`, JSON parsing |
| **Memory** | Heap growth | Memory growing indefinitely on scroll |
| **Network** | Request timing | Slow API responses, redundant calls |

### 1.2 Quick Instrumentation

```dart
// Wrap suspected expensive operations
final stopwatch = Stopwatch()..start();
// ... operation ...
debugPrint('Operation took: \${stopwatch.elapsedMilliseconds}ms');
```

### 1.3 Chat-Specific Checks

| Check | Method | Target |
|-------|--------|--------|
| Scroll jank | DevTools overlay | < 55 FPS with 100+ messages |
| Rebuild count | `print` in `build()` | No rebuilds for off-screen items |
| Memory leaks | Memory tab | Stable after scrolling long history |
| Token lag | Visual + timer | <100ms from API chunk to UI |
| First paint | Stopwatch | <100ms for message list |

---

## 2. Best Practices to Avoid Issues

### 2.1 ListView Optimization (Critical)

Always use `ListView.builder` with unique keys:

```dart
ListView.builder(
  reverse: true,              // Chat-style: newest at bottom
  itemCount: messages.length,
  itemBuilder: (context, index) {
    final message = messages[index];
    return ChatBubble(
      key: ValueKey(message.id),  // Essential: prevents unnecessary rebuilds
      message: message,
    );
  },
)
```

**Additional optimizations:**

```dart
ListView.builder(
  reverse: true,
  itemExtent: 80,                  // Skip layout calculations
  // OR use prototypeItem for variable heights:
  prototypeItem: ChatBubble(message: dummyMessage),
  findChildIndexCallback: (key) {
    final valueKey = key as ValueKey<String>;
    return messages.indexWhere((m) => m.id == valueKey.value);
  },
  itemCount: messages.length,
  itemBuilder: (context, index) => ChatBubble(
    key: ValueKey(messages[index].id),
    message: messages[index],
  ),
)
```

### 2.2 Widget Granularity

Split widgets to minimize rebuild scope:

```dart
class ChatBubble extends StatelessWidget {
  final Message message;
  const ChatBubble({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Only rebuilds when avatar changes
        MessageAvatar(userId: message.userId),
        // Only rebuilds when content changes
        MessageContent(content: message.content),
        // Only rebuilds when timestamp changes
        MessageTime(time: message.timestamp),
      ],
    );
  }
}
```

Use `const` aggressively for static UI:

```dart
const SizedBox(height: 8)
const Padding(padding: EdgeInsets.all(12))
const Icon(Icons.send)
```

### 2.3 AI Token Streaming

**Buffer rapid updates** — don't rebuild per token:

```dart
class ChatController extends ChangeNotifier {
  final List<Message> _messages = [];
  String _currentBuffer = '';
  Timer? _flushTimer;

  void onTokenReceived(String token) {
    _currentBuffer += token;

    // Debounce: update UI every 50-100ms, not per token
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 80), () {
      _messages.last.content += _currentBuffer;
      _currentBuffer = '';
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}
```

**Use `ValueNotifier` for granular updates:**

```dart
class StreamingText extends StatelessWidget {
  final ValueNotifier<String> textNotifier;

  const StreamingText({required this.textNotifier, super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: textNotifier,
      builder: (context, text, child) {
        return Text(text); // Only this text rebuilds
      },
    );
  }
}
```

### 2.4 API & Data Layer

**Pagination for chat history:**

```dart
Future<void> loadMoreMessages() async {
  if (_isLoading || !_hasMore) return;
  _isLoading = true;

  final olderMessages = await api.getMessages(
    beforeId: _messages.first.id,
    limit: 50, // Load in chunks
  );

  _messages.insertAll(0, olderMessages);
  _isLoading = false;
  notifyListeners();
}
```

**Offload heavy parsing with `compute`:**

```dart
// Parse large JSON off the main thread
final messages = await compute(parseMessages, rawJsonResponse);

// parse_messages.dart
List<Message> parseMessages(String rawJson) {
  final List<dynamic> json = jsonDecode(rawJson);
  return json.map((e) => Message.fromJson(e)).toList();
}
```

**Cache rendered markdown:**

```dart
class MarkdownMessage extends StatefulWidget {
  final String content;
  const MarkdownMessage({required this.content, super.key});

  @override
  State<MarkdownMessage> createState() => _MarkdownMessageState();
}

class _MarkdownMessageState extends State<MarkdownMessage> {
  Widget? _cachedRender;

  @override
  void didUpdateWidget(covariant MarkdownMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _cachedRender = null; // Invalidate cache
    }
  }

  @override
  Widget build(BuildContext context) {
    return _cachedRender ??= MarkdownBody(data: widget.content);
  }
}
```

### 2.5 Image & Media

```dart
CachedNetworkImage(
  imageUrl: avatarUrl,
  placeholder: (context, url) => const CircleAvatar(
    child: Icon(Icons.person),
  ),
  memCacheWidth: 100,    // Downsample before caching
  memCacheHeight: 100,
  maxAge: const Duration(days: 7),
)
```

---

## 3. Optimization Plan

### Phase 1: Baseline (Day 1)

```bash
# Run in profile mode
flutter run --profile
```

- [ ] Record 60s DevTools session during typical usage
- [ ] Document: average FPS, worst frames, memory baseline
- [ ] Test: scroll 100+ messages, start AI chat, receive long response

### Phase 2: Quick Wins (Days 2-3)

| Issue | Fix | Expected Impact |
|-------|-----|----------------|
| Scroll jank | Add `ValueKey` to `ListView.builder` | 30-50% frame time reduction |
| Excessive rebuilds | Use `const`, split widgets | Fewer rebuilds in DevTools |
| Memory growth | Paginate messages (keep last 100) | Stable memory curve |
| Slow first paint | Add `prototypeItem` | Faster initial render |

### Phase 3: Streaming & API (Days 4-5)

- [ ] Implement token buffering (50-100ms debounce)
- [ ] Cancel in-flight requests on new user message
- [ ] Use persistent connections for SSE/WebSocket
- [ ] Add offline message queue
- [ ] Compress payloads if not already

### Phase 4: Advanced (Week 2)

- [ ] Custom `RenderObject` for simple bubbles (if still janky)
- [ ] Virtual scrolling for 1000+ message histories
- [ ] Worker isolate for markdown/syntax highlighting
- [ ] Use `Selector` instead of `Consumer` for granular rebuilds:

```dart
Selector<ChatController, String>(
  selector: (_, controller) => controller.lastMessageId,
  builder: (_, lastId, __) => ListView.builder(...),
)
```

### Phase 5: Monitoring

Add debug assertions:

```dart
assert(() {
  final sw = Stopwatch()..start();
  scheduleMicrotask(() {
    if (sw.elapsedMilliseconds > 16) {
      debugPrint('⚠️ Build took \${sw.elapsedMilliseconds}ms');
    }
  });
  return true;
}());
```

CI integration tests:
- Scroll through 500 messages, fail if FPS < 55

---

## 4. Chat-Specific Patterns

### Message Model

```dart
@immutable
class Message {
  final String id;           // UUID for ValueKey
  final String content;
  final String role;         // 'user' | 'assistant'
  final DateTime timestamp;
  final MessageStatus status; // sending | sent | error

  const Message({
    required this.id,
    required this.content,
    required this.role,
    required this.timestamp,
    this.status = MessageStatus.sent,
  });
}
```

### API Service with Cancellation

```dart
class ChatApiService {
  CancelToken? _currentCancelToken;

  Stream<String> sendMessage(String content) async* {
    _currentCancelToken?.cancel();
    _currentCancelToken = CancelToken();

    final response = await dio.post<ResponseBody>(
      '/chat',
      data: {'message': content},
      options: Options(responseType: ResponseType.stream),
      cancelToken: _currentCancelToken,
    );

    await for (final chunk in response.data!.stream) {
      yield utf8.decode(chunk);
    }
  }

  void cancel() => _currentCancelToken?.cancel();
}
```

### State Management with Selectors

```dart
class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;
  final String currentStreamBuffer;

  ChatState copyWith({...}) => ...;
}

// In UI: only rebuild when messages change
Selector<ChatState, List<Message>>(
  selector: (state) => state.messages,
  builder: (context, messages, _) => MessageList(messages: messages),
)

// Separate selector for loading state
Selector<ChatState, bool>(
  selector: (state) => state.isLoading,
  builder: (context, isLoading, _) => TypingIndicator(visible: isLoading),
)
```

---

## 5. Tools & Monitoring

| Tool | Platform | Use Case |
|------|----------|----------|
| Flutter DevTools | All | Frame analysis, widget rebuilds, memory |
| Performance Overlay | All | Real-time FPS overlay |
| Dart CPU Profiler | All | Hot method identification |
| Android Studio Profiler | Android | Native memory, network, energy |
| Xcode Instruments | iOS | iOS-specific profiling |
| Firebase Performance | All | Production monitoring |

### Recommended pub.dev Packages

```yaml
dependencies:
  # Caching
  cached_network_image: ^3.4.0
  flutter_cache_manager: ^3.4.0

  # State management (choose one)
  flutter_bloc: ^9.0.0
  provider: ^6.1.0
  riverpod: ^2.6.0

  # Markdown rendering
  flutter_markdown: ^0.7.0

  # HTTP with cancellation
  dio: ^5.7.0

dev_dependencies:
  # Performance testing
  integration_test:
    sdk: flutter
```

---

## Quick Reference Checklist

- [ ] `ListView.builder` with `reverse: true` and `ValueKey`
- [ ] Token updates debounced (50-100ms)
- [ ] Images cached and downsampled (`memCacheWidth/Height`)
- [ ] Old messages paginated (unload from memory)
- [ ] API requests cancelable (`CancelToken`)
- [ ] `const` constructors for static UI
- [ ] Markdown parsing isolated or cached
- [ ] Typing indicators don't rebuild message list
- [ ] Chat history serialized efficiently
- [ ] Profile mode testing before release

---

## License

MIT
