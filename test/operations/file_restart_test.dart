import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:neorang_narang_app/main.dart';
import '../support/operations_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String path;
  late AppDatabase app;
  Database? opened;
  Future<SqliteCompletionRepository> reopen() async {
    await opened?.close();
    app = AppDatabase(databasePath: path);
    opened = await app.database;
    return SqliteCompletionRepository(app);
  }
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nn-operations-fixture-');
    path = '${directory.path}/operations-only.db';
    opened = null;
  });
  tearDown(() async {
    await opened?.close();
    // Only the directory created by this test is removed.
    if (await directory.exists()) { await directory.delete(recursive: true); }
  });
  test('closed file retains pending edit and one successful retry across two reopens', () async {
    var store = await reopen();
    final a = operationsRecord('a');
    await store.add(a);
    final edit = CompletionRecovery(before: a, record: a.withGraceReflection('after restart'), attemptedAt: DateTime.utc(2026));
    await store.stageRecovery(edit);
    store = await reopen();
    expect((await store.listRecoveries()).single.toJson(), edit.toJson());
    expect((await store.findById('a'))!.toJson(), a.toJson());
    await store.retryRecovery(edit.id);
    store = await reopen();
    expect((await store.loadAll()).single.toJson(), edit.record.toJson());
    expect(await store.listRecoveries(), isEmpty);
  });
  test('failed transaction leaves exact pending snapshot after file reopen', () async {
    var store = await reopen();
    final a = operationsRecord('a');
    await store.add(a);
    final edit = CompletionRecovery(before: a, record: a.withGraceReflection('pending'), attemptedAt: DateTime.utc(2026));
    await store.stageRecovery(edit);
    await opened!.execute("CREATE TRIGGER operations_fail_cleanup BEFORE DELETE ON completion_recoveries BEGIN SELECT RAISE(ABORT, 'fixture_failure'); END");
    await expectLater(store.retryRecovery(edit.id), throwsA(isA<DatabaseException>()));
    store = await reopen();
    expect((await store.findById('a'))!.toJson(), a.toJson());
    expect((await store.listRecoveries()).single.toJson(), edit.toJson());
    await opened!.execute('DROP TRIGGER operations_fail_cleanup');
    await store.retryRecovery(edit.id);
    store = await reopen();
    expect((await store.findById('a'))!.toJson(), edit.record.toJson());
    expect(await store.listRecoveries(), isEmpty);
  });
  test('trash retains suspended edit and restore reactivates it after reopen', () async {
    var store = await reopen();
    final a = operationsRecord('a');
    final edit = CompletionRecovery(before: a, record: a.withGraceReflection('suspended'), attemptedAt: DateTime.utc(2026));
    await store.add(a);
    await store.stageRecovery(edit);
    await store.deleteById(a.id);
    store = await reopen();
    expect(await store.findById(a.id), isNull);
    final trash = (await store.listTrash()).single;
    expect(trash.record.toJson(), a.toJson());
    expect(trash.suspendedRecoveries.single.toJson(), edit.toJson());
    await store.restoreTrash(a.id);
    store = await reopen();
    expect((await store.findById(a.id))!.toJson(), a.toJson());
    expect((await store.listRecoveries()).single.toJson(), edit.toJson());
    await store.retryRecovery(edit.id);
    expect((await store.loadAll()).single.toJson(), edit.record.toJson());
  });
  test('permanent deletion marker survives reopen and blocks old ID', () async {
    var store = await reopen();
    final a = operationsRecord('a');
    await store.add(a);
    await store.deleteById(a.id);
    await store.permanentlyDeleteTrash(a.id);
    store = await reopen();
    expect(await store.wasDeleted(a.id), isTrue);
    expect(await store.listTrash(), isEmpty);
    await expectLater(store.add(a), throwsStateError);
    expect(await store.loadAll(), isEmpty);
  });
  test('question draft reopens and clearing it does not erase completion', () async {
    final store = await reopen();
    final record = operationsRecord('a');
    await store.add(record);
    final draft = QuestionDraft(courseNumber: 2, courseTitle: '다 이루었다', participationMode: ParticipationMode.solo,
      myDisplayName: 'fixture', partnerDisplayName: '', firstAskerIsMe: false,
      currentQuestionIndex: 12, savedAt: DateTime.utc(2026, 1, 2));
    await SqliteQuestionDraftRepository(app).save(draft);
    await reopen();
    final drafts = SqliteQuestionDraftRepository(app);
    expect((await drafts.load())!.toJson(), draft.toJson());
    await drafts.clear();
    final finalStore = await reopen();
    expect(await SqliteQuestionDraftRepository(app).load(), isNull);
    expect((await finalStore.loadAll()).single.toJson(), record.toJson());
  });
}
