import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_ai_chat_app_openrouter/config/constants.dart';
import '../services/auth_service.dart';

/// Represents a single content part in a multimodal message.
class ContentPart {
  final String type; // 'text' or 'image_url'
  final String? text;
  final String? imageUrl; // base64 data URL or URL

  const ContentPart({required this.type, this.text, this.imageUrl});
}

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

  /// Send a chat completion request to OpenRouter.
  ///
  /// [messages] should follow the standard OpenRouter format.
  /// For multimodal messages, the content field can be a String (plain text)
  /// or a List<Map> of content parts (text + image_url).
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
        'max_tokens': maxTokens,
        'temperature': temperature,
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

  /// Build a multimodal content array from text and an optional attachment.
  ///
  /// For images, encodes the file as a base64 data URL.
  /// For other file types, returns the text only (file types are sent as text
  /// context; actual file upload is not supported by OpenRouter chat completions).
  static List<Map<String, dynamic>> buildMultimodalContent({
    required String text,
    String? attachmentPath,
    String? inputType,
  }) {
    final parts = <Map<String, dynamic>>[];

    // Add text part
    if (text.isNotEmpty) {
      parts.add({'type': 'text', 'text': text});
    }

    // Add image part if present
    if (attachmentPath != null && inputType == 'image') {
      try {
        final file = File(attachmentPath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          final base64 = base64Encode(bytes);
          final ext = attachmentPath.toLowerCase();
          String mimeType = 'image/jpeg';
          if (ext.endsWith('.png')) mimeType = 'image/png';
          if (ext.endsWith('.gif')) mimeType = 'image/gif';
          if (ext.endsWith('.webp')) mimeType = 'image/webp';

          parts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$base64'},
          });
        }
      } catch (e) {
        // If file can't be read, just send text
      }
    }

    // If no parts were added (shouldn't happen), return a text fallback
    if (parts.isEmpty) {
      parts.add({'type': 'text', 'text': text});
    }

    return parts;
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