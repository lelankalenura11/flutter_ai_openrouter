import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/services/openrouter_service.dart';

class ChatService {
  final AppDatabase _db;
  final OpenRouterService _openRouterService;
  final Uuid _uuid = const Uuid();

  ChatService(this._db, this._openRouterService);

  /// Create a new chat
  Future<String> createChat({
    String? folderId,
    String? skillId,
    String? title,
    String? forkedFromMessageId,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final chat = ChatsTableCompanion(
      id: Value(id),
      folderId: Value(folderId),
      title: Value(title ?? 'New Chat'),
      skillId: Value(skillId),
      forkedFromMessageId: Value(forkedFromMessageId),
      totalInputTokens: const Value(0),
      totalOutputTokens: const Value(0),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    await _db.insertChat(chat);
    return id;
  }

  /// Delete a chat
  Future<void> deleteChat(String id) => _db.deleteChat(id);

  /// Get all chats
  Future<List<ChatsTableData>> getAllChats() => _db.getAllChats();

  /// Get messages for a chat
  Future<List<MessagesTableData>> getMessages(String chatId) =>
      _db.getMessages(chatId);

  /// Send a text message and get the response
  Future<MessagesTableData?> sendMessage({
    required String chatId,
    required String text,
    required String model,
    int? maxTokens,
    double? temperature,
    String? systemPrompt,
  }) async {
    final now = DateTime.now();
    final userMessageId = _uuid.v4();

    // Save user message
    final userMessage = MessagesTableCompanion(
      id: Value(userMessageId),
      chatId: Value(chatId),
      role: const Value('user'),
      content: Value(text),
      inputType: const Value('text'),
      createdAt: Value(now),
    );
    await _db.insertMessage(userMessage);

    // Build message list for API
    final messages = <Map<String, dynamic>>[];

    // Get existing messages for context
    final existingMessages = await _db.getMessages(chatId);

    // Build context from existing messages (last ~20 to stay within token limits)
    final contextMessages = existingMessages.takeLast(20).toList();
    for (final msg in contextMessages) {
      messages.add({
        'role': msg.role,
        'content': msg.content,
      });
    }

    // If we have a system prompt, prepend it
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.insert(0, {
        'role': 'system',
        'content': systemPrompt,
      });
    }

    // Call OpenRouter
    final response = await _openRouterService.sendChatMessage(
      model: model,
      messages: messages,
      maxTokens: maxTokens,
      temperature: temperature,
      includeReasoning: true,
    );

    if (response.isError) {
      return null;
    }

    // Save assistant message
    final assistantMessageId = _uuid.v4();
    final assistantMessage = MessagesTableCompanion(
      id: Value(assistantMessageId),
      chatId: Value(chatId),
      role: const Value('assistant'),
      content: Value(response.content ?? ''),
      inputType: const Value('text'),
      inputTokens: Value(response.promptTokens),
      outputTokens: Value(response.completionTokens),
      reasoning: Value(response.reasoning),
      createdAt: Value(DateTime.now()),
    );
    await _db.insertMessage(assistantMessage);

    // Update chat token totals
    if (response.promptTokens != null || response.completionTokens != null) {
      final chat = await _db.getChat(chatId);
      if (chat != null) {
        await _db.updateChatTokens(
          chatId,
          (chat.totalInputTokens) + (response.promptTokens ?? 0),
          (chat.totalOutputTokens) + (response.completionTokens ?? 0),
        );
      } else {
        await _db.updateChatTokens(
          chatId,
          response.promptTokens ?? 0,
          response.completionTokens ?? 0,
        );
      }
    }

    // Update chat's updatedAt
    await (_db.update(_db.chatsTable)..where((t) => t.id.equals(chatId))).write(
      ChatsTableCompanion(
        updatedAt: Value(DateTime.now()),
      ),
    );

    return await _db.getMessage(assistantMessageId);
  }
}

extension on List<MessagesTableData> {
  List<T> takeLast<T>(int n) {
    if (length <= n) return this as List<T>;
    return sublist(length - n) as List<T>;
  }
}