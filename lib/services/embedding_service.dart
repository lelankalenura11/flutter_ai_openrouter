import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_ai_chat_app_openrouter/config/constants.dart';
import 'package:flutter_ai_chat_app_openrouter/services/auth_service.dart';

/// Service for generating text embeddings via OpenRouter's embeddings API
/// and computing cosine similarity locally.
class EmbeddingService {
  final AuthService _authService;

  EmbeddingService(this._authService);

  Future<String?> _getApiKey() async => await _authService.getApiKey();

  /// Generate an embedding vector for the given [text].
  ///
  /// Uses OpenRouter's `/api/v1/embeddings` endpoint with
  /// `openai/text-embedding-3-small` model (1536 dimensions).
  ///
  /// Returns `null` on failure (network error, API error) — embedding
  /// generation is best-effort and must never block the UI.
  Future<List<double>?> generateEmbedding(String text) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    try {
      final url = Uri.parse('${AppConstants.openRouterBaseUrl}/embeddings');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'openai/text-embedding-3-small',
          'input': text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final dataList = data['data'] as List<dynamic>?;
        if (dataList != null && dataList.isNotEmpty) {
          final embedding = dataList[0]['embedding'] as List<dynamic>;
          return embedding.cast<double>().toList();
        }
      } else {
        debugPrint('Embedding error (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('Embedding network error: $e');
    }
    return null;
  }

  /// Generate embeddings for multiple [texts] in a single API call.
  ///
  /// Returns a list of vectors in the same order as [texts].
  /// Any text that fails to embed will have a `null` entry.
  Future<List<List<double>?>> generateEmbeddingBatch(List<String> texts) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return texts.map((_) => null).toList();
    }

    try {
      final url = Uri.parse('${AppConstants.openRouterBaseUrl}/embeddings');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'openai/text-embedding-3-small',
          'input': texts,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final dataList = data['data'] as List<dynamic>?;
        if (dataList != null) {
          // Sort by index to match input order
          dataList.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
          return dataList
              .map((e) => (e['embedding'] as List<dynamic>).cast<double>().toList())
              .toList();
        }
      } else {
        debugPrint('Batch embedding error (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('Batch embedding network error: $e');
    }
    return texts.map((_) => null).toList();
  }
}

/// Compute cosine similarity between two vectors.
///
/// Returns a value in [-1, 1] where 1 = identical direction, 0 = orthogonal,
/// -1 = opposite direction. For text embeddings, values typically range 0.3–0.9.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;

  double dotProduct = 0.0;
  double normA = 0.0;
  double normB = 0.0;

  for (int i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  final denom = sqrt(normA) * sqrt(normB);
  if (denom == 0) return 0.0;
  return dotProduct / denom;
}

/// Result of a similarity search.
class ScoredMessage {
  final String messageId;
  final double score;

  const ScoredMessage({required this.messageId, required this.score});
}