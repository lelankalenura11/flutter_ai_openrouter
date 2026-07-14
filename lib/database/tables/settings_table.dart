import 'package:drift/drift.dart';

class SettingsTable extends Table {
  TextColumn get id => text()(); // single row ID 'default'
  TextColumn get openrouterModel => text()();
  IntColumn get maxTokens => integer()();
  RealColumn get temperature => real()();
  TextColumn get theme => text()();

  @override
  Set<Column> get primaryKey => {id};
}