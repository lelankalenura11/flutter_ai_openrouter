class Skill {
  final String id;
  final String name;
  final String systemPrompt;
  final bool isBuiltin;
  final DateTime createdAt;

  const Skill({
    required this.id,
    required this.name,
    required this.systemPrompt,
    this.isBuiltin = false,
    required this.createdAt,
  });

  Skill copyWith({
    String? id,
    String? name,
    String? systemPrompt,
    bool? isBuiltin,
    DateTime? createdAt,
  }) {
    return Skill(
      id: id ?? this.id,
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'system_prompt': systemPrompt,
        'is_builtin': isBuiltin,
        'created_at': createdAt.toIso8601String(),
      };

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
        id: json['id'] as String,
        name: json['name'] as String,
        systemPrompt: json['system_prompt'] as String,
        isBuiltin: json['is_builtin'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Predefined built-in skills
class BuiltInSkills {
  static const List<Map<String, String>> skills = [
    {
      'id': 'builtin_code_expert',
      'name': 'Code Expert',
      'system_prompt':
          'You are an expert software engineer. Provide clear, well-explained code solutions. '
          'Consider best practices, edge cases, and performance. When relevant, explain your reasoning.',
    },
    {
      'id': 'builtin_summarizer',
      'name': 'Summarizer',
      'system_prompt':
          'You are a skilled summarizer. Condense the given information into a clear, concise summary. '
          'Focus on key points and avoid unnecessary details. Use bullet points when appropriate.',
    },
    {
      'id': 'builtin_analyst',
      'name': 'Analyst',
      'system_prompt':
          'You are a data and logic analyst. Break down complex topics into their components, '
          'identify patterns, and provide structured analysis. Support your conclusions with evidence.',
    },
    {
      'id': 'builtin_creative_writer',
      'name': 'Creative Writer',
      'system_prompt':
          'You are a creative writer. Craft engaging, imaginative content with vivid descriptions. '
          'Adapt your tone and style to match the user\'s request, whether it\'s storytelling, poetry, or creative prose.',
    },
    {
      'id': 'builtin_teacher',
      'name': 'Teacher',
      'system_prompt':
          'You are a patient and knowledgeable teacher. Explain concepts clearly and simply. '
          'Use analogies, examples, and step-by-step reasoning. Adapt your explanations to the user\'s level of understanding.',
    },
  ];
}