import 'package:flutter_test/flutter_test.dart';
import 'package:neorang_narang_app/main.dart';

// Synthetic fixtures only. Never use a person's journal or device database.
CompletionRecord operationsRecord(String id, {int course = 1, String text = 'fixture'}) =>
    CompletionRecord(
      id: id, courseNumber: course,
      courseTitle: course == 1 ? '다 끝났다' : '다 이루었다',
      participationMode: ParticipationMode.together,
      myName: 'fixture-self', partnerName: 'fixture-partner',
      completedAt: DateTime.utc(2026, 1, 2),
      mySignedAt: DateTime.utc(2026, 1, 1, 10),
      partnerSignedAt: DateTime.utc(2026, 1, 1, 11),
      graceReflection: text, graceReflectionPending: false,
    );

Map<String, Future<void> Function(CompletionTrashStore)> operationsScenarios() => {
  'concurrent distinct writes preserve every complete record': (store) async {
    final expected = List.generate(12, (i) => operationsRecord('parallel-$i', course: i.isEven ? 1 : 2));
    await Future.wait(expected.map(store.add));
    final actual = await store.loadAll();
    expect(actual, hasLength(12));
    for (final record in expected) {
      expect(actual.singleWhere((r) => r.id == record.id).toJson(), record.toJson());
    }
    expect(await store.countForCourse(1), 6);
    expect(await store.countForCourse(2), 6);
  },
  'concurrent identical retries create one record': (store) async {
    final record = operationsRecord('same');
    await Future.wait(List.generate(12, (_) => store.add(record)));
    expect((await store.loadAll()).single.toJson(), record.toJson());
  },
  'identity conflict does not poison the following write': (store) async {
    final first = operationsRecord('a');
    await store.add(first);
    await expectLater(store.add(operationsRecord('a', text: 'conflict')), throwsStateError);
    await store.add(operationsRecord('b', course: 2));
    expect((await store.findById('a'))!.toJson(), first.toJson());
    expect((await store.findById('b'))!.toJson(), operationsRecord('b', course: 2).toJson());
    expect(await store.loadAll(), hasLength(2));
  },
  'empty reflection update survives edit trash restore without identity change': (store) async {
    final original = operationsRecord('a');
    await store.add(original);
    await CompletionActions(store).saveEdit(original, '');
    final empty = original.withGraceReflection('');
    expect((await store.findById('a'))!.toJson(), empty.toJson());
    await store.deleteById('a');
    expect((await store.listTrash()).single.record.toJson(), empty.toJson());
    await store.restoreTrash('a');
    expect((await store.findById('a'))!.toJson(), empty.toJson());
    expect(await store.listRecoveries(), isEmpty);
    expect(await store.listTrash(), isEmpty);
  },
  'discarded unsaved new ID stays blocked while unrelated pending survives': (store) async {
    final a = CompletionRecovery(record: operationsRecord('a'), attemptedAt: DateTime.utc(2026));
    final b = CompletionRecovery(record: operationsRecord('b'), attemptedAt: DateTime.utc(2026));
    await store.stageRecovery(a);
    await store.stageRecovery(b);
    await store.discardRecovery(a.id);
    await expectLater(store.add(a.record), throwsStateError);
    await expectLater(store.stageRecovery(a), throwsStateError);
    await store.retryRecovery(b.id);
    expect((await store.loadAll()).single.toJson(), b.record.toJson());
    expect(await store.listRecoveries(), isEmpty);
    expect(await store.wasDeleted('a'), isTrue);
  },
  'stale edit fails after newer edit without losing either pending or current': (store) async {
    final a = operationsRecord('a');
    await store.add(a);
    final pending = CompletionRecovery(before: a, record: a.withGraceReflection('old attempt'), attemptedAt: DateTime.utc(2026));
    await store.stageRecovery(pending);
    await store.saveGraceReflection('a', 'new current');
    await expectLater(store.retryRecovery(pending.id), throwsStateError);
    expect((await store.findById('a'))!.toJson(), a.withGraceReflection('new current').toJson());
    expect((await store.listRecoveries()).single.toJson(), pending.toJson());
    await store.discardRecovery(pending.id);
    expect((await store.findById('a'))!.graceReflection, 'new current');
  },
  'permanent delete does not resurrect through stale recovery replay': (store) async {
    final a = operationsRecord('a');
    await store.add(a);
    await store.add(operationsRecord('b', course: 2));
    await store.deleteById(a.id);
    await store.permanentlyDeleteTrash(a.id);
    await expectLater(store.stageRecovery(CompletionRecovery(record: a, attemptedAt: DateTime.utc(2026))), throwsStateError);
    await expectLater(store.add(a), throwsStateError);
    expect(await store.listTrash(), isEmpty);
    expect(await store.listRecoveries(), isEmpty);
    expect((await store.loadAll()).single.toJson(), operationsRecord('b', course: 2).toJson());
  },
  'mixed chapter operation sequence has exact final snapshots': (store) async {
    final records = List.generate(8, (i) => operationsRecord('sequence-$i', course: i.isEven ? 1 : 2));
    for (final r in records) { await store.add(r); }
    await CompletionActions(store).saveEdit(records[0], 'updated');
    await store.deleteById(records[1].id);
    await store.deleteById(records[2].id);
    await store.restoreTrash(records[1].id);
    await store.permanentlyDeleteTrash(records[2].id);
    final expected = {for (final r in records) if (r.id != records[2].id) r.id: r.toJson()};
    expected[records[0].id] = records[0].withGraceReflection('updated').toJson();
    final actual = {for (final r in await store.loadAll()) r.id: r.toJson()};
    expect(actual, expected);
    expect(await store.countForCourse(1), 3);
    expect(await store.countForCourse(2), 4);
    expect(await store.listTrash(), isEmpty);
    expect(await store.listRecoveries(), isEmpty);
  },
};
