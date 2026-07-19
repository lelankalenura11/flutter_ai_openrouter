import 'package:drift/drift.dart';

class ChatsTable extends Table {
  TextColumn get id => text()();
  TextColumn get folderId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get skillId => text().nullable()();
  TextColumn get forkedFromMessageId => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  IntColumn get totalInputTokens => integer()();
  IntColumn get totalOutputTokens => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL',
        'FOREIGN KEY (skill_id) REFERENCES skills(id) ON DELETE SET NULL',
      ];
}
