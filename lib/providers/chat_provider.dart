import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/services/openrouter_service.dart';

class ChatProvider extends ChangeNotifier {
  final AppDatabase _db;
  final OpenRouterService _openRouterService;
  final Uuid _uuid = const Uuid();

  List<ChatsTableData> _chats = [];
  List<MessagesTableData> _messages = [];
  String? _currentChatId;
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  String? _activeSkillId;
  String? _activeSkillPrompt;

  List<ChatsTableData> get chats => _chats;
  List<MessagesTableData> get messages => _messages;
  String? get currentChatId => _currentChatId;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;
  String? get activeSkillId => _activeSkillId;
  String? get activeSkillPrompt => _activeSkillPrompt;

  ChatProvider(this._db, this._openRouterService);

  Future<void> loadChats() async {
    _isLoading = true;
    notifyListeners();

    try {
      _chats = await _db.getAllChats();
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
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
      _error = e.toString();
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
    } catch (e) {
      _error = e.toString();
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
      _error = e.toString();
      notifyListeners();
    }
  }

  void setSkill(String? skillId, String? prompt) {
    _activeSkillId = skillId;
    _activeSkillPrompt = prompt;
    notifyListeners();
  }

  Future<void> toggleStar(String messageId) async {
    await _db.toggleStar(messageId);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (_currentChatId == null || text.isEmpty) return;

    _isSending = true;
    _error = null;
    notifyListeners();

    try {
      // Get settings for model params
      final settings = await _db.getSettings();
      final model = settings?.openrouterModel ?? 'openai/gpt-4o';
      final maxTokens = settings?.maxTokens ?? 4096;
      final temperature = settings?.temperature ?? 0.7;

      // Create user message locally
      final userMsgId = _uuid.v4();
      final now = DateTime.now();
      final userMessage = MessagesTableCompanion(
        id: Value(userMsgId),
        chatId: Value(_currentChatId!),
        role: const Value('user'),
        content: Value(text),
        inputType: const Value('text'),
        createdAt: Value(now),
      );
      await _db.insertMessage(userMessage);

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
        apiMessages.add({
          'role': msg.role,
          'content': msg.content,
        });
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
        _error = response.error;
        _isSending = false;
        notifyListeners();
        return;
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
      final currentId = _currentChatId;
      if (currentId != null) {
        await (_db.update(_db.chatsTable)..where((t) => t.id.equals(currentId)))
            .write(ChatsTableCompanion(
          updatedAt: Value(DateTime.now()),
        ));
      }

      // Reload messages
      _messages = await _db.getMessages(_currentChatId!);
    } catch (e) {
      _error = 'Error: $e';
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