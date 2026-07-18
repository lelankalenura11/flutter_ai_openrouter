import 'package:drift/drift.dart';

class SettingsTable extends Table {
  TextColumn get id => text()(); // single row ID 'default'
  TextColumn get openrouterModel => text()();
  IntColumn get maxTokens => integer()();
  RealColumn get temperature => real()();
  TextColumn get theme => text()();
  BoolColumn get memoryEnabled => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
