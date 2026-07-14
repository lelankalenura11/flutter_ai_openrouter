import 'package:drift/drift.dart';

class StarsTable extends Table {
  TextColumn get messageId => text()();
  DateTimeColumn get starredAt => dateTime()();

  @override
  Set<Column> get primaryKey => {messageId};

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE',
      ];
}