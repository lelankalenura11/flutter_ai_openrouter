import 'package:drift/drift.dart';

class FoldersTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}