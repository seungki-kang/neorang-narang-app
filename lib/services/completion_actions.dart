part of '../main.dart';

class CompletionActions {
  CompletionActions(
    this.store, {
    CompletionRecoveryContext? recoveryContext,
    DateTime Function()? clock,
  }) : recoveryContext = recoveryContext ?? StoredCompletionRecoveryContext(),
       _now = clock ?? DateTime.now;

  final CompletionRecoveryContext recoveryContext;
  final DateTime Function() _now;
  final CompletionEditingStore store;
  Future<void> saveEdit(CompletionRecord before, String reflection) async {
    final entry = CompletionRecovery(
      before: before,
      record: before.withGraceReflection(reflection.trim()),
      attemptedAt: _now(),
    );
    try {
      await store.stageRecovery(entry);
      await store.retryRecovery(entry.id);
    } catch (_) {
      final current = await store.findById(entry.record.id);
      if (current == null || !sameCompletion(current, entry.record)) rethrow;
    }
  }

  Future<void> saveNew(CompletionRecord record) async {
    final entry = CompletionRecovery(
      record: record,
      attemptedAt: _now(),
    );
    await store.stageRecovery(entry);
    await store.retryRecovery(entry.id);
  }

  Future<bool> delete(String id) async {
    try {
      await store.deleteById(id);
    } catch (_) {
      if (!await store.wasDeleted(id) || await store.findById(id) != null) {
        rethrow;
      }
    }
    if (await store.findById(id) != null) {
      throw StateError('completion_delete_unverified');
    }
    // Legacy prefs cannot participate in a SQLite transaction. A durable tombstone
    // prevents resurrection if cleanup is interrupted; home/page load retries it.
    if (store is CompletionTrashStore) return true;
    try {
      await cleanLegacy(id);
      return true;
    } catch (_) {
      return false; // Tombstone persists, so pending() retries cleanup.
    }
  }

  Future<void> cleanLegacy(String id) async {
    final trashStore = store;
    if (trashStore is CompletionTrashStore &&
        (await trashStore.listTrash()).any((e) => e.record.id == id)) {
      return;
    }
    if (await store.findById(id) != null) return;
    await recoveryContext.purgeRetained(id);
    final draft = await recoveryContext.loadGrace();
    if (draft?.id == id) await recoveryContext.clearGrace(id);
    await recoveryContext.removeLegacyForRecord(id);
  }

  Future<List<PendingCompletion>> pending() async {
    final trashStore = store;
    final archivedIds = trashStore is CompletionTrashStore
        ? (await trashStore.listTrash()).map((e) => e.record.id).toSet()
        : <String>{};
    for (final id in await store.deletedIds()) {
      if (archivedIds.contains(id)) continue;
      if (await store.findById(id) != null) continue;
      await cleanLegacy(id);
    }
    final entries = await store.listRecoveries();
    final result = <PendingCompletion>[];
    for (final entry in entries) {
      final current = await store.findById(entry.record.id);
      if (current != null &&
          (entry.before == null
              ? current.hasSameCompletionContent(entry.record)
              : sameCompletion(current, entry.record))) {
        try {
          await store.retryRecovery(entry.id);
        } catch (_) {
          if ((await store.listRecoveries()).any((r) => r.id == entry.id)) {
            result.add(PendingCompletion(recovery: entry));
          }
        }
      } else {
        result.add(PendingCompletion(recovery: entry));
      }
    }
    final grace = await recoveryContext.loadGrace();
    if (grace != null) {
      if (await store.wasDeleted(grace.id)) {
        if (!archivedIds.contains(grace.id)) await cleanLegacy(grace.id);
      } else if (!result.any((e) => e.recordId == grace.id)) {
        final current = await store.findById(grace.id);
        if (current != null && grace.matchesCompletion(current)) {
          await recoveryContext.clearQuestion(grace);
          await recoveryContext.clearGrace(grace.id);
        } else {
          result.add(PendingCompletion(grace: grace));
        }
      }
    }
    for (final legacy in await recoveryContext.listLegacy()) {
      if (await store.wasDeleted(legacy.before.id)) continue;
      final current = await store.findById(legacy.before.id);
      if (current != null && sameCompletion(current, legacy.desired)) {
        await recoveryContext.removeLegacy(
          legacy.id,
        ); // already committed, no UPDATE needed
        continue;
      }
      final equivalent = result
          .where(
            (p) =>
                p.recordId == legacy.before.id &&
                p.reflection == legacy.reflection,
          )
          .firstOrNull;
      if (equivalent != null) {
        equivalent.legacySources.add(legacy);
      } else {
        result.add(PendingCompletion(legacy: legacy));
      }
    }
    return result;
  }

