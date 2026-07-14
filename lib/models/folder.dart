class Folder {
  final String id;
  final String name;
  final DateTime createdAt;
  final int sortOrder;

  const Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sortOrder = 0,
  });

  Folder copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    int? sortOrder,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'sort_order': sortOrder,
      };

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}