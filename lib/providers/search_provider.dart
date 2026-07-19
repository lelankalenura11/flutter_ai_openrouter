import 'package:flutter/foundation.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/models/search_match.dart';

/// Manages search state within the current chat.
class ChatSearchNotifier extends ChangeNotifier {
  String _query = '';
  List<ChatSearchMatch> _matches = [];
  int _currentMatchIndex = 0;
  bool _isActive = false;

  String get query => _query;
  List<ChatSearchMatch> get matches => _matches;
  int get currentMatchIndex => _currentMatchIndex;
  bool get isActive => _isActive;
  bool get hasMatches => _matches.isNotEmpty;

  ChatSearchMatch? get currentMatch {
    if (!hasMatches) return null;
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _matches.length) {
      return null;
    }
    return _matches[_currentMatchIndex];
  }

  void enterSearch() {
    _isActive = true;
    notifyListeners();
  }

  void exitSearch() {
    _isActive = false;
    _query = '';
    _matches = [];
    _currentMatchIndex = 0;
    notifyListeners();
  }

  void setQuery(String query, List<MessagesTableData> messages) {
    _query = query.trim();
    _matches = [];
    _currentMatchIndex = 0;

    if (_query.isEmpty) {
      notifyListeners();
      return;
    }

    final lowerQuery = _query.toLowerCase();

    for (final msg in messages) {
      final text = msg.content;
      final lowerText = text.toLowerCase();
      int start = 0;

      while (true) {
        final index = lowerText.indexOf(lowerQuery, start);
        if (index == -1) break;

        _matches.add(
          ChatSearchMatch(
            messageId: msg.id,
            start: index,
            end: index + _query.length,
          ),
        );

        start = index + _query.length;
      }
    }

    notifyListeners();
  }

  void nextMatch() {
    if (!hasMatches) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _matches.length;
    notifyListeners();
  }

  void previousMatch() {
    if (!hasMatches) return;
    _currentMatchIndex =
        (_currentMatchIndex - 1 + _matches.length) % _matches.length;
    notifyListeners();
  }

  void clear() {
    _query = '';
    _matches = [];
    _currentMatchIndex = 0;
    notifyListeners();
  }
}