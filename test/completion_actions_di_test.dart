import 'package:flutter_test/flutter_test.dart';
import 'package:neorang_narang_app/main.dart';

final fixedTime = DateTime.utc(2026, 10, 22, 10);

CompletionRecord record(String id, {String reflection = '원문'}) =>
    CompletionRecord(
      id: id,
      courseNumber: 1,
      courseTitle: '다 끝났다',
      participationMode: ParticipationMode.solo,
      myName: '가상 참여자',
      partnerName: '',
      completedAt: fixedTime,
      mySignedAt: fixedTime,
      partnerSignedAt: null,
      graceReflection: reflection,
      graceReflectionPending: false,
    );

GraceDraft draft(CompletionRecord value) => GraceDraft(
  id: value.id,
  courseNumber: value.courseNumber,
  courseTitle: value.courseTitle,
  participationMode: value.participationMode,
  myName: value.myName,
  partnerName: value.partnerName,
  reflection: value.graceReflection,
  awaitingSignature: true,
  pendingRecord: value,
);

// No SharedPreferences mock, global initialization, filesystem or SQLite.
class MemoryRecoveryContext implements CompletionRecoveryContext {
  GraceDraft? grace;
  bool failQuestionCleanup = false;
  bool failGraceCleanup = false;
  bool failPurge = false;
  final calls = <String>[];
  final legacy = <LegacyCompletionRecovery>[];
  DateTime? attemptedAt;

  @override
  Future<GraceDraft?> loadGrace() async => grace;
  @override
  Future<void> clearGrace(String id) async {
    calls.add('grace:$id');
    if (failGraceCleanup) {
      throw StateError('injected_grace_cleanup');
    }
    if (grace?.id == id) {
      grace = null;
    }
  }
  @override
  Future<void> clearQuestion(GraceDraft value) async {
    calls.add('question:${value.id}');
    if (failQuestionCleanup) {
      throw StateError('injected_question_cleanup');
    }
  }
  @override
  Future<void> purgeRetained(String id) async {
    calls.add('purge:$id');
    if (failPurge) {
      throw StateError('injected_purge');
    }
  }
  @override
  Future<List<LegacyCompletionRecovery>> listLegacy() async => [...legacy];
  @override
  Future<void> removeLegacy(String id) async {
    calls.add('legacy:$id');
    legacy.removeWhere((entry) => entry.id == id);
  }
  @override
  Future<void> removeLegacyForRecord(String id) async {
    calls.add('legacy-record:$id');
    legacy.removeWhere((entry) => entry.before.id == id);
  }
  @override
  Future<void> markLegacyAttempt(String id, DateTime time) async {
    calls.add('attempt:$id');
    attemptedAt = time;
  }
}

class MemoryEditingStore implements CompletionEditingStore {
  final records = <String, CompletionRecord>{};
  final recoveries = <String, CompletionRecovery>{};
  final deleted = <String>{};
  bool failStage = false;
  bool failCommit = false;
  bool loseAcknowledgement = false;
  int commits = 0;
  int retries = 0;

  @override
  Future<void> stageRecovery(CompletionRecovery entry) async {
    if (failStage) {
      throw StateError('injected_stage');
    }
    recoveries[entry.id] = entry;
  }
  @override
  Future<void> retryRecovery(String id) async {
    retries++;
    if (failCommit) {
      throw StateError('injected_commit');
    }
    final entry = recoveries[id];
    if (entry == null) {
      return;
    }
    if (deleted.contains(entry.record.id)) {
      throw StateError('deleted');
    }
    if (!records.containsKey(entry.record.id)) {
      commits++;
    }
    records[entry.record.id] = entry.record;
    recoveries.remove(id);
    if (loseAcknowledgement) {
      throw StateError('injected_ack_loss');
    }
  }
  @override
  Future<List<CompletionRecord>> loadAll() async => records.values.toList();
  @override
  Future<CompletionRecord?> findById(String id) async => records[id];
  @override
  Future<List<CompletionRecovery>> listRecoveries() async =>
      recoveries.values.toList();
  @override
  Future<void> discardRecovery(String id) async {
    recoveries.remove(id);
  }
  @override
  Future<List<String>> deletedIds() async => deleted.toList();
  @override
  Future<bool> wasDeleted(String id) async => deleted.contains(id);
  @override
  Future<void> add(CompletionRecord value) async {
    throw StateError('unexpected_direct_add');
  }
  @override
  Future<void> deleteById(String id) async {
    throw StateError('unexpected_delete');
  }
  @override
  Future<int> countForCourse(int number) async =>
      records.values.where((entry) => entry.courseNumber == number).length;
  @override
  Future<List<CompletionRecord>> pendingGraceRecords() async =>
      records.values.where((entry) => entry.graceReflectionPending).toList();
  @override
  Future<void> saveGraceReflection(String id, String reflection) async {
    throw StateError('unexpected_direct_edit');
  }
}

CompletionActions actions(
  MemoryEditingStore store,
  MemoryRecoveryContext context,
) => CompletionActions(
  store,
  recoveryContext: context,
  clock: () => fixedTime,
);

