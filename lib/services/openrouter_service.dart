import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_ai_chat_app_openrouter/config/constants.dart';
import '../services/auth_service.dart';

/// Represents a single content part in a multimodal message.
class ContentPart {
  final String type;
  final String? text;
  final String? imageUrl;

  const ContentPart({required this.type, this.text, this.imageUrl});
}

class OpenRouterService {
  final AuthService _authService;
  http.Client? _activeClient;

  OpenRouterService(this._authService);

  Future<String?> _getApiKey() async => await _authService.getApiKey();

  Map<String, String> _headers(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://flutter-ai-chat.app',
        'X-Title': AppConstants.appName,
      };

  /// Cancel any currently active request
  void cancelRequest() {
    _activeClient?.close();
    _activeClient = null;
  }

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

  /// Send a chat completion request to OpenRouter (non-streaming).
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

  /// Send a streaming chat completion request to OpenRouter.
  /// Returns a [StreamSubscription] of content tokens as they arrive.
  /// Calls [onToken] with each text chunk.
  /// Calls [onComplete] with the complete response when done.
  /// Calls [onError] on failure.
  StreamSubscription<String>? sendChatMessageStream({
    required String model,
    required List<Map<String, dynamic>> messages,
    required void Function(String token) onToken,
    required void Function(OpenRouterResponse response) onComplete,
    required void Function(String error) onError,
    int? maxTokens,
    double? temperature,
    bool? includeReasoning,
  }) {
    _getApiKey().then((apiKey) async {
      if (apiKey == null || apiKey.isEmpty) {
        onError('API key not set');
        return;
      }

      try {
        _activeClient?.close();
        _activeClient = http.Client();

        final url = Uri.parse('${AppConstants.openRouterBaseUrl}/chat/completions');
        final body = <String, dynamic>{
          'model': model,
          'messages': messages,
          'max_tokens': maxTokens,
          'temperature': temperature,
          'stream': true,
          if (includeReasoning == true) 'include_reasoning': true,
          if (includeReasoning == true) 'reasoning': {'max_tokens': 2048},
        };

        final request = http.Request('POST', url)
          ..headers.addAll(_headers(apiKey))
          ..body = jsonEncode(body);

        final response = await _activeClient!.send(request);

        if (response.statusCode != 200) {
          final errorBody = await response.stream.bytesToString();
          onError('HTTP ${response.statusCode}: $errorBody');
          return;
        }

        final fullContent = StringBuffer();
        String? reasoning;
        int? promptTokens;
        int? completionTokens;
        String? finishReason;

        await for (final chunk in response.stream.transform(utf8.decoder)) {
          // Parse SSE format: "data: {...}\n\n"
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (!line.startsWith('data: ')) continue;
            final jsonStr = line.substring(6).trim();
            if (jsonStr == '[DONE]') break;

            try {
              final data = jsonDecode(jsonStr) as Map<String, dynamic>;
              final choices = data['choices'] as List<dynamic>?;
              if (choices == null || choices.isEmpty) continue;

              final choice = choices[0] as Map<String, dynamic>;
              final delta = choice['delta'] as Map<String, dynamic>?;
              final finish = choice['finish_reason'] as String?;
              if (finish != null) finishReason = finish;

              if (delta == null) continue;

              final content = delta['content'] as String?;
              final reasoningContent = delta['reasoning'] as String?;

              if (content != null && content.isNotEmpty) {
                fullContent.write(content);
                onToken(content);
              }
              if (reasoningContent != null && reasoningContent.isNotEmpty) {
                reasoning = (reasoning ?? '') + reasoningContent;
              }

              // Usage info is in the final chunk
              final usage = data['usage'] as Map<String, dynamic>?;
              if (usage != null) {
                promptTokens = usage['prompt_tokens'] as int?;
                completionTokens = usage['completion_tokens'] as int?;
              }

              // Some models put usage in the final choice
              final choiceUsage = choice['usage'] as Map<String, dynamic>?;
              if (choiceUsage != null) {
                promptTokens ??= choiceUsage['prompt_tokens'] as int?;
                completionTokens ??= choiceUsage['completion_tokens'] as int?;
              }
            } catch (e) {
              // Skip malformed JSON chunks
            }
          }
        }

        onComplete(OpenRouterResponse(
          content: fullContent.toString(),
          reasoning: reasoning,
          promptTokens: promptTokens,
          completionTokens: completionTokens,
        ));
      } catch (e) {
        if (e is SocketException || e is HttpException ||
            e.toString().contains('Client') || e.toString().contains('closed')) {
          // Request was cancelled — not an error
          return;
        }
        onError('Network error: $e');
      }
    });

    return null; // StreamSubscription not needed since we use callbacks
  }

  /// Build a multimodal content array from text and image(s).
  static List<Map<String, dynamic>> buildMultimodalContent({
    required String text,
    String? attachmentPath,
    String? inputType,
    List<Uint8List>? imageBytesList,
  }) {
    final parts = <Map<String, dynamic>>[];

    if (text.isNotEmpty) {
      parts.add({'type': 'text', 'text': text});
    }

    if (imageBytesList != null && imageBytesList.isNotEmpty) {
      for (final bytes in imageBytesList) {
        if (bytes.isEmpty) continue;
        try {
          final base64 = base64Encode(bytes);
          parts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,$base64'},
          });
        } catch (e) {
          // Skip invalid images
        }
      }
    } else if (attachmentPath != null && inputType == 'image') {
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
      } catch (e) {}
    }

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