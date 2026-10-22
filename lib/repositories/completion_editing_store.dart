part of '../main.dart';

/// History mutations require this richer contract. Existing read/finish doubles
/// can continue implementing CompletionStore without pretending to support edits.
abstract interface class CompletionEditingStore implements CompletionStore {
  Future<CompletionRecord?> findById(String id);
  Future<void> stageRecovery(CompletionRecovery entry);
  Future<List<CompletionRecovery>> listRecoveries();
  Future<void> retryRecovery(String recoveryId);
  Future<void> discardRecovery(String recoveryId);
  Future<void> deleteById(String id);
  Future<bool> wasDeleted(String id);
  Future<List<String>> deletedIds();
}

/// Separate queries prevent deleted snapshots from entering save retries.
abstract interface class CompletionTrashStore
    implements CompletionEditingStore {
  Future<List<CompletionRecovery>> listTrash();
  Future<void> restoreTrash(String id);
  Future<void> permanentlyDeleteTrash(String id);
}
