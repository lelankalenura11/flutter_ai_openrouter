import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_ai_chat_app_openrouter/database/app_database.dart';

class SkillProvider extends ChangeNotifier {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  List<SkillsTableData> _skills = [];
  bool _isLoading = false;

  List<SkillsTableData> get skills => _skills;
  bool get isLoading => _isLoading;

  SkillProvider(this._db);

  Future<void> loadSkills() async {
    _isLoading = true;
    notifyListeners();

    try {
      _skills = await _db.getAllSkills();
    } catch (e) {
      debugPrint('Error loading skills: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> createSkill(String name, String prompt) async {
    final id = _uuid.v4();
    await _db.insertSkill(SkillsTableCompanion(
      id: Value(id),
      name: Value(name),
      systemPrompt: Value(prompt),
      isBuiltin: const Value(false),
      createdAt: Value(DateTime.now()),
    ));
    await loadSkills();
  }

  Future<void> updateSkill(String id, String name, String prompt) async {
    await _db.updateSkill(SkillsTableCompanion(
      id: Value(id),
      name: Value(name),
      systemPrompt: Value(prompt),
      isBuiltin: Value(_skills.firstWhere((s) => s.id == id).isBuiltin),
      createdAt: Value(_skills.firstWhere((s) => s.id == id).createdAt),
    ));
    await loadSkills();
  }

  Future<void> deleteSkill(String id) async {
    await _db.deleteSkill(id);
    await loadSkills();
  }
}