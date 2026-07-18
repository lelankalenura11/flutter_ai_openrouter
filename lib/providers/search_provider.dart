import 'package:flutter/foundation.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/models/search_match.dart';

/// Manages search state within the current chat.
/// Telegram-style: starts from most recent match, Enter/Shift+Enter navigation.
class ChatSearchNotifier extends ChangeNotifier {
  String _query = '';
  List<SearchMatch> _matches = [];
  int _currentMatchIndex = -1;
  bool _isActive = false;

  String get query => _query;
  List<SearchMatch> get matches => _matches;
  int get currentMatchIndex => _currentMatchIndex;
  bool get isActive => _isActive;
  bool get hasMatches => _matches.isNotEmpty;

  String get counterText {
    if (_matches.isEmpty) return '0/0';
    return '${_currentMatchIndex + 1}/${_matches.length}';
  }

  void enterSearch() {
    _isActive = true;
    notifyListeners();
  }

  void exitSearch() {
    _isActive = false;
    _query = '';
    _matches = [];
    _currentMatchIndex = -1;
    notifyListeners();
  }

  void setQuery(String query, List<MessagesTableData> messages) {
    _query = query.trim();
    _matches = [];
    _currentMatchIndex = -1;

    if (_query.isEmpty) {
      notifyListeners();
      return;
    }

    final regex = RegExp(RegExp.escape(_query), caseSensitive: false);

    for (final msg in messages) {
      for (final match in regex.allMatches(msg.content)) {
        _matches.add(SearchMatch(msg.id, match.start, match.end));
      }
    }

    // Telegram starts from the MOST RECENT match (end of list)
    if (_matches.isNotEmpty) {
      _currentMatchIndex = _matches.length - 1;
    }

    notifyListeners();
  }

  void nextMatch() {
    if (_matches.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _matches.length;
    notifyListeners();
  }

  void previousMatch() {
    if (_matches.isEmpty) return;
    _currentMatchIndex =
        (_currentMatchIndex - 1 + _matches.length) % _matches.length;
    notifyListeners();
  }

  SearchMatch? get currentMatch {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _matches.length) {
      return null;
    }
    return _matches[_currentMatchIndex];
  }

  bool isActiveMatch(String messageId, int start, int end) {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _matches.length) {
      return false;
    }
    final m = _matches[_currentMatchIndex];
    return m.messageId == messageId && m.start == start && m.end == end;
  }
}
