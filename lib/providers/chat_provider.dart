import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/services/openrouter_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/file_compression_service.dart';
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
  // Fallback — show a generic message, never raw errors
  return 'Something went wrong. Please try again.';
}

class ChatProvider extends ChangeNotifier {
  final AppDatabase _db;
  final OpenRouterService _openRouterService;
  final Uuid _uuid = const Uuid();

  // Chats
  List<ChatsTableData> _chats = [];
  List<MessagesTableData> _messages = [];
  String? _currentChatId;
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  String? _activeSkillId;
  String? _activeSkillPrompt;

  // Folders
  List<FoldersTableData> _folders = [];

  // Stars — set of starred message IDs for quick lookup
  Set<String> _starredMessageIds = {};

  // Starred messages list
  List<MessagesTableData> _starredMessages = [];

  // Starred messages with chat info (for starred screen)
  List<StarredMessageInfo> _starredWithChatInfo = [];

  // Failed message IDs that can be retried
  Set<String> _failedMessageIds = {};

  // Pending attachment (set by chat_screen before sending)
  FileAttachment? _pendingAttachment;

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

  ChatProvider(this._db, this._openRouterService);

  ChatsTableData? get currentChat {
    if (_currentChatId == null) return null;
    return _chats.where((c) => c.id == _currentChatId).firstOrNull;
  }

  /// Set a pending attachment that will be sent with the next message.
  void setPendingAttachment(FileAttachment? attachment) {
    _pendingAttachment = attachment;
    notifyListeners();
  }

  /// Clear the pending attachment without sending.
  void clearPendingAttachment() {
    _pendingAttachment = null;
    notifyListeners();
  }

  /// Copies the attachment file to app-local storage for persistence.
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
    _isLoading = true;
    notifyListeners();

    try {
      _messages = await _db.getMessages(id);
      _failedMessageIds = _messages
          .where((m) => m.status == 'failed')
          .map((m) => m.id)
          .toSet();
    } catch (e) {
      _error = _friendlyError(e);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> deleteChat(String id) async {
    try {
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
      // Reload chats to get updated data
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
      // Refresh chats list in case any were in this folder
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

      // Create the new chat
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

      // Copy messages with new IDs
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

      // Reload chats and switch to the new one
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

      // Use a cheap/fast model for title generation
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
        model: 'openai/gpt-4o-mini', // Cheap model for title gen
        messages: messages,
        maxTokens: 30,
        temperature: 0.3,
      );

      if (!response.isError && response.content != null && response.content!.trim().isNotEmpty) {
        var title = response.content!.trim();
        // Remove any quotes the model might add
        title = title.replaceAll(RegExp(r'''^["']|["']$'''), '');
        // Cap at 60 chars
        if (title.length > 60) title = title.substring(0, 57) + '...';
        await _db.renameChat(chatId, title);

        _chats = await _db.getAllChats();
        notifyListeners();
      }
    } catch (_) {
      // Silently ignore title generation failures — it's not critical
    }
  }

