class Chat {
  final String id;
  final String? folderId;
  final String title;
  final String? skillId;
  final String? forkedFromMessageId;
  final int totalInputTokens;
  final int totalOutputTokens;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Chat({
    required this.id,
    this.folderId,
    required this.title,
    this.skillId,
    this.forkedFromMessageId,
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Chat copyWith({
    String? id,
    String? folderId,
    String? title,
    String? skillId,
    String? forkedFromMessageId,
    int? totalInputTokens,
    int? totalOutputTokens,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Chat(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      skillId: skillId ?? this.skillId,
      forkedFromMessageId: forkedFromMessageId ?? this.forkedFromMessageId,
      totalInputTokens: totalInputTokens ?? this.totalInputTokens,
      totalOutputTokens: totalOutputTokens ?? this.totalOutputTokens,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'folder_id': folderId,
        'title': title,
        'skill_id': skillId,
        'forked_from_message_id': forkedFromMessageId,
        'total_input_tokens': totalInputTokens,
        'total_output_tokens': totalOutputTokens,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Chat.fromJson(Map<String, dynamic> json) => Chat(
        id: json['id'] as String,
        folderId: json['folder_id'] as String?,
        title: json['title'] as String,
        skillId: json['skill_id'] as String?,
        forkedFromMessageId: json['forked_from_message_id'] as String?,
        totalInputTokens: json['total_input_tokens'] as int? ?? 0,
        totalOutputTokens: json['total_output_tokens'] as int? ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}