void main() {
  test('DI staging failure prevents commit and preserves unrelated records', () async {
    final store = MemoryEditingStore()..failStage = true;
    final context = MemoryRecoveryContext();
    final other = record('other');
    store.records[other.id] = other;
    await expectLater(actions(store, context).saveNew(record('new')), throwsStateError);
    expect(store.retries, 0);
    expect(store.recoveries, isEmpty);
    expect((await store.loadAll()).single.toJson(), other.toJson());
    expect(context.calls, isEmpty);
  });

  test('DI failed commit keeps exact retry payload and injected attempt time', () async {
    final store = MemoryEditingStore()..failCommit = true;
    final value = record('new');
    await expectLater(
      actions(store, MemoryRecoveryContext()).saveNew(value), throwsStateError,
    );
    expect(store.records, isEmpty);
    expect(store.recoveries.values.single.record.toJson(), value.toJson());
    expect(store.recoveries.values.single.attemptedAt, fixedTime);
  });

  test('DI edit acknowledgement loss recognizes committed content', () async {
    final store = MemoryEditingStore()..loseAcknowledgement = true;
    final before = record('edit');
    store.records[before.id] = before;
    await actions(store, MemoryRecoveryContext()).saveEdit(before, ' 수정 내용 ');
    expect(store.records.length, 1);
    expect(store.records[before.id]!.toJson(),
        before.withGraceReflection('수정 내용').toJson());
    expect(store.recoveries, isEmpty);
  });

  test('DI uncommitted edit failure preserves original and pending edit', () async {
    final store = MemoryEditingStore()..failCommit = true;
    final before = record('edit');
    store.records[before.id] = before;
    await expectLater(actions(store, MemoryRecoveryContext()).saveEdit(before, '수정'),
        throwsStateError);
    expect(store.records[before.id]!.toJson(), before.toJson());
    expect(store.recoveries.values.single.before!.toJson(), before.toJson());
    expect(store.recoveries.values.single.record.graceReflection, '수정');
  });

  test('DI pending cleanup failure preserves committed record and draft then recovers', () async {
    final store = MemoryEditingStore();
    final value = record('saved');
    store.records[value.id] = value;
    final context = MemoryRecoveryContext()
      ..grace = draft(value)
      ..failQuestionCleanup = true;
    final service = actions(store, context);
    await expectLater(service.pending(), throwsStateError);
    expect(context.grace!.pendingRecord!.toJson(), value.toJson());
    expect(store.records[value.id]!.toJson(), value.toJson());
    expect(context.calls, ['question:saved']);
    context.failQuestionCleanup = false;
    expect(await service.pending(), isEmpty);
    expect(context.grace, isNull);
    expect(store.records.length, 1);
    expect(store.commits, 0);
    expect(context.calls, ['question:saved', 'question:saved', 'grace:saved']);
  });

  test('DI retry after grace cleanup failure never changes signature identity', () async {
    final store = MemoryEditingStore();
    final value = record('retry');
    final context = MemoryRecoveryContext()
      ..grace = draft(value)
      ..failGraceCleanup = true;
    final pending = PendingCompletion(grace: context.grace);
    final service = actions(store, context);
    await expectLater(service.retry(pending), throwsStateError);
    expect(store.records[value.id]!.toJson(), value.toJson());
    expect(context.grace, isNotNull);
    context.failGraceCleanup = false;
    await service.retry(pending);
    expect(context.grace, isNull);
    expect(store.records.length, 1);
    expect(store.records[value.id]!.toJson(), value.toJson());
    expect(store.commits, 1);
  });

  test('DI simultaneous contexts cannot clear each other', () async {
    final leftStore = MemoryEditingStore();
    final rightStore = MemoryEditingStore();
    final left = record('left');
    final right = record('right');
    leftStore.records[left.id] = left;
    rightStore.records[right.id] = right;
    final leftContext = MemoryRecoveryContext()..grace = draft(left);
    final rightContext = MemoryRecoveryContext()..grace = draft(right);
    await Future.wait([
      actions(leftStore, leftContext).pending(),
      actions(rightStore, rightContext).discard(
        PendingCompletion(grace: draft(record('unrelated'))),
      ),
    ]);
    expect(leftContext.grace, isNull);
    expect(rightContext.grace!.toJson(), draft(right).toJson());
    expect(rightContext.calls, isEmpty);
    expect(leftStore.records[left.id]!.toJson(), left.toJson());
    expect(rightStore.records[right.id]!.toJson(), right.toJson());
  });

  test('DI failed retained-copy cleanup cannot erase grace or legacy sources', () async {
    final context = MemoryRecoveryContext()
      ..grace = draft(record('cleanup'))
      ..failPurge = true;
    await expectLater(actions(MemoryEditingStore(), context).cleanLegacy('cleanup'),
        throwsStateError);
    expect(context.grace, isNotNull);
    expect(context.calls, ['purge:cleanup']);
  });

  test('DI successful cleanup preserves ordering and unrelated grace', () async {
    final context = MemoryRecoveryContext()..grace = draft(record('unrelated'));
    await actions(MemoryEditingStore(), context).cleanLegacy('deleted');
    expect(context.grace!.id, 'unrelated');
    expect(context.calls, ['purge:deleted', 'legacy-record:deleted']);
  });

  test('DI legacy retry records injected time and retains original completion dates', () async {
    final before = record('legacy');
    final desired = before.withGraceReflection('이전 복구 내용');
    final legacy = LegacyCompletionRecovery({
      'saved': before.toJson(),
      'draft': draft(desired).toJson(),
      'choice': 'draft',
    });
    final context = MemoryRecoveryContext()..legacy.add(legacy);
    final store = MemoryEditingStore();
    store.records[before.id] = before;
    await actions(store, context).retry(PendingCompletion(legacy: legacy));
    expect(context.attemptedAt, fixedTime);
    expect(context.legacy, isEmpty);
    expect(store.records[before.id]!.toJson(), desired.toJson());
    expect(context.calls, ['attempt:${legacy.id}', 'legacy:${legacy.id}']);
  });
}