  // ========================================================================
  // Send message with friendly errors, retry & attachment support
  // ========================================================================

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Resend a failed message by its ID
  Future<void> retryMessage(String messageId) async {
    final msg = _messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null || msg.role != 'user') return;
    await sendMessage(msg.content, messageIdToReplace: messageId);
  }

  /// Send a message, optionally with a file attachment.
  ///
  /// If [messageIdToReplace] is provided, it updates that message's content
  /// instead of creating a new one (used for retry).
  Future<void> sendMessage(
    String text, {
    String? messageIdToReplace,
    FileAttachment? attachment,
  }) async {
    if (_currentChatId == null && text.isEmpty && attachment == null) return;

    // Use pending attachment if none provided directly
    final effectiveAttachment = attachment ?? _pendingAttachment;

    _isSending = true;
    _error = null;
    notifyListeners();

    try {
      // Ensure a chat exists if we're sending a first message
      if (_currentChatId == null) {
        final id = await createChat(skillId: _activeSkillId);
        if (id == null) {
          _error = 'Failed to create chat';
          _isSending = false;
          notifyListeners();
          return;
        }
      }

      // Get settings for model params
      final settings = await _db.getSettings();
      final model = settings?.openrouterModel ?? 'openai/gpt-4o';
      final maxTokens = settings?.maxTokens ?? 4096;
      final temperature = settings?.temperature ?? 0.7;

      final now = DateTime.now();
      String userMsgId;

      // Store attachment locally if present
      String? storedAttachmentPath;
      String inputType = 'text';
      if (effectiveAttachment != null) {
        storedAttachmentPath = await _storeAttachmentLocally(
          effectiveAttachment.path,
          effectiveAttachment.inputType,
        );
        inputType = effectiveAttachment.inputType;
      }

      if (messageIdToReplace != null) {
        // Retry: update the existing failed message status to 'sending'
        userMsgId = messageIdToReplace;
        await _db.updateMessageStatus(userMsgId, 'sending');
        // Reload messages to reflect status change
        if (_currentChatId != null) {
          _messages = await _db.getMessages(_currentChatId!);
        }
        _failedMessageIds.remove(userMsgId);
        notifyListeners();
      } else {
        // Create user message locally
        userMsgId = _uuid.v4();
        final userMessage = MessagesTableCompanion(
          id: Value(userMsgId),
          chatId: Value(_currentChatId!),
          role: const Value('user'),
          content: Value(text),
          inputType: Value(inputType),
          attachmentPath: Value(storedAttachmentPath),
          status: const Value('sending'),
          createdAt: Value(now),
        );
        await _db.insertMessage(userMessage);

        // Insert into local list immediately
        _messages.add(MessagesTableData(
          id: userMsgId,
          chatId: _currentChatId!,
          role: 'user',
          content: text,
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

      // Clear pending attachment after using it
      if (_pendingAttachment != null) {
        _pendingAttachment = null;
        notifyListeners();
      }

      // Reload messages to show user message
      _messages = await _db.getMessages(_currentChatId!);
      notifyListeners();

      // Build message list for API
      final apiMessages = <Map<String, dynamic>>[];

      if (_activeSkillPrompt != null && _activeSkillPrompt!.isNotEmpty) {
        apiMessages.add({
          'role': 'system',
          'content': _activeSkillPrompt,
        });
      }

      for (final msg in _messages) {
        if (msg.status == 'failed') continue; // Don't include failed messages

        // For messages with image attachments, use multimodal content format
        if (msg.attachmentPath != null && (msg.inputType == 'image' || msg.inputType == 'video')) {
          final content = OpenRouterService.buildMultimodalContent(
            text: msg.content,
            attachmentPath: msg.attachmentPath,
            inputType: msg.inputType,
          );
          apiMessages.add({
            'role': msg.role,
            'content': content,
          });
        } else if (msg.attachmentPath != null && msg.inputType == 'pdf') {
          // For PDFs, send a text note about the attached file
          final content = OpenRouterService.buildMultimodalContent(
            text: '${msg.content}\n\n[Attached PDF file available locally: ${msg.attachmentPath}]',
            attachmentPath: null,
          );
          apiMessages.add({
            'role': msg.role,
            'content': content,
          });
        } else {
          // Plain text message
          apiMessages.add({
            'role': msg.role,
            'content': msg.content,
          });
        }
      }

      // Call OpenRouter
      final response = await _openRouterService.sendChatMessage(
        model: model,
        messages: apiMessages,
        maxTokens: maxTokens,
        temperature: temperature,
        includeReasoning: true,
      );

      if (response.isError) {
        // Mark the user message as failed
        await _db.updateMessageStatus(userMsgId, 'failed');
        _failedMessageIds.add(userMsgId);
        final msgIndex = _messages.indexWhere((m) => m.id == userMsgId);
        if (msgIndex != -1) {
          _messages[msgIndex] = _messages[msgIndex].copyWith(status: 'failed');
        }
        _error = _friendlyError(response.error);
        _isSending = false;
        notifyListeners();
        return;
      }

      // Mark user message as sent
      await _db.updateMessageStatus(userMsgId, 'sent');
      final msgIndex = _messages.indexWhere((m) => m.id == userMsgId);
      if (msgIndex != -1) {
        _messages[msgIndex] = _messages[msgIndex].copyWith(status: 'sent');
      }

      // Save assistant message
      final assistantId = _uuid.v4();
      final assistantMessage = MessagesTableCompanion(
        id: Value(assistantId),
        chatId: Value(_currentChatId!),
        role: const Value('assistant'),
        content: Value(response.content ?? ''),
        inputType: const Value('text'),
        inputTokens: Value(response.promptTokens),
        outputTokens: Value(response.completionTokens),
        reasoning: Value(response.reasoning),
        status: const Value('sent'),
        createdAt: Value(DateTime.now()),
      );
      await _db.insertMessage(assistantMessage);

      // Update chat tokens
      final chat = await _db.getChat(_currentChatId!);
      if (chat != null) {
        await _db.updateChatTokens(
          _currentChatId!,
          chat.totalInputTokens + (response.promptTokens ?? 0),
          chat.totalOutputTokens + (response.completionTokens ?? 0),
        );
      }

      // Update chat's updatedAt
      if (_currentChatId != null) {
        await (_db.update(_db.chatsTable)..where((t) => t.id.equals(_currentChatId!)))
            .write(ChatsTableCompanion(
          updatedAt: Value(DateTime.now()),
        ));
      }

      // Reload messages
      _messages = await _db.getMessages(_currentChatId!);

      // Auto-title logic
      if (chat != null) {
        if (chat.title == 'New Chat') {
          // First response in a brand new chat → auto-title immediately
          _autoTitleChat(_currentChatId!, text, response.content ?? '');
        } else if (chat.title == 'Forked chat') {
          // For forked chats, only auto-title on the SECOND response
          final existingAssistantCount = _messages
              .where((m) => m.role == 'assistant' && m.id != assistantId)
              .length;
          if (existingAssistantCount > 0) {
            _autoTitleChat(_currentChatId!, text, response.content ?? '');
          }
        }
      }
    } catch (e) {
      _error = _friendlyError(e);
    }

    _isSending = false;
    notifyListeners();
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
      totalInputTokens: totalInputTokens.value,
      totalOutputTokens: totalOutputTokens.value,
      createdAt: createdAt.value,
      updatedAt: updatedAt.value,
    );
  }
}