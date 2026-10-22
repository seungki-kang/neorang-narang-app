part of '../main.dart';

/// Dependencies needed by completion recovery, separate from the record store.
/// Defaults resolve storage lazily, preserving existing startup and test behavior.
abstract interface class CompletionRecoveryContext {
  Future<GraceDraft?> loadGrace();
  Future<void> clearGrace(String id);
  Future<void> clearQuestion(GraceDraft grace);
  Future<void> purgeRetained(String id);
  Future<List<LegacyCompletionRecovery>> listLegacy();
  Future<void> removeLegacy(String id);
  Future<void> removeLegacyForRecord(String id);
  Future<void> markLegacyAttempt(String id, DateTime time);
}

class StoredCompletionRecoveryContext implements CompletionRecoveryContext {
  @override
  Future<GraceDraft?> loadGrace() => graceDraftRepository.load();
  @override
  Future<void> clearGrace(String id) => graceDraftRepository.clearIfId(id);
  @override
  Future<void> clearQuestion(GraceDraft grace) => clearQuestionForGrace(grace);
  @override
  Future<void> purgeRetained(String id) =>
      CompletionRepository().purgeRetainedCopy(id);
  @override
  Future<List<LegacyCompletionRecovery>> listLegacy() =>
      LegacyRecoveryRepository().list();
  @override
  Future<void> removeLegacy(String id) => LegacyRecoveryRepository().remove(id);
  @override
  Future<void> removeLegacyForRecord(String id) =>
      LegacyRecoveryRepository().removeForRecord(id);
  @override
  Future<void> markLegacyAttempt(String id, DateTime time) =>
      LegacyRecoveryRepository().markAttempt(id, time);
}
