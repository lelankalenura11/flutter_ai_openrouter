import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/folders_table.dart';
import 'tables/chats_table.dart';
import 'tables/messages_table.dart';
import 'tables/stars_table.dart';
import 'tables/skills_table.dart';
import 'tables/message_embeddings_table.dart';
import 'tables/settings_table.dart';

part 'app_database.g.dart';

// --- DAO-style helper classes ---

/// Convenience methods for folder operations
extension FolderQueries on AppDatabase {
  Future<List<FoldersTableData>> getAllFolders() =>
      select(foldersTable).get();

  Future<FoldersTableData?> getFolder(String id) =>
      (select(foldersTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertFolder(FoldersTableCompanion folder) =>
      into(foldersTable).insert(folder);

  Future<void> updateFolder(FoldersTableCompanion folder) =>
      update(foldersTable).replace(folder);

  Future<void> deleteFolder(String id) =>
      (delete(foldersTable)..where((t) => t.id.equals(id))).go();
}

/// Convenience methods for chat operations
extension ChatQueries on AppDatabase {
  Future<List<ChatsTableData>> getAllChats() =>
      (select(chatsTable)..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();

  Future<ChatsTableData?> getChat(String id) =>
      (select(chatsTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<ChatsTableData>> getChatsByFolder(String? folderId) {
    if (folderId == null) {
      return (select(chatsTable)..where((t) => t.folderId.isNull())).get();
    }
    return (select(chatsTable)..where((t) => t.folderId.equals(folderId)))
        .get();
  }

  Future<void> insertChat(ChatsTableCompanion chat) =>
      into(chatsTable).insert(chat);

  Future<void> updateChat(ChatsTableCompanion chat) =>
      update(chatsTable).replace(chat);

  Future<void> deleteChat(String id) =>
      (delete(chatsTable)..where((t) => t.id.equals(id))).go();

  Future<void> deleteAllChats() async {
    // Delete all messages, stars, embeddings, chats, and folders
    await delete(messagesTable).go();
    await delete(starsTable).go();
    await delete(messageEmbeddingsTable).go();
    await delete(chatsTable).go();
    await delete(foldersTable).go();
  }

  Future<void> moveChatToFolder(String chatId, String? folderId) async {
    await (update(chatsTable)..where((t) => t.id.equals(chatId))).write(
      ChatsTableCompanion(
        folderId: Value(folderId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> renameChat(String chatId, String title) async {
    await (update(chatsTable)..where((t) => t.id.equals(chatId))).write(
      ChatsTableCompanion(
        title: Value(title),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateChatTokens(String chatId, int inputTokens, int outputTokens) async {
    await (update(chatsTable)..where((t) => t.id.equals(chatId))).write(
      ChatsTableCompanion(
        totalInputTokens: Value(inputTokens),
        totalOutputTokens: Value(outputTokens),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

/// Convenience methods for message operations
extension MessageQueries on AppDatabase {
  Future<List<MessagesTableData>> getMessages(String chatId) =>
      (select(messagesTable)
            ..where((t) => t.chatId.equals(chatId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  Future<MessagesTableData?> getMessage(String id) =>
      (select(messagesTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertMessage(MessagesTableCompanion message) =>
      into(messagesTable).insert(message);

  Future<void> updateMessage(MessagesTableCompanion message) =>
      update(messagesTable).replace(message);

  Future<void> deleteMessage(String id) =>
      (delete(messagesTable)..where((t) => t.id.equals(id))).go();

  Future<void> updateMessageStatus(String id, String status) async {
    await (update(messagesTable)..where((t) => t.id.equals(id))).write(
      MessagesTableCompanion(status: Value(status)),
    );
  }

  /// Fork messages from a given point — copy all messages from `fromMessageId` onward into a new chat
  Future<List<MessagesTableData>> forkMessages(
      String fromMessageId, String sourceChatId) async {
    final allMessages = await getMessages(sourceChatId);
    final fromIndex = allMessages.indexWhere((m) => m.id == fromMessageId);
    if (fromIndex == -1) return [];

    final forkedData = allMessages.sublist(fromIndex);
    // Return a deep copy with nulled IDs — the caller assigns new IDs
    return forkedData;
  }
}

/// Convenience methods for star operations
extension StarQueries on AppDatabase {
  Future<List<StarsTableData>> getAllStars() => select(starsTable).get();

  Future<StarsTableData?> getStar(String messageId) =>
      (select(starsTable)..where((t) => t.messageId.equals(messageId)))
          .getSingleOrNull();

  Future<void> toggleStar(String messageId) async {
    final existing = await getStar(messageId);
    if (existing != null) {
      await (delete(starsTable)..where((t) => t.messageId.equals(messageId))).go();
    } else {
      await into(starsTable).insert(StarsTableCompanion(
        messageId: Value(messageId),
        starredAt: Value(DateTime.now()),
      ));
    }
  }

  /// Get starred messages with their full data
  Future<List<MessagesTableData>> getStarredMessages() async {
    final stars = await select(starsTable).get();
    if (stars.isEmpty) return [];

    final query = select(messagesTable)
      ..where((t) => t.id.isIn(stars.map((s) => s.messageId).toList()))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    final messages = await query.get();
    return messages;
  }

  /// Get chat title for a message
  Future<String?> getChatTitleForMessage(String messageId) async {
    final msg = await getMessage(messageId);
    if (msg == null) return null;
    final chat = await getChat(msg.chatId);
    return chat?.title;
  }

  /// Get all stars with message and chat info (for starred screen)
  Future<List<StarredMessageInfo>> getStarredWithChatInfo() async {
    final stars = await getAllStars();
    if (stars.isEmpty) return [];

    // Order by starredAt descending
    stars.sort((a, b) => b.starredAt.compareTo(a.starredAt));

    final result = <StarredMessageInfo>[];
    for (final star in stars) {
      final msg = await getMessage(star.messageId);
      if (msg == null) continue;
      final chat = await getChat(msg.chatId);
      result.add(StarredMessageInfo(
        message: msg,
        chatTitle: chat?.title ?? 'Unknown Chat',
        starredAt: star.starredAt,
      ));
    }
    return result;
  }
}

/// Convenience methods for skill operations
extension SkillQueries on AppDatabase {
  Future<List<SkillsTableData>> getAllSkills() => select(skillsTable).get();

  Future<SkillsTableData?> getSkill(String id) =>
      (select(skillsTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertSkill(SkillsTableCompanion skill) =>
      into(skillsTable).insert(skill);

  Future<void> updateSkill(SkillsTableCompanion skill) =>
      update(skillsTable).replace(skill);

  Future<void> deleteSkill(String id) =>
      (delete(skillsTable)..where((t) => t.id.equals(id))).go();
}

/// Convenience methods for settings operations
extension SettingsQueries on AppDatabase {
  Future<SettingsTableData?> getSettings() =>
      (select(settingsTable)..where((t) => t.id.equals('default')))
          .getSingleOrNull();

  Future<void> updateSettings(SettingsTableCompanion settings) =>
      update(settingsTable).replace(settings);
}

/// Convenience methods for embedding operations
extension EmbeddingQueries on AppDatabase {
  Future<MessageEmbeddingsTableData?> getEmbedding(String messageId) =>
      (select(messageEmbeddingsTable)..where((t) => t.messageId.equals(messageId)))
          .getSingleOrNull();

  Future<void> insertEmbedding(MessageEmbeddingsTableCompanion embedding) =>
      into(messageEmbeddingsTable).insert(embedding);

  Future<void> deleteEmbedding(String messageId) =>
      (delete(messageEmbeddingsTable)..where((t) => t.messageId.equals(messageId))).go();

  /// Get all embeddings for messages in a given chat.
  Future<List<MessageEmbeddingsTableData>> getEmbeddingsForChat(String chatId) async {
    // Fetch all message IDs for the chat
    final messages = await getMessages(chatId);
    if (messages.isEmpty) return [];
    final ids = messages.map((m) => m.id).toList();
    return (select(messageEmbeddingsTable)
          ..where((t) => t.messageId.isIn(ids)))
        .get();
  }

  /// Get all embeddings (for cross-chat search).
  Future<List<MessageEmbeddingsTableData>> getAllEmbeddings() =>
      select(messageEmbeddingsTable).get();
}

/// Value object returned by [StarQueries.getStarredWithChatInfo]
class StarredMessageInfo {
  final MessagesTableData message;
  final String chatTitle;
  final DateTime starredAt;

  const StarredMessageInfo({
    required this.message,
    required this.chatTitle,
    required this.starredAt,
  });
}

// --- Main Database Class ---

@DriftDatabase(
  tables: [
    FoldersTable,
    ChatsTable,
    MessagesTable,
    StarsTable,
    SkillsTable,
    MessageEmbeddingsTable,
    SettingsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();

          // Insert default settings
          await into(settingsTable).insert(SettingsTableCompanion(
            id: const Value('default'),
            openrouterModel: const Value('openai/gpt-4o'),
            maxTokens: const Value(4096),
            temperature: const Value(0.7),
            theme: const Value('system'),
            memoryEnabled: const Value(false),
          ));

          // Insert built-in skills
          final now = DateTime.now();
          final builtInSkills = [
            (
              id: 'builtin_code_expert',
              name: 'Code Expert',
              prompt:
                  'You are an expert software engineer. Provide clear, well-explained code solutions. '
                  'Consider best practices, edge cases, and performance. When relevant, explain your reasoning.',
            ),
            (
              id: 'builtin_summarizer',
              name: 'Summarizer',
              prompt:
                  'You are a skilled summarizer. Condense the given information into a clear, concise summary. '
                  'Focus on key points and avoid unnecessary details. Use bullet points when appropriate.',
            ),
            (
              id: 'builtin_analyst',
              name: 'Analyst',
              prompt:
                  'You are a data and logic analyst. Break down complex topics into their components, '
                  'identify patterns, and provide structured analysis. Support your conclusions with evidence.',
            ),
            (
              id: 'builtin_creative_writer',
              name: 'Creative Writer',
              prompt:
                  'You are a creative writer. Craft engaging, imaginative content with vivid descriptions. '
                  'Adapt your tone and style to match the user\'s request, whether it\'s storytelling, poetry, or creative prose.',
            ),
            (
              id: 'builtin_teacher',
              name: 'Teacher',
              prompt:
                  'You are a patient and knowledgeable teacher. Explain concepts clearly and simply. '
                  'Use analogies, examples, and step-by-step reasoning. Adapt your explanations to the user\'s level of understanding.',
            ),
          ];

          for (final skill in builtInSkills) {
            await into(skillsTable).insert(SkillsTableCompanion(
              id: Value(skill.id),
              name: Value(skill.name),
              systemPrompt: Value(skill.prompt),
              isBuiltin: const Value(true),
              createdAt: Value(now),
            ));
          }
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            // Add status column to messages
            await m.addColumn(messagesTable, messagesTable.status);
          }
          if (from < 3) {
            // Add memoryEnabled column to settings
            await m.addColumn(settingsTable, settingsTable.memoryEnabled);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'chat_app.sqlite'));

    final cachebase = p.join(dbFolder.path, '.cache');
    final cacheDir = Directory(cachebase);
    if (!cacheDir.existsSync()) {
      cacheDir.createSync();
    }

    return NativeDatabase.createInBackground(file);
  });
}