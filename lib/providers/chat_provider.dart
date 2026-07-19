import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/services/openrouter_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/embedding_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/file_compression_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/pdf_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/video_service.dart';
import 'package:path_provider/path_provider.dart';

/// Maps raw error strings to user-friendly messages
String _friendlyError(dynamic error) {
  final s = error.toString().toLowerCase();
  if (s.contains('401') || s.contains('unauthorized') || s.contains('invalid api key')) {
    return 'Invalid API key. Check your API key in Settings.';
  }
  if (s.contains('429') || s.contains('rate limit') || s.contains('too many requests')) {
    return 'Rate limited. Please wait a moment before sending another message.';
  }
  if (s.contains('402') || s.contains('insufficient') || s.contains('quota') || s.contains('credits')) {
    return 'Insufficient credits. Check your OpenRouter account balance.';
  }
  if (s.contains('network') || s.contains('connection refused') ||
      s.contains('dns') || s.contains('timeout') || s.contains('socket')) {
    return 'Unable to connect. Check your internet connection and try again.';
  }
  if (s.contains('500') || s.contains('502') || s.contains('503') || s.contains('server error')) {
    return 'OpenRouter server error. Please try again later.';
  }
  if (s.contains('400') || s.contains('bad request')) {
    return 'Invalid request. The selected model may not be available.';
  }
  if (s.contains('model')) {
    return 'The selected model is not available. Try a different model in Settings.';
  }
  return 'Something went wrong. Please try again.';
}

class ChatProvider extends ChangeNotifier {
  final AppDatabase _db;
  final OpenRouterService _openRouterService;
  final EmbeddingService _embeddingService;
  final Uuid _uuid = const Uuid();

  // Streaming state for assistant messages being generated
  String? _streamingMessageId;
  String? _streamingChatId;

  // Token debouncing — buffer rapid token updates to avoid rebuilding UI per token
  Timer? _debounceTimer;
  String _debounceBuffer = '';
  bool _debounceNeedsFlush = false;
  static const Duration _debounceInterval = Duration(milliseconds: 80);
  // Track the assistant message ID for the current debounce cycle
  String? _debounceAssistantId;

  // Chats
  List<ChatsTableData> _chats = [];
  List<MessagesTableData> _messages = [];
  String? _currentChatId;
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  String? _activeSkillId;
  String? _activeSkillPrompt;

  // The streaming content accumulated so far (for persistence across chat switches)
  String _streamingContent = '';
  String? _streamingReasoning;
  int? _streamingInputTokens;
  int? _streamingOutputTokens;

  // Folders
  List<FoldersTableData> _folders = [];

  // Stars
  Set<String> _starredMessageIds = {};
  List<MessagesTableData> _starredMessages = [];
  List<StarredMessageInfo> _starredWithChatInfo = [];

  // Failed messages
  Set<String> _failedMessageIds = {};

  // Streaming isolation — separate notifier for in-progress content
  final StreamingState streamingState = StreamingState();
  bool _streamingFinished = false;

  // Pending attachment
  FileAttachment? _pendingAttachment;

  // PDF render cache — avoids re-rendering the same PDF file on every send
  final Map<String, PdfRenderResult> _pdfRenderCache = {};
  bool _isPreparingPdf = false;

  bool get isPreparingPdf => _isPreparingPdf;

  // Getters
  List<ChatsTableData> get chats => _chats;
  List<MessagesTableData> get messages => _messages;
  String? get currentChatId => _currentChatId;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;
  String? get activeSkillId => _activeSkillId;
  String? get activeSkillPrompt => _activeSkillPrompt;
  List<FoldersTableData> get folders => _folders;
  Set<String> get starredMessageIds => _starredMessageIds;
  List<MessagesTableData> get starredMessages => _starredMessages;
  List<StarredMessageInfo> get starredWithChatInfo => _starredWithChatInfo;
  Set<String> get failedMessageIds => _failedMessageIds;
  FileAttachment? get pendingAttachment => _pendingAttachment;
  String? get streamingMessageId => _streamingMessageId;
  String? get streamingChatId => _streamingChatId;

  /// True if any chat (not just the current one) is generating
  bool get anyChatGenerating => _isSending && _streamingChatId != null;

  /// True if the given chat ID is currently generating
  bool isChatGenerating(String chatId) =>
      _isSending && _streamingChatId == chatId;

  /// Public access to the database (for export/import service)
  AppDatabase get database => _db;

  ChatProvider(this._db, this._openRouterService, this._embeddingService);

  /// Flush buffered tokens to the UI by updating the in-memory message.
  void _flushDebounce() {
    _debounceNeedsFlush = false;
    _debounceBuffer = '';

    final msgId = _debounceAssistantId;
    if (msgId == null) return;

    final idx = _messages.indexWhere((m) => m.id == msgId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        content: _streamingContent,
      );
      notifyListeners();
    }
  }

  ChatsTableData? get currentChat {
    if (_currentChatId == null) return null;
    return _chats.where((c) => c.id == _currentChatId).firstOrNull;
  }

  void setPendingAttachment(FileAttachment? attachment) {
    _pendingAttachment = attachment;
    notifyListeners();
  }

  void clearPendingAttachment() {
    _pendingAttachment = null;
    notifyListeners();
  }

  Future<String> _storeAttachmentLocally(String sourcePath, String inputType) async {
    final appDir = await getApplicationDocumentsDirectory();
    final attachDir = Directory('${appDir.path}/attachments');
    if (!attachDir.existsSync()) {
      attachDir.createSync(recursive: true);
    }
    final ext = sourcePath.split('.').last;
    final destPath = '${attachDir.path}/${_uuid.v4()}.$ext';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  // ========================================================================
  // Embedding helpers
  // ========================================================================

  /// Generate and store an embedding for a message (non-blocking).
  /// This is best-effort — failures are silently logged.
  Future<void> _generateAndStoreEmbedding(String messageId, String text) async {
    try {
      final vector = await _embeddingService.generateEmbedding(text);
      if (vector == null) return;

      await _db.insertEmbedding(MessageEmbeddingsTableCompanion(
        messageId: Value(messageId),
        vector: Value(vector.join(',')),
        model: const Value('openai/text-embedding-3-small'),
        createdAt: Value(DateTime.now()),
      ));
    } catch (e) {
      debugPrint('Failed to generate/store embedding for $messageId: $e');
    }
  }

  /// Retrieve top-K similar messages from the same chat using cosine similarity.
  ///
  /// Returns message content strings that can be injected as context.
  Future<List<String>> _retrieveRelevantMemory(
    String queryText,
    String chatId, {
    int topK = 5,
  }) async {
    try {
      // Get query embedding
      final queryVector = await _embeddingService.generateEmbedding(queryText);
      if (queryVector == null) return [];

      // Get existing embeddings for this chat
      final storedEmbeddings = await _db.getEmbeddingsForChat(chatId);
      if (storedEmbeddings.isEmpty) return [];

      // Compute similarity scores
      final scored = <_ScoredMessage>[];
      for (final stored in storedEmbeddings) {
        final parts = stored.vector.split(',');
        if (parts.length != queryVector.length) continue;

        final storedVector = parts.map((s) => double.tryParse(s) ?? 0.0).toList();
        if (storedVector.length != queryVector.length) continue;

        final score = cosineSimilarity(queryVector, storedVector);
        if (score > 0.5) { // Only consider reasonably similar results
          scored.add(_ScoredMessage(stored.messageId, score));
        }
      }

      // Sort by score descending, take top-K
      scored.sort((a, b) => b.score.compareTo(a.score));
      final topIds = scored.take(topK).map((s) => s.messageId).toSet();

      // Get message contents.
      final results = <String>[];
      for (final msg in _messages) {
        if (topIds.contains(msg.id) && msg.role == 'user') {
          results.add(msg.content);
        }
      }
      return results;
    } catch (e) {
      debugPrint('Memory retrieval error: $e');
      return [];
    }
  }

  // ========================================================================
  // Cancel generation
  // ========================================================================

  void cancelResponse() {
    _openRouterService.cancelRequest();
    _isSending = false;
    _streamingMessageId = null;
    _streamingChatId = null;
    _streamingContent = '';
    _streamingReasoning = null;
    _streamingInputTokens = null;
    _streamingOutputTokens = null;
    notifyListeners();
  }

  // ========================================================================
  // Chat loading & management
  // ========================================================================

  Future<void> loadChats() async {
    _isLoading = true;
    notifyListeners();

    try {
      _chats = await _db.getAllChats();
      _folders = await _db.getAllFolders();
      await _loadStarredState();
    } catch (e) {
      _error = _friendlyError(e);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadStarredState() async {
    final stars = await _db.getAllStars();
    _starredMessageIds = stars.map((s) => s.messageId).toSet();
    _starredMessages = await _db.getStarredMessages();
    _starredWithChatInfo = await _db.getStarredWithChatInfo();
  }

  Future<String?> createChat({
    String? folderId,
    String? skillId,
    String? title,
  }) async {
    try {
      final now = DateTime.now();
      final id = _uuid.v4();
      final chat = ChatsTableCompanion(
        id: Value(id),
        folderId: Value(folderId),
        title: Value(title ?? 'New Chat'),
        skillId: Value(skillId),
        isPinned: const Value(false),
        totalInputTokens: const Value(0),
        totalOutputTokens: const Value(0),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
      await _db.insertChat(chat);
      _chats.insert(0, chat.toData());
      _currentChatId = id;
      _messages = [];
      notifyListeners();
      return id;
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
      return null;
    }
  }

  Future<void> selectChat(String id) async {
    _currentChatId = id;
    // Clear PDF cache when switching chats to free memory on mobile
    _pdfRenderCache.clear();
    _isLoading = true;
    notifyListeners();

    try {
      _messages = await _db.getMessages(id);

      // If this chat is currently streaming, add the in-progress placeholder
      if (_streamingChatId == id && _streamingMessageId != null) {
        final hasPlaceholder = _messages.any((m) => m.id == _streamingMessageId);
        if (!hasPlaceholder) {
          _messages.add(MessagesTableData(
            id: _streamingMessageId!,
            chatId: id,
            role: 'assistant',
            content: _streamingContent,
            inputType: 'text',
            attachmentPath: null,
            inputTokens: _streamingInputTokens,
            outputTokens: _streamingOutputTokens,
            reasoning: _streamingReasoning,
            status: 'sending',
            createdAt: DateTime.now(),
            editedAt: null,
          ));
        } else {
          // Update existing placeholder with streaming content
          final idx = _messages.indexWhere((m) => m.id == _streamingMessageId);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(
              content: _streamingContent,
            );
          }
        }
      }

      _failedMessageIds = _messages
          .where((m) => m.status == 'failed')
          .map((m) => m.id)
          .toSet();
    } catch (e) {
      _error = _friendlyError(e);
    }

    _isLoading = false;
    notifyListeners();

    // Retry auto-title if still default placeholder and streaming is not in progress.
    // This handles cases where the original _autoTitleChat call failed
    // (e.g. app was backgrounded when the response completed).
    if (_streamingChatId != id) {
      final chat = currentChat;
      final title = chat?.title;
      if ((title == 'New Chat' || title == 'Forked chat') &&
          _messages.any((m) => m.role == 'assistant' && m.status == 'sent')) {
        final firstUser = _messages.where((m) => m.role == 'user').firstOrNull;
        final firstAssistant =
            _messages.where((m) => m.role == 'assistant' && m.status == 'sent').firstOrNull;
        if (firstUser != null && firstAssistant != null) {
          _autoTitleChat(id, firstUser.content, firstAssistant.content);
        }
      }
    }
  }

  Future<void> deleteAllChats() async {
    try {
      await _db.deleteAllChats();
      _chats = [];
      _folders = [];
      _messages = [];
      _currentChatId = null;
      _starredMessageIds = {};
      _starredMessages = [];
      _starredWithChatInfo = [];
      _failedMessageIds = {};
      _streamingMessageId = null;
      _streamingChatId = null;
      _streamingContent = '';
      _streamingReasoning = null;
      _streamingInputTokens = null;
      _streamingOutputTokens = null;
      _isSending = false;
      notifyListeners();
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  Future<void> deleteChat(String id) async {
    try {
      // Clean up attachment files before deletion
      final msgs = await _db.getMessages(id);
      for (final msg in msgs) {
        if (msg.attachmentPath != null) {
          try {
            final file = File(msg.attachmentPath!);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}
        }
      }
      await _db.deleteChat(id);
      _chats.removeWhere((c) => c.id == id);
      if (_currentChatId == id) {
        _currentChatId = null;
        _messages = [];
      }
      notifyListeners();
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
    }
  }
  Future<void> renameChat(String chatId, String title) async {
    try {
      await _db.renameChat(chatId, title);
      _chats = await _db.getAllChats();
      notifyListeners();
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  // ========================================================================
  // Folder management
  // ========================================================================

  Future<String?> createFolder(String name) async {
    try {
      final id = _uuid.v4();
      final folder = FoldersTableCompanion(
        id: Value(id),
        name: Value(name),
        createdAt: Value(DateTime.now()),
        sortOrder: const Value(0),
      );
      await _db.insertFolder(folder);
      _folders.add(FoldersTableData(
        id: id,
        name: name,
        createdAt: DateTime.now(),
        sortOrder: 0,
      ));
      notifyListeners();
      return id;
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
      return null;
    }
  }

  Future<void> renameFolder(String id, String name) async {
    try {
      await _db.updateFolder(FoldersTableCompanion(
        id: Value(id),
        name: Value(name),
      ));
      _folders = await _db.getAllFolders();
      notifyListeners();
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  Future<void> deleteFolder(String id) async {
    try {
      await _db.deleteFolder(id);
      _folders.removeWhere((f) => f.id == id);
      _chats = await _db.getAllChats();
      notifyListeners();
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  Future<void> moveChatToFolder(String chatId, String? folderId) async {
    try {
      await _db.moveChatToFolder(chatId, folderId);
      _chats = await _db.getAllChats();
      notifyListeners();
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  List<ChatsTableData> getChatsByFolder(String? folderId) {
    if (folderId == null) {
      return _chats.where((c) => c.folderId == null).toList();
    }
    return _chats.where((c) => c.folderId == folderId).toList();
  }

  // ========================================================================
  // Pin / Unpin
  // ========================================================================

  Future<void> togglePinChat(String chatId) async {
    try {
      final chat = _chats.where((c) => c.id == chatId).firstOrNull;
      if (chat == null) return;
      await (_db.update(_db.chatsTable)..where((t) => t.id.equals(chatId)))
          .write(ChatsTableCompanion(isPinned: Value(!chat.isPinned)));
      _chats = await _db.getAllChats();
      notifyListeners();
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  // ========================================================================
  // Skill selection
  // ========================================================================

  void setSkill(String? skillId, String? prompt) {
    _activeSkillId = skillId;
    _activeSkillPrompt = prompt;
    notifyListeners();
  }

  // ========================================================================
  // Star management
  // ========================================================================

  Future<void> toggleStar(String messageId) async {
    await _db.toggleStar(messageId);
    if (_starredMessageIds.contains(messageId)) {
      _starredMessageIds.remove(messageId);
    } else {
      _starredMessageIds.add(messageId);
    }
    _starredMessages = await _db.getStarredMessages();
    _starredWithChatInfo = await _db.getStarredWithChatInfo();
    notifyListeners();
  }

  bool isMessageStarred(String messageId) =>
      _starredMessageIds.contains(messageId);

  // ========================================================================
  // Fork chat
  // ========================================================================

  Future<String?> forkChat(String fromMessageId) async {
    if (_currentChatId == null) return null;

    try {
      final sourceMessages = await _db.forkMessages(fromMessageId, _currentChatId!);
      if (sourceMessages.isEmpty) return null;

      final now = DateTime.now();
      final newChatId = _uuid.v4();

      final chat = ChatsTableCompanion(
        id: Value(newChatId),
        title: Value('Forked chat'),
        forkedFromMessageId: Value(fromMessageId),
        totalInputTokens: const Value(0),
        totalOutputTokens: const Value(0),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
      await _db.insertChat(chat);

      for (final msg in sourceMessages) {
        await _db.insertMessage(MessagesTableCompanion(
          id: Value(_uuid.v4()),
          chatId: Value(newChatId),
          role: Value(msg.role),
          content: Value(msg.content),
          inputType: Value(msg.inputType),
          attachmentPath: Value(msg.attachmentPath),
          inputTokens: Value(msg.inputTokens),
          outputTokens: Value(msg.outputTokens),
          reasoning: Value(msg.reasoning),
          status: const Value('sent'),
          createdAt: Value(msg.createdAt),
        ));
      }

      _chats = await _db.getAllChats();
      _currentChatId = newChatId;
      _messages = await _db.getMessages(newChatId);
      notifyListeners();
      return newChatId;
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
      return null;
    }
  }

  // ========================================================================
  // Smart auto-title
  // ========================================================================

  Future<void> _autoTitleChat(String chatId, String firstUserMessage, String firstResponse) async {
    try {
      final settings = await _db.getSettings();
      if (settings == null) return;

      final messages = [
        {
          'role': 'system',
          'content': 'Generate a short chat title (5 words maximum, no quotes). Topic: ${firstUserMessage.replaceAll('\n', ' ').trim()}',
        },
        {
          'role': 'user',
          'content': firstUserMessage,
        },
        {
          'role': 'assistant',
          'content': firstResponse,
        },
      ];

      final response = await _openRouterService.sendChatMessage(
        model: 'openai/gpt-4o-mini',
        messages: messages,
        maxTokens: 30,
        temperature: 0.3,
      );

      if (!response.isError && response.content != null && response.content!.trim().isNotEmpty) {
        var title = response.content!.trim();
        title = title.replaceAll(RegExp(r'''^["']|["']$'''), '');
        if (title.length > 60) title = '${title.substring(0, 57)}...';
        await _db.renameChat(chatId, title);
        _chats = await _db.getAllChats();
        notifyListeners();
      }
    } catch (_) {}
  }

  // ========================================================================
  // Send message with streaming support
  // ========================================================================

  /// Transcribe an audio file to text using OpenRouter's STT endpoint.
  ///
  /// Returns the transcribed text, or null on failure.
  Future<String?> transcribeAudio(String filePath) async {
    return await _openRouterService.transcribeAudio(filePath);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> retryMessage(String messageId) async {
    final msg = _messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null || msg.role != 'user') return;
    await sendMessage(msg.content, messageIdToReplace: messageId);
  }

  Future<void> sendMessage(
    String text, {
    String? messageIdToReplace,
    FileAttachment? attachment,
    String? systemContext,
  }) async {
    if (_currentChatId == null && text.isEmpty && attachment == null) return;

    // Don't allow sending while already streaming
    if (_isSending) return;

    final effectiveAttachment = attachment ?? _pendingAttachment;

    _isSending = true;
    _error = null;
    _streamingFinished = false;
    _streamingChatId = _currentChatId;
    streamingState.isStreaming = true;
    streamingState.content = '';
    streamingState.messageId = null;
    streamingState.notifyListeners();
    notifyListeners();

    try {
      if (_currentChatId == null) {
        final id = await createChat(skillId: _activeSkillId);
        if (id == null) {
          _error = 'Failed to create chat';
          _isSending = false;
          _streamingChatId = null;
          notifyListeners();
          return;
        }
        // Update streaming chat ID now that we have a real chat ID
        _streamingChatId = _currentChatId;
      }

      final settings = await _db.getSettings();
      final model = settings?.openrouterModel ?? 'openai/gpt-4o';
      final maxTokens = settings?.maxTokens ?? 4096;
      final temperature = settings?.temperature ?? 0.7;
      final memoryEnabled = settings?.memoryEnabled ?? false;

      final now = DateTime.now();
      String userMsgId;

      String? storedAttachmentPath;
      String inputType = 'text';
      String storedOriginalName = '';
      if (effectiveAttachment != null) {
        storedAttachmentPath = await _storeAttachmentLocally(
          effectiveAttachment.path,
          effectiveAttachment.inputType,
        );
        inputType = effectiveAttachment.inputType;
        storedOriginalName = effectiveAttachment.displayName;
      }

      if (messageIdToReplace != null) {
        userMsgId = messageIdToReplace;
        await _db.updateMessageStatus(userMsgId, 'sending');
        if (_currentChatId != null) {
          _messages = await _db.getMessages(_currentChatId!);
        }
        _failedMessageIds.remove(userMsgId);
        notifyListeners();
      } else {
        userMsgId = _uuid.v4();
        final userMessage = MessagesTableCompanion(
          id: Value(userMsgId),
          chatId: Value(_currentChatId!),
          role: const Value('user'),
        // Prepend original filename to content for attachment messages
        content: Value(inputType == 'pdf' || inputType == 'image'
            ? '📎 $storedOriginalName\n\n$text'
            : text),
        inputType: Value(inputType),
          attachmentPath: Value(storedAttachmentPath),
          status: const Value('sending'),
          createdAt: Value(now),
        );
        await _db.insertMessage(userMessage);

        _messages.add(MessagesTableData(
          id: userMsgId,
          chatId: _currentChatId!,
          role: 'user',
        content: inputType == 'pdf' || inputType == 'image'
            ? '📎 $storedOriginalName\n\n$text'
            : text,
        inputType: inputType,
          attachmentPath: storedAttachmentPath,
          inputTokens: null,
          outputTokens: null,
          reasoning: null,
          status: 'sending',
          createdAt: now,
          editedAt: null,
        ));
        notifyListeners();
      }

      if (_pendingAttachment != null) {
        _pendingAttachment = null;
        notifyListeners();
      }

      _messages = await _db.getMessages(_currentChatId!);
      notifyListeners();

      // Mark user message as sent
      await _db.updateMessageStatus(userMsgId, 'sent');
      final userMsgIndex = _messages.indexWhere((m) => m.id == userMsgId);
      if (userMsgIndex != -1) {
        _messages[userMsgIndex] = _messages[userMsgIndex].copyWith(status: 'sent');
      }

      // --- Phase 7: Memory Retrieval ---
      List<String> memoryContexts = [];
      if (memoryEnabled && inputType == 'text' && _currentChatId != null) {
        memoryContexts = await _retrieveRelevantMemory(
          text,
          _currentChatId!,
          topK: 5,
        );
      }

      // Pre-render all PDFs (max 3 to limit memory on mobile) before building API messages.
      // Shows a loading state so the user knows the app is working.
      int pdfCount = 0;
      bool needsPdfRender = false;
      for (final msg in _messages) {
        if (msg.attachmentPath != null && msg.inputType == 'pdf' && msg.role == 'user') {
          if (!_pdfRenderCache.containsKey(msg.attachmentPath)) {
            needsPdfRender = true;
            break;
          }
        }
      }
      if (needsPdfRender) {
        _isPreparingPdf = true;
        notifyListeners();
        pdfCount = 0;
        for (final msg in _messages) {
          if (msg.attachmentPath != null && msg.inputType == 'pdf' && msg.role == 'user') {
            if (!_pdfRenderCache.containsKey(msg.attachmentPath)) {
              if (pdfCount >= 3) break;
              final result = await PdfService.renderPdfAsImages(msg.attachmentPath!);
              _pdfRenderCache[msg.attachmentPath!] = result;
              pdfCount++;
            }
          }
        }
        _isPreparingPdf = false;
        notifyListeners();
      }

      // Build message list for API
      final apiMessages = <Map<String, dynamic>>[];

      if (_activeSkillPrompt != null && _activeSkillPrompt!.isNotEmpty) {
        apiMessages.add({
          'role': 'system',
          'content': _activeSkillPrompt,
        });
      }

      // Inject web search context (if provided) — between system prompt and history
      if (systemContext != null && systemContext.isNotEmpty) {
        apiMessages.add({
          'role': 'system',
          'content': systemContext,
        });
      }

      // Inject retrieved memory context (between system prompt and recent history)
      if (memoryContexts.isNotEmpty) {
        final memoryBlock = StringBuffer('Relevant context from earlier in this conversation:\n---\n');
        memoryBlock.write(memoryContexts.join('\n---\n'));
        memoryBlock.write('\n---');
        apiMessages.add({
          'role': 'system',
          'content': memoryBlock.toString(),
        });
      }

      for (final msg in _messages) {
        if (msg.attachmentPath != null && (msg.inputType == 'image')) {
          final content = OpenRouterService.buildMultimodalContent(
            model: model,
            text: msg.content,
            attachmentPath: msg.attachmentPath,
            inputType: msg.inputType,
          );
          apiMessages.add({'role': msg.role, 'content': content});
        } else if (msg.attachmentPath != null && msg.inputType == 'video') {
          // Check if model supports native video (e.g., MiniMax M3)
          if (msg.role == 'user' && msg.attachmentPath != null) {
            if (OpenRouterService.supportsNativeVideo(model)) {
              // Send original video file directly as native video content
              final content = OpenRouterService.buildMultimodalContent(
                model: model,
                text: msg.content.isNotEmpty ? msg.content : 'Attached video',
                attachmentPath: msg.attachmentPath,
                inputType: 'video',
              );
              apiMessages.add({'role': msg.role, 'content': content});
            } else {
              // Extract video frames and send as images for non-native models
              final videoResult = await VideoService.extractFrames(msg.attachmentPath!);
              if (videoResult.hasFrames) {
                final content = OpenRouterService.buildMultimodalContent(
                  model: model,
                  text: msg.content.isNotEmpty
                      ? msg.content
                      : 'Attached video (${videoResult.totalFramesExtracted} frames extracted)',
                  imageBytesList: videoResult.frames,
                );
                apiMessages.add({'role': msg.role, 'content': content});
              } else {
                // Fallback — send as text
                final content = OpenRouterService.buildMultimodalContent(
                  model: model,
                  text: '[Video file: ${msg.attachmentPath!.split('/').last}] ${msg.content}',
                );
                apiMessages.add({'role': msg.role, 'content': content});
              }
            }
          } else {
            apiMessages.add({'role': msg.role, 'content': msg.content});
          }
        } else if (msg.attachmentPath != null && msg.inputType == 'pdf') {
          // Render PDF pages as images and send to vision model.
          // If image rendering fails, extracted text is sent instead.
          if (msg.role == 'user' && msg.attachmentPath != null) {
            final pdfResult = _pdfRenderCache[msg.attachmentPath!] ?? await PdfService.renderPdfAsImages(msg.attachmentPath!);
            if (pdfResult.hasImages) {
              final content = OpenRouterService.buildMultimodalContent(
                text: msg.content.isNotEmpty
                    ? msg.content
                    : 'Attached PDF (${pdfResult.totalPages} pages, showing ${pdfResult.renderedCount})',
                imageBytesList: pdfResult.images,
              );
              apiMessages.add({'role': msg.role, 'content': content});
            } else if (pdfResult.extractedText != null && pdfResult.extractedText!.isNotEmpty) {
              // Fallback — send extracted PDF text content
              final content = OpenRouterService.buildMultimodalContent(
                text: msg.content.isNotEmpty
                    ? '${msg.content}\n\n--- PDF Content (${pdfResult.totalPages} pages) ---\n${pdfResult.extractedText}'
                    : '--- PDF Content (${pdfResult.totalPages} pages, ${pdfResult.extractedText!.length} chars) ---\n${pdfResult.extractedText}',
              );
              apiMessages.add({'role': msg.role, 'content': content});
            } else {
              // Fallback — send as generic text reference
              final content = OpenRouterService.buildMultimodalContent(
                text: '[PDF file: ${msg.attachmentPath!.split('/').last}] ${msg.content}',
              );
              apiMessages.add({'role': msg.role, 'content': content});
            }
          } else {
            apiMessages.add({'role': msg.role, 'content': msg.content});
          }
        } else {
          apiMessages.add({'role': msg.role, 'content': msg.content});
        }
      }

      // Create placeholder assistant message and save to DB immediately
      final assistantId = _uuid.v4();
      _streamingMessageId = assistantId;
      _streamingContent = '';
      _streamingReasoning = null;
      _streamingInputTokens = null;
      _streamingOutputTokens = null;

      // Save to DB so it persists across chat switches
      await _db.insertMessage(MessagesTableCompanion(
        id: Value(assistantId),
        chatId: Value(_currentChatId!),
        role: const Value('assistant'),
        content: const Value(''),
        inputType: const Value('text'),
        status: const Value('sending'),
        createdAt: Value(DateTime.now()),
      ));

      // Add to local list
      _messages.add(MessagesTableData(
        id: assistantId,
        chatId: _currentChatId!,
        role: 'assistant',
        content: '',
        inputType: 'text',
        attachmentPath: null,
        inputTokens: null,
        outputTokens: null,
        reasoning: null,
        status: 'sending',
        createdAt: DateTime.now(),
        editedAt: null,
      ));
      notifyListeners();

      // Start streaming
      _openRouterService.sendChatMessageStream(
        model: model,
        messages: apiMessages,
        maxTokens: maxTokens,
        temperature: temperature,
        includeReasoning: true,
        onToken: (token) {
          if (_streamingFinished) return;
          _streamingContent += token;
          streamingState.content = _streamingContent;
          streamingState.notifyListeners();
          _debounceBuffer += token;
          _debounceAssistantId = assistantId;

          // If no pending flush, schedule one
          if (!_debounceNeedsFlush) {
            _debounceNeedsFlush = true;
            _debounceTimer?.cancel();
            // If buffer gets large before interval, flush immediately
            if (_debounceBuffer.length > 200) {
              _flushDebounce();
            } else {
              _debounceTimer = Timer(_debounceInterval, _flushDebounce);
            }
          }
        },
        onComplete: (response) async {
          _streamingFinished = true;
          // Cancel any pending debounce flushes to prevent race condition
          _debounceTimer?.cancel();
          _debounceNeedsFlush = false;
          streamingState.isStreaming = false;
          streamingState.notifyListeners();
          _streamingContent = response.content ?? '';
          _streamingReasoning = response.reasoning;
          _streamingInputTokens = response.promptTokens;
          _streamingOutputTokens = response.completionTokens;

          // Update the message in DB
          await (_db.update(_db.messagesTable)..where((t) => t.id.equals(assistantId)))
              .write(MessagesTableCompanion(
            content: Value(_streamingContent),
            inputTokens: Value(_streamingInputTokens),
            outputTokens: Value(_streamingOutputTokens),
            reasoning: Value(_streamingReasoning),
            status: const Value('sent'),
          ));

          // Update in-memory message directly to keep content visible
          final msgIdx = _messages.indexWhere((m) => m.id == assistantId);
          if (msgIdx != -1) {
            _messages[msgIdx] = MessagesTableData(
              id: _messages[msgIdx].id,
              chatId: _messages[msgIdx].chatId,
              role: _messages[msgIdx].role,
              content: _streamingContent,
              inputType: _messages[msgIdx].inputType,
              attachmentPath: _messages[msgIdx].attachmentPath,
              inputTokens: _streamingInputTokens,
              outputTokens: _streamingOutputTokens,
              reasoning: _streamingReasoning,
              status: 'sent',
              createdAt: _messages[msgIdx].createdAt,
              editedAt: DateTime.now(),
            );
          }

          // Update chat tokens
          final chat = await _db.getChat(_currentChatId!);
          if (chat != null) {
            await _db.updateChatTokens(
              _currentChatId!,
              chat.totalInputTokens + (_streamingInputTokens ?? 0),
              chat.totalOutputTokens + (_streamingOutputTokens ?? 0),
            );
          }

          // Update chat updatedAt
          if (_currentChatId != null) {
            await (_db.update(_db.chatsTable)..where((t) => t.id.equals(_currentChatId!)))
                .write(ChatsTableCompanion(
              updatedAt: Value(DateTime.now()),
            ));
          }

          // Auto-title logic
          if (chat != null) {
            if (chat.title == 'New Chat') {
              _autoTitleChat(_currentChatId!, text, _streamingContent);
            } else if (chat.title == 'Forked chat') {
              final existingAssistantCount = _messages
                  .where((m) => m.role == 'assistant' && m.id != assistantId)
                  .length;
              if (existingAssistantCount > 0) {
                _autoTitleChat(_currentChatId!, text, _streamingContent);
              }
            }
          }

          // --- Phase 7: Generate embeddings (non-blocking) ---
          // For the user message
          if (memoryEnabled && _currentChatId != null) {
            // Fire-and-forget for user message
            unawaited(_generateAndStoreEmbedding(userMsgId, text));
            // Fire-and-forget for assistant response
            if (_streamingContent.isNotEmpty) {
              unawaited(_generateAndStoreEmbedding(assistantId, _streamingContent));
            }
          }

          // Only clear streaming state AFTER the in-memory update above
          _streamingMessageId = null;
          _streamingChatId = null;
          _streamingContent = '';
          _streamingReasoning = null;
          _streamingInputTokens = null;
          _streamingOutputTokens = null;
          _isSending = false;
          notifyListeners();
        },
        onError: (error) {
          _streamingFinished = true;
          streamingState.isStreaming = false;
          streamingState.notifyListeners();
          // Cancel any pending debounce flushes
          _debounceTimer?.cancel();
          _debounceNeedsFlush = false;
          // Mark as failed in DB
          _db.updateMessageStatus(assistantId, 'failed');
          _failedMessageIds.add(assistantId);

          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(status: 'failed');
          }

          _error = _friendlyError(error);
          _streamingMessageId = null;
          _streamingChatId = null;
          _streamingContent = '';
          _streamingReasoning = null;
          _streamingInputTokens = null;
          _streamingOutputTokens = null;
          _isSending = false;
          notifyListeners();
        },
      );
    } catch (e) {
      // Cancel any pending debounce flushes
      _debounceTimer?.cancel();
      _debounceNeedsFlush = false;
      _error = _friendlyError(e);
      _streamingMessageId = null;
      _streamingChatId = null;
      _streamingContent = '';
      _streamingReasoning = null;
      _streamingInputTokens = null;
      _streamingOutputTokens = null;
      _isSending = false;
      notifyListeners();
    }
  }
}

extension on ChatsTableCompanion {
  ChatsTableData toData() {
    return ChatsTableData(
      id: id.value,
      folderId: folderId.value,
      title: title.value,
      skillId: skillId.value,
      forkedFromMessageId: forkedFromMessageId.value,
      isPinned: isPinned.present ? isPinned.value : false,
      totalInputTokens: totalInputTokens.value,
      totalOutputTokens: totalOutputTokens.value,
      createdAt: createdAt.value,
      updatedAt: updatedAt.value,
    );
  }
}

/// Separate notifier for streaming content — avoids rebuilding non-streaming widgets on every token.
class StreamingState extends ChangeNotifier {
  String content = '';
  bool isStreaming = false;
  String? messageId;
}

/// Internal score holder for memory retrieval.
class _ScoredMessage {
  final String messageId;
  final double score;

  const _ScoredMessage(this.messageId, this.score);
}