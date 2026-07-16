import 'package:drift/drift.dart';

class MessagesTable extends Table {
  TextColumn get id => text()();
  TextColumn get chatId => text()();
  TextColumn get role => text()(); // 'user', 'assistant', 'system'
  TextColumn get content => text()();
  TextColumn get inputType => text()(); // 'text', 'image', 'video', 'audio', 'pdf'
  TextColumn get attachmentPath => text().nullable()();
  IntColumn get inputTokens => integer().nullable()();
  IntColumn get outputTokens => integer().nullable()();
  TextColumn get reasoning => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('sent'))(); // 'sending', 'sent', 'failed'
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get editedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE',
      ];
}