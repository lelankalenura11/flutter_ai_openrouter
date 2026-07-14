enum MessageRole { user, assistant, system }

enum InputType { text, image, video, audio, pdf }

class Message {
  final String id;
  final String chatId;
  final MessageRole role;
  final String content;
  final InputType inputType;
  final String? attachmentPath;
  final int? inputTokens;
  final int? outputTokens;
  final String? reasoning;
  final DateTime createdAt;
  final DateTime? editedAt;

  const Message({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.inputType = InputType.text,
    this.attachmentPath,
    this.inputTokens,
    this.outputTokens,
    this.reasoning,
    required this.createdAt,
    this.editedAt,
  });

  Message copyWith({
    String? id,
    String? chatId,
    MessageRole? role,
    String? content,
    InputType? inputType,
    String? attachmentPath,
    int? inputTokens,
    int? outputTokens,
    String? reasoning,
    DateTime? createdAt,
    DateTime? editedAt,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      role: role ?? this.role,
      content: content ?? this.content,
      inputType: inputType ?? this.inputType,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      reasoning: reasoning ?? this.reasoning,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'chat_id': chatId,
        'role': role.name,
        'content': content,
        'input_type': inputType.name,
        'attachment_path': attachmentPath,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'reasoning': reasoning,
        'created_at': createdAt.toIso8601String(),
        'edited_at': editedAt?.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        chatId: json['chat_id'] as String,
        role: MessageRole.values.firstWhere((e) => e.name == json['role']),
        content: json['content'] as String,
        inputType: InputType.values.firstWhere(
            (e) => e.name == (json['input_type'] ?? 'text')),
        attachmentPath: json['attachment_path'] as String?,
        inputTokens: json['input_tokens'] as int?,
        outputTokens: json['output_tokens'] as int?,
        reasoning: json['reasoning'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        editedAt: json['edited_at'] != null
            ? DateTime.parse(json['edited_at'] as String)
            : null,
      );
}