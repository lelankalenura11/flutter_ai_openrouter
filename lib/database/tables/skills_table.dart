import 'package:drift/drift.dart';

class SkillsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get systemPrompt => text()();
  BoolColumn get isBuiltin => boolean()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}