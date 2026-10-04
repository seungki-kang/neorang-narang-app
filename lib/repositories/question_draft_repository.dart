part of '../main.dart';

class QuestionDraftRepository implements QuestionDraftStore {
  static const String _storageKey = 'neorang_narang_question_draft_v1';

  @override
  Future<QuestionDraft?> load() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final String? stored = preferences.getString(_storageKey);
    if (stored == null || stored.isEmpty) return null;

    try {
      return QuestionDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(stored) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(QuestionDraft draft) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(draft.toJson()));
  }

  @override
  Future<void> clear() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }
}

