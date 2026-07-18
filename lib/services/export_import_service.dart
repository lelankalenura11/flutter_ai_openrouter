import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';

/// Schema version for forward compatibility.
/// Increment when the manifest format changes.
const int currentSchemaVersion = 1;

/// Maximum manifest file size we'll accept (50 MB).
const int maxManifestSize = 50 * 1024 * 1024;

/// Service for exporting and importing app data as .zip archives.
///
/// Exported .zip structure:
///   manifest.json   — JSON manifest with schemaVersion, exportedAt, data
///   media/          — directory of attachment files (referenced by relative path)
///
/// Embeds are NOT exported (recomputed on import).
/// API key is NEVER included in the export.
class ExportImportService {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  ExportImportService(this._db);

  // ========================================================================
  // Export
  // ========================================================================

  /// Export all app data (except embeddings and API key) to a .zip file.
  ///
  /// Returns the path to the generated .zip file.
  /// The caller is responsible for deleting the temp file after use.
  Future<String> exportData() async {
    // 1. Query all data
    final folders = await _db.getAllFolders();
    final chats = await _db.getAllChats();
    final allMessages = <MessagesTableData>[];
    for (final chat in chats) {
      final msgs = await _db.getMessages(chat.id);
      allMessages.addAll(msgs);
    }
    final stars = await _db.getAllStars();
    final skills = await _db.getAllSkills();
    final settings = await _db.getSettings();

    // 2. Collect attachment files that exist on disk
    final attachmentFiles = <String, File>{};
    for (final msg in allMessages) {
      if (msg.attachmentPath != null && msg.attachmentPath!.isNotEmpty) {
        final file = File(msg.attachmentPath!);
        if (file.existsSync()) {
          // Use a flat UUID-based name to avoid path conflicts
          final ext = p.extension(msg.attachmentPath!);
          final mediaName = '${_uuid.v4()}$ext';
          attachmentFiles[mediaName] = file;
        }
      }
    }

    // 3. Build manifest
    final manifest = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'data': {
        'folders': folders
            .map((f) => {
                  'id': f.id,
                  'name': f.name,
                  'createdAt': f.createdAt.toIso8601String(),
                  'sortOrder': f.sortOrder,
                })
            .toList(),
        'chats': chats
            .map((c) => {
                  'id': c.id,
                  'folderId': c.folderId,
                  'title': c.title,
                  'skillId': c.skillId,
                  'forkedFromMessageId': c.forkedFromMessageId,
                  'totalInputTokens': c.totalInputTokens,
                  'totalOutputTokens': c.totalOutputTokens,
                  'createdAt': c.createdAt.toIso8601String(),
                  'updatedAt': c.updatedAt.toIso8601String(),
                })
            .toList(),
        'messages': allMessages
            .map((m) => {
                  'id': m.id,
                  'chatId': m.chatId,
                  'role': m.role,
                  'content': m.content,
                  'inputType': m.inputType,
                  // Store relative path in media/ if attachment exists
                  'attachmentPath': m.attachmentPath != null &&
                          m.attachmentPath!.isNotEmpty &&
                          attachmentFiles.entries.any(
                              (e) => e.value.path == m.attachmentPath)
                      ? 'media/${attachmentFiles.entries.firstWhere((e) => e.value.path == m.attachmentPath).key}'
                      : m.attachmentPath,
                  'inputTokens': m.inputTokens,
                  'outputTokens': m.outputTokens,
                  'reasoning': m.reasoning,
                  'status': m.status,
                  'createdAt': m.createdAt.toIso8601String(),
                  'editedAt': m.editedAt?.toIso8601String(),
                })
            .toList(),
        'stars': stars
            .map((s) => {
                  'messageId': s.messageId,
                  'starredAt': s.starredAt.toIso8601String(),
                })
            .toList(),
        'skills': skills
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'systemPrompt': s.systemPrompt,
                  'isBuiltin': s.isBuiltin,
                  'createdAt': s.createdAt.toIso8601String(),
                })
            .toList(),
        'settings': settings != null
            ? {
                'openrouterModel': settings.openrouterModel,
                'maxTokens': settings.maxTokens,
                'temperature': settings.temperature,
                'theme': settings.theme,
                // API key is intentionally excluded
              }
            : null,
      },
    };

    // 4. Build zip archive
    final archive = Archive();
    final manifestJson = utf8.encode(jsonEncode(manifest));
    archive.addFile(ArchiveFile('manifest.json', manifestJson.length, manifestJson));

    // Add media files
    for (final entry in attachmentFiles.entries) {
      try {
        final bytes = await entry.value.readAsBytes();
        archive.addFile(ArchiveFile('media/${entry.key}', bytes.length, bytes));
      } catch (e) {
        debugPrint('Failed to add attachment to export: ${entry.key} — $e');
        // Skip files that can't be read
      }
    }

    // 5. Write zip to temp directory
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = p.join(tempDir.path, 'ai_chat_export_$timestamp.zip');

    final outputFile = File(outputPath);
    final encoded = ZipEncoder().encode(archive);
    await outputFile.writeAsBytes(encoded);

    return outputPath;
  }

  // ========================================================================
  // Import
  // ========================================================================

  /// Import data from a .zip export file.
  ///
  /// Returns a summary of what was imported.
  /// Throws on validation failure or parse error.
  Future<ImportResult> importData(String zipPath) async {
    // 1. Read and validate the zip
    final zipFile = File(zipPath);
    if (!zipFile.existsSync()) {
      throw Exception('File not found: $zipPath');
    }

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 2. Read manifest
    final manifestFile = archive.files.firstWhere(
      (f) => f.name == 'manifest.json',
      orElse: () => throw Exception('Missing manifest.json in archive'),
    );

    if (manifestFile.size > maxManifestSize) {
      throw Exception('manifest.json is too large (${manifestFile.size} bytes)');
    }

    final manifestJson = utf8.decode(manifestFile.content);
    final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

    // 3. Validate schema version
    final schemaVersion = manifest['schemaVersion'] as int?;
    if (schemaVersion == null || schemaVersion < 1) {
      throw Exception('Invalid or missing schemaVersion');
    }
    if (schemaVersion > currentSchemaVersion) {
      throw Exception(
        'This export was created with a newer app version (schema v$schemaVersion). '
        'Please update your app to import this file.',
      );
    }

    final data = manifest['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Missing data section in manifest');
    }

    // 4. Build ID mapping (old ID → new UUID)
    // We need this to preserve foreign key relationships
    final folderIdMap = <String, String>{};
    final chatIdMap = <String, String>{};
    final messageIdMap = <String, String>{};
    final skillIdMap = <String, String>{};

    // 5. Prepare app attachments directory
    final appDir = await getApplicationDocumentsDirectory();
    final attachDir = Directory(p.join(appDir.path, 'attachments'));
    if (!attachDir.existsSync()) {
      attachDir.createSync(recursive: true);
    }

    // 6. Import in dependency order

    // 6a. Skills (no dependencies)
    final importedSkills = <Map<String, dynamic>>[];
    final skillsList = data['skills'] as List<dynamic>? ?? [];
    for (final s in skillsList) {
      final oldId = s['id'] as String;
      final newId = _uuid.v4();
      skillIdMap[oldId] = newId;

      final skill = SkillsTableCompanion(
        id: Value(newId),
        name: Value(s['name'] as String),
        systemPrompt: Value(s['systemPrompt'] as String),
        isBuiltin: Value(s['isBuiltin'] as bool),
        createdAt: Value(DateTime.parse(s['createdAt'] as String)),
      );

      // Skip built-in skills that already exist (they're created during DB init)
      final isBuiltin = s['isBuiltin'] as bool;
      if (!isBuiltin) {
        try {
          await _db.insertSkill(skill);
          importedSkills.add({'name': s['name'], 'type': 'custom'});
        } catch (e) {
          debugPrint('Failed to import skill ${s['name']}: $e');
        }
      } else {
        importedSkills.add({'name': s['name'], 'type': 'builtin (skipped)'});
      }
    }

    // 6b. Folders (no dependencies)
    final importedFolders = <Map<String, dynamic>>[];
    final foldersList = data['folders'] as List<dynamic>? ?? [];
    for (final f in foldersList) {
      final oldId = f['id'] as String;
      final newId = _uuid.v4();
      folderIdMap[oldId] = newId;

      final folder = FoldersTableCompanion(
        id: Value(newId),
        name: Value(f['name'] as String),
        createdAt: Value(DateTime.parse(f['createdAt'] as String)),
        sortOrder: Value(f['sortOrder'] as int),
      );

      try {
        await _db.insertFolder(folder);
        importedFolders.add({'name': f['name']});
      } catch (e) {
        debugPrint('Failed to import folder ${f['name']}: $e');
      }
    }

    // 6c. Chats (depends on folders, skills)
    final importedChats = <Map<String, dynamic>>[];
    final chatsList = data['chats'] as List<dynamic>? ?? [];
    for (final c in chatsList) {
      final oldId = c['id'] as String;
      final newId = _uuid.v4();
      chatIdMap[oldId] = newId;

      final oldFolderId = c['folderId'] as String?;
      final newFolderId = oldFolderId != null ? folderIdMap[oldFolderId] : null;

      final oldSkillId = c['skillId'] as String?;
      final newSkillId = oldSkillId != null ? skillIdMap[oldSkillId] : null;

      // Message IDs aren't mapped yet, but the FK is nullable — we set null
      // since forked references would point to old messages anyway

      final chat = ChatsTableCompanion(
        id: Value(newId),
        folderId: Value(newFolderId),
        title: Value(c['title'] as String),
        skillId: Value(newSkillId),
        forkedFromMessageId: Value(null), // Cannot preserve across devices
        totalInputTokens: Value(c['totalInputTokens'] as int),
        totalOutputTokens: Value(c['totalOutputTokens'] as int),
        createdAt: Value(DateTime.parse(c['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(c['updatedAt'] as String)),
      );

      try {
        await _db.insertChat(chat);
        importedChats.add({'title': c['title']});
      } catch (e) {
        debugPrint('Failed to import chat ${c['title']}: $e');
      }
    }

    // 6d. Messages (depends on chats)
    final importedMessages = <Map<String, dynamic>>[];
    final messagesList = data['messages'] as List<dynamic>? ?? [];
    for (final m in messagesList) {
      final oldId = m['id'] as String;
      final newId = _uuid.v4();
      messageIdMap[oldId] = newId;

      final oldChatId = m['chatId'] as String;
      final newChatId = chatIdMap[oldChatId];
      if (newChatId == null) {
        debugPrint('Skipping message with unknown chatId: $oldChatId');
        continue;
      }

      // Handle attachment path: if it's a media/ reference, extract from zip
      String? newAttachmentPath;
      final oldPath = m['attachmentPath'] as String?;
      if (oldPath != null && oldPath.isNotEmpty) {
        if (oldPath.startsWith('media/')) {
          // Extract from archive
          final mediaName = oldPath.substring(6); // remove 'media/' prefix
          final mediaFile = archive.files.firstWhere(
            (f) => f.name == oldPath,
            orElse: () => ArchiveFile(oldPath, 0, Uint8List(0)),
          );
          if (mediaFile.size > 0 && mediaFile.content.isNotEmpty) {
            final destPath = p.join(attachDir.path, mediaName);
            try {
              await File(destPath).writeAsBytes(mediaFile.content);
              newAttachmentPath = destPath;
            } catch (e) {
              debugPrint('Failed to extract media file $mediaName: $e');
            }
          }
        } else {
          // Absolute path from same-device export — may not exist on this device
          // Keep it as-is; the user can re-attach if needed
          newAttachmentPath = oldPath;
        }
      }

      final editedAtStr = m['editedAt'] as String?;

      final message = MessagesTableCompanion(
        id: Value(newId),
        chatId: Value(newChatId),
        role: Value(m['role'] as String),
        content: Value(m['content'] as String),
        inputType: Value(m['inputType'] as String),
        attachmentPath: Value(newAttachmentPath),
        inputTokens: Value(m['inputTokens'] as int?),
        outputTokens: Value(m['outputTokens'] as int?),
        reasoning: Value(m['reasoning'] as String?),
        status: const Value('sent'), // Reset status on import
        createdAt: Value(DateTime.parse(m['createdAt'] as String)),
        editedAt: Value(editedAtStr != null ? DateTime.parse(editedAtStr) : null),
      );

      try {
        await _db.insertMessage(message);
        importedMessages.add({
          'role': m['role'],
          'contentPreview':
              (m['content'] as String).substring(0, ((m['content'] as String).length).clamp(0, 50)),
        });
      } catch (e) {
        debugPrint('Failed to import message ${m['id']}: $e');
      }
    }

    // 6e. Stars (depends on messages)
    final importedStars = <Map<String, dynamic>>[];
    final starsList = data['stars'] as List<dynamic>? ?? [];
    for (final s in starsList) {
      final oldMessageId = s['messageId'] as String;
      final newMessageId = messageIdMap[oldMessageId];
      if (newMessageId == null) continue;

      try {
        await _db.into(_db.starsTable).insert(StarsTableCompanion(
          messageId: Value(newMessageId),
          starredAt: Value(DateTime.parse(s['starredAt'] as String)),
        ));
        importedStars.add({'messageId': newMessageId});
      } catch (e) {
        debugPrint('Failed to import star for message $oldMessageId: $e');
      }
    }

    // 6f. Settings (no dependencies)
    final settingsData = data['settings'] as Map<String, dynamic>?;
    if (settingsData != null) {
      try {
        await _db.updateSettings(SettingsTableCompanion(
          id: const Value('default'),
          openrouterModel: Value(settingsData['openrouterModel'] as String? ?? 'openai/gpt-4o'),
          maxTokens: Value(settingsData['maxTokens'] as int? ?? 4096),
          temperature: Value((settingsData['temperature'] as num?)?.toDouble() ?? 0.7),
          theme: Value(settingsData['theme'] as String? ?? 'system'),
        ));
      } catch (e) {
        debugPrint('Failed to import settings: $e');
      }
    }

    // 7. Embeddings are NOT imported — they are regenerated lazily.
    //    When the user next sends a message with memory enabled, any messages
    //    missing embeddings will be processed on-demand via the chat provider.

    return ImportResult(
      folders: importedFolders.length,
      chats: importedChats.length,
      messages: importedMessages.length,
      stars: importedStars.length,
      skills: importedSkills.length,
      settingsImported: settingsData != null,
      mediaFilesExtracted: archive.files.where((f) => f.name.startsWith('media/')).length,
    );
  }
}

/// Result summary returned after importing data.
class ImportResult {
  final int folders;
  final int chats;
  final int messages;
  final int stars;
  final int skills;
  final bool settingsImported;
  final int mediaFilesExtracted;

  const ImportResult({
    required this.folders,
    required this.chats,
    required this.messages,
    required this.stars,
    required this.skills,
    required this.settingsImported,
    required this.mediaFilesExtracted,
  });

  int get totalItems => folders + chats + messages + stars + skills;
}