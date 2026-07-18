import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';
import 'package:flutter_ai_chat_app_openrouter/services/auth_service.dart';
import 'package:flutter_ai_chat_app_openrouter/services/openrouter_service.dart';

class SettingsProvider extends ChangeNotifier {
  final AppDatabase _db;
  final AuthService _authService;
  final OpenRouterService _openRouterService;

  String _apiKey = '';
  String _model = 'openai/gpt-4o';
  int _maxTokens = 4096;
  double _temperature = 0.7;
  String _theme = 'system';
  bool _isLoading = false;
  String? _error;
  bool _connectionTestResult = false;
  bool _connectionTestRunning = false;
  bool _isExporting = false;
  bool _isImporting = false;

  String get apiKey => _apiKey;
  String get model => _model;
  int get maxTokens => _maxTokens;
  double get temperature => _temperature;
  String get theme => _theme;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get connectionTestResult => _connectionTestResult;
  bool get connectionTestRunning => _connectionTestRunning;
  bool get isExporting => _isExporting;
  bool get isImporting => _isImporting;

  void setExporting(bool value) {
    _isExporting = value;
    notifyListeners();
  }

  void setImporting(bool value) {
    _isImporting = value;
    notifyListeners();
  }

  SettingsProvider(this._db, this._authService, this._openRouterService);

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load API key
      _apiKey = (await _authService.getApiKey()) ?? '';

      // Load settings from DB
      final settings = await _db.getSettings();
      if (settings != null) {
        _model = settings.openrouterModel;
        _maxTokens = settings.maxTokens;
        _temperature = settings.temperature;
        _theme = settings.theme;
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveApiKey(String key) async {
    await _authService.saveApiKey(key);
    _apiKey = key;
    notifyListeners();
  }

  Future<void> saveModel(String value) async {
    _model = value;
    await _db.updateSettings(SettingsTableCompanion(
      id: const Value('default'),
      openrouterModel: Value(value),
      maxTokens: Value(_maxTokens),
      temperature: Value(_temperature),
      theme: Value(_theme),
    ));
    notifyListeners();
  }

  Future<void> saveMaxTokens(int value) async {
    _maxTokens = value;
    await _db.updateSettings(SettingsTableCompanion(
      id: const Value('default'),
      openrouterModel: Value(_model),
      maxTokens: Value(value),
      temperature: Value(_temperature),
      theme: Value(_theme),
    ));
    notifyListeners();
  }

  Future<void> saveTemperature(double value) async {
    _temperature = value;
    await _db.updateSettings(SettingsTableCompanion(
      id: const Value('default'),
      openrouterModel: Value(_model),
      maxTokens: Value(_maxTokens),
      temperature: Value(value),
      theme: Value(_theme),
    ));
    notifyListeners();
  }

  Future<void> saveTheme(String value) async {
    _theme = value;
    await _db.updateSettings(SettingsTableCompanion(
      id: const Value('default'),
      openrouterModel: Value(_model),
      maxTokens: Value(_maxTokens),
      temperature: Value(_temperature),
      theme: Value(value),
    ));
    notifyListeners();
  }

  Future<void> testConnection() async {
    _connectionTestRunning = true;
    _error = null;
    notifyListeners();

    try {
      _connectionTestResult = await _openRouterService.testConnection(
        apiKey: _apiKey,
      );
      if (!_connectionTestResult) {
        _error = 'Connection failed. Check your API key.';
      }
    } catch (e) {
      _connectionTestResult = false;
      _error = 'Connection error: $e';
    }

    _connectionTestRunning = false;
    notifyListeners();
  }
}