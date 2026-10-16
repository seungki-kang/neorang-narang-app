part of '../main.dart';

class QuestionDraftRepository implements QuestionDraftStore {
  static const String _storageKey = 'neorang_narang_question_draft_v1';

  @override
  Future<QuestionDraft?> load() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final String? stored = preferences.getString(_storageKey);
    if (stored == null) return null;

    try {
      return QuestionDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(stored) as Map),
      );
    } catch (_) {
      throw const StorageReadException();
    }
  }

  @override
  Future<void> save(QuestionDraft draft) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await load(); // Refuse to overwrite an unreadable existing draft.
    final bool saved =
        await preferences.setString(_storageKey, jsonEncode(draft.toJson()));
    if (!saved) throw StateError('draft_write_failed');
  }

  @override
  Future<void> clear() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await load(); // Corrupt drafts need recovery, not automatic removal.
    if (!await preferences.remove(_storageKey)) {
      throw StateError('draft_remove_failed');
    }
  }
}

