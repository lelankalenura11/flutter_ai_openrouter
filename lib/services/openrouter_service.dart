import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_ai_chat_app_openrouter/config/constants.dart';
import '../services/auth_service.dart';

class OpenRouterService {
  final AuthService _authService;

  OpenRouterService(this._authService);

  Future<String?> _getApiKey() async => await _authService.getApiKey();

  Map<String, String> _headers(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://flutter-ai-chat.app',
        'X-Title': AppConstants.appName,
      };

  /// Test the connection by hitting a lightweight endpoint
  Future<bool> testConnection({required String apiKey, String? model}) async {
    try {
      final url = Uri.parse('${AppConstants.openRouterBaseUrl}/models');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Send a chat completion request to OpenRouter
  Future<OpenRouterResponse> sendChatMessage({
    required String model,
    required List<Map<String, dynamic>> messages,
    int? maxTokens,
    double? temperature,
    bool? includeReasoning,
  }) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return OpenRouterResponse.error('API key not set');
    }

    try {
      final url = Uri.parse('${AppConstants.openRouterBaseUrl}/chat/completions');
      final body = <String, dynamic>{
        'model': model,
        'messages': messages,
        'max_tokens': ?maxTokens,
        'temperature': ?temperature,
        if (includeReasoning == true) 'include_reasoning': true,
        if (includeReasoning == true) 'reasoning': {'max_tokens': 2048},
      };

      final response = await http.post(
        url,
        headers: _headers(apiKey),
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return OpenRouterResponse.fromJson(data);
      } else {
        final errorBody = response.body;
        return OpenRouterResponse.error(
          'HTTP ${response.statusCode}: $errorBody',
        );
      }
    } catch (e) {
      return OpenRouterResponse.error('Network error: $e');
    }
  }
}

class OpenRouterResponse {
  final String? content;
  final String? reasoning;
  final int? promptTokens;
  final int? completionTokens;
  final String? error;

  const OpenRouterResponse({
    this.content,
    this.reasoning,
    this.promptTokens,
    this.completionTokens,
    this.error,
  });

  factory OpenRouterResponse.fromJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>?;
    final usage = json['usage'] as Map<String, dynamic>?;

    String? content;
    String? reasoning;
    if (choices != null && choices.isNotEmpty) {
      final choice = choices[0] as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>?;
      content = message?['content'] as String?;
      reasoning = message?['reasoning'] as String?;
    }

    return OpenRouterResponse(
      content: content,
      reasoning: reasoning,
      promptTokens: usage?['prompt_tokens'] as int?,
      completionTokens: usage?['completion_tokens'] as int?,
    );
  }

  factory OpenRouterResponse.error(String error) =>
      OpenRouterResponse(error: error);

  bool get isError => error != null;
}