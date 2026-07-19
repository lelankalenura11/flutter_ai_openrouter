import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

class WebSearchService {
  /// Searches DuckDuckGo for the given query and returns formatted context
  /// that can be injected into an AI prompt.
  /// Runs the HTTP fetch + HTML parsing on a background isolate via compute().
  static Future<String> searchAndFormat(String query) async {
    return compute(_searchAndParse, query);
  }
}

/// Top-level function for Isolate execution. Handles the full search + parse.
/// compute() supports async functions — it will await the returned Future.
Future<String> _searchAndParse(String query) async {
  try {
    final response = await http.get(
      Uri.parse('https://html.duckduckgo.com/html/?q=${Uri.encodeComponent(query)}'),
      headers: {'User-Agent': 'Mozilla/5.0'},
    );

    if (response.statusCode == 200) {
      return _parseResults(response.body);
    }
  } catch (e) {
    debugPrint('Search failed: $e');
  }
  return '';
}

/// Parses the raw HTML response from DuckDuckGo and formats the results.
String _parseResults(String body) {
  try {
    final document = parser.parse(body);
    final results = document.querySelectorAll('.result__body');

    final context = StringBuffer();
    context.writeln(
        'Here are some web search results for the user\'s query. Use this information to answer:\n');

    int count = 0;
    for (final result in results.take(5)) {
      final titleElement = result.querySelector('.result__a');
      final snippetElement = result.querySelector('.result__snippet');

      if (titleElement != null && snippetElement != null) {
        count++;
        context.writeln('[Result $count]');
        context.writeln('Title: ${titleElement.text.trim()}');
        context.writeln('Snippet: ${snippetElement.text.trim()}\n');
      }
    }

    if (count > 0) {
      return context.toString();
    }
  } catch (e) {
    debugPrint('Search parse failed: $e');
  }
  return '';
}