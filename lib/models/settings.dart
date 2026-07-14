class AppSettings {
  final String openrouterModel;
  final int maxTokens;
  final double temperature;
  final String theme; // 'light', 'dark', 'system'

  const AppSettings({
    this.openrouterModel = 'openai/gpt-4o',
    this.maxTokens = 4096,
    this.temperature = 0.7,
    this.theme = 'system',
  });

  AppSettings copyWith({
    String? openrouterModel,
    int? maxTokens,
    double? temperature,
    String? theme,
  }) {
    return AppSettings(
      openrouterModel: openrouterModel ?? this.openrouterModel,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      theme: theme ?? this.theme,
    );
  }

  Map<String, dynamic> toJson() => {
        'openrouter_model': openrouterModel,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'theme': theme,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        openrouterModel: json['openrouter_model'] as String? ?? 'openai/gpt-4o',
        maxTokens: json['max_tokens'] as int? ?? 4096,
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
        theme: json['theme'] as String? ?? 'system',
      );
}