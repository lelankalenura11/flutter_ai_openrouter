import 'package:drift/drift.dart';

class MessageEmbeddingsTable extends Table {
  TextColumn get messageId => text()();
  TextColumn get vector => text()(); // stored as comma-separated float strings
  TextColumn get model => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {messageId};

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE',
      ];
}