  Future<void> retry(PendingCompletion pending) async {
    final legacy = pending.legacy;
    if (legacy != null) {
      if (!GraceConflictRecovery.canUseDraft(legacy.draft, legacy.before)) {
        throw StateError('legacy_identity_conflict');
      }
      await recoveryContext.markLegacyAttempt(legacy.id, _now());
      await saveEdit(legacy.before, legacy.reflection);
      await recoveryContext.removeLegacy(legacy.id);
      return;
    }
    for (final source in pending.legacySources) {
      await recoveryContext.markLegacyAttempt(source.id, _now());
    }
    final recovery = pending.recovery;
    if (recovery != null) {
      final entry = CompletionRecovery(
        record: recovery.record,
        before: recovery.before,
        attemptedAt: _now(),
      );
      await store.stageRecovery(entry);
      await store.retryRecovery(entry.id);
      final grace = await recoveryContext.loadGrace();
      if (grace?.id == recovery.record.id &&
          grace!.matchesCompletion((await store.findById(grace.id))!)) {
        await recoveryContext.clearQuestion(grace);
        await recoveryContext.clearGrace(grace.id);
      }
      for (final source in pending.legacySources) {
        await recoveryContext.removeLegacy(source.id);
      }
      return;
    }
    final grace = pending.grace!;
    final record = grace.pendingRecord;
    if (record == null) throw StateError('signature_required');
    final saved = await store.findById(grace.id);
    if (saved == null || grace.matchesCompletion(saved)) {
      await saveNew(record);
      await recoveryContext.clearQuestion(grace);
      await recoveryContext.clearGrace(grace.id);
    } else {
      if (!GraceConflictRecovery.canUseDraft(grace, saved)) {
        throw StateError('completion_identity_conflict');
      }
      await saveEdit(saved, record.graceReflection);
      await recoveryContext.clearQuestion(grace);
      await recoveryContext.clearGrace(grace.id);
    }
    for (final source in pending.legacySources) {
      await recoveryContext.removeLegacy(source.id);
    }
  }

  Future<void> discard(PendingCompletion pending) async {
    if (pending.legacy != null) {
      await recoveryContext.removeLegacy(pending.legacy!.id);
      return;
    }
    if (pending.recovery != null) {
      await store.discardRecovery(pending.recovery!.id);
    }
    final grace = await recoveryContext.loadGrace();
    if (grace?.id == pending.recordId &&
        (grace!.pendingRecord?.graceReflection ?? grace.reflection) ==
            pending.reflection) {
      await recoveryContext.clearGrace(pending.recordId);
    }
    for (final source in pending.legacySources) {
      await recoveryContext.removeLegacy(source.id);
    }
  }
}

class PendingCompletion {
  PendingCompletion({this.recovery, this.grace, this.legacy});
  final CompletionRecovery? recovery;
  final GraceDraft? grace;
  final LegacyCompletionRecovery? legacy;
  final List<LegacyCompletionRecovery> legacySources = [];
  String get recordId => recovery?.record.id ?? grace?.id ?? legacy!.before.id;
  int get courseNumber =>
      recovery?.record.courseNumber ??
      grace?.courseNumber ??
      legacy!.before.courseNumber;
  String get title =>
      recovery?.record.courseTitle ??
      grace?.courseTitle ??
      legacy!.before.courseTitle;
  String get reflection =>
      recovery?.record.graceReflection ??
      grace?.pendingRecord?.graceReflection ??
      grace?.reflection ??
      legacy!.reflection;
  DateTime? get attemptedAt =>
      recovery?.attemptedAt ?? grace?.lastAttemptAt ?? legacy?.attemptedAt;
  bool get isEdit => recovery?.before != null || legacy != null;
}
