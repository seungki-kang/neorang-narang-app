import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:neorang_narang_app/main.dart';

import 'history_recovery_repository_test.dart' show fixture;
import 'history_recovery_widget_test.dart'
    show ControlledHistoryStore, until, tap;

Map<String, dynamic> legacySnapshot(String id, {String text = '저장 대기 원문'}) {
  final saved = fixture(id);
  final draft = GraceDraft(
    id: id,
    courseNumber: saved.courseNumber,
    courseTitle: saved.courseTitle,
    participationMode: saved.participationMode,
    myName: saved.myName,
    partnerName: saved.partnerName,
    reflection: text,
    awaitingSignature: true,
    pendingRecord: saved.withGraceReflection(text),
  );
  return {'saved': saved.toJson(), 'draft': draft.toJson(), 'choice': 'saved'};
}

Future<void> seed(
  CompletionEditingStore store, {
  String id = 'legacy',
  String text = '저장 대기 원문',
}) async {
  await store.add(fixture(id));
  await LegacyRecoveryRepository().append(legacySnapshot(id, text: text));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    completionRepository = CompletionRepository();
    questionDraftRepository = QuestionDraftRepository();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  void size(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'home legacy recovery opens unified title guidance all actions and read-only detail',
    (tester) async {
      size(tester);
      final store = completionRepository as CompletionEditingStore;
      await tester.runAsync(() => seed(store));
      final before = await tester.runAsync(() => store.findById('legacy'));
      final archives = await tester.runAsync(
        () => GraceConflictRecovery.archives(),
      );
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await until(tester, find.byTooltip('저장되지 않은 기록 1개'));
      await tester.tap(find.byTooltip('저장되지 않은 기록 1개'));
      await until(tester, find.byType(UnsavedRecordsPage));
      await until(tester, find.text('다시 저장'));
      expect(find.text('복구 보관함'), findsNothing);
      expect(find.text('저장되지 않은 기록'), findsOneWidget);
      expect(
        find.text('저장을 완료하지 못한 기록입니다. 내용을 확인하고 다시 저장할 수 있습니다.'),
        findsOneWidget,
      );
      expect(find.text('수정 저장 대기'), findsOneWidget);
      expect(find.text('기존 은혜 기록'), findsOneWidget);
      expect(find.text('저장 대기 중인 내용'), findsOneWidget);
      expect(find.text('내용 확인'), findsOneWidget);
      expect(find.text('다시 저장'), findsOneWidget);
      expect(find.text('임시 기록 삭제'), findsOneWidget);
      await tap(tester, '내용 확인');
      expect(find.text('기존 기록 수정'), findsOneWidget);
      expect(
        (await tester.runAsync(() => store.findById('legacy')))!.toJson(),
        before!.toJson(),
      );
      expect(
        await tester.runAsync(() => GraceConflictRecovery.archives()),
        archives,
      );
      await tap(tester, '확인');
    },
  );
  testWidgets(
    'legacy retry removes only its card home menu and persists after recreation',
    (tester) async {
      size(tester);
      final store = completionRepository as CompletionEditingStore;
      await tester.runAsync(() => seed(store));
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await until(tester, find.byTooltip('저장되지 않은 기록 1개'));
      await tester.tap(find.byTooltip('저장되지 않은 기록 1개'));
      await until(tester, find.text('다시 저장'));
      await tap(tester, '다시 저장');
      await tap(tester, '다시 저장');
      await until(tester, find.text('저장되지 않은 기록이 없습니다.'));
      expect((await tester.runAsync(() => store.loadAll()))!.length, 1);
      expect(
        (await tester.runAsync(() => store.findById('legacy')))!.toJson(),
        fixture('legacy').withGraceReflection('저장 대기 원문').toJson(),
      );
      await tester.pageBack();
      await until(tester, find.byType(ProgressCard));
      expect(find.byTooltip('저장되지 않은 기록 1개'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await until(tester, find.byType(ProgressCard));
      expect(find.byTooltip('저장되지 않은 기록 1개'), findsNothing);
      expect(
        await tester.runAsync(() => GraceConflictRecovery.archives()),
        isEmpty,
      );
    },
  );
  testWidgets(
    'legacy retry failure retains both raw source and pending card then succeeds once',
    (tester) async {
      size(tester);
      final store = ControlledHistoryStore()..failSave = true;
      await tester.runAsync(() => seed(store));
      await tester.pumpWidget(UnsavedRecordsApp(store: store));
      await until(tester, find.text('다시 저장'));
      await tap(tester, '다시 저장');
      await tap(tester, '다시 저장');
      expect(
        find.textContaining('저장을 완료하지 못했습니다. 저장 대기 내용은 유지됩니다.'),
        findsOneWidget,
      );
      expect(find.text('저장 대기 원문'), findsOneWidget);
      expect(
        (await tester.runAsync(() => store.findById('legacy')))!
            .graceReflection,
        '기존 은혜',
      );
      expect(
        (await tester.runAsync(() => GraceConflictRecovery.archives()))!.length,
        1,
      );
      final pending = (await tester.runAsync(
        () => CompletionActions(store).pending(),
      ))!;
      expect(
        pending.length,
        1,
      ); // SQLite/prefs stage and the legacy source are the same operation.
      store.failSave = false;
      await tap(tester, '다시 저장');
      await tap(tester, '다시 저장');
      await until(tester, find.text('저장되지 않은 기록이 없습니다.'));
      expect((await tester.runAsync(() => store.loadAll()))!.length, 1);
    },
  );
  testWidgets(
    'legacy temporary deletion cancel and confirm never change completed counts',
    (tester) async {
      size(tester);
      final store = completionRepository as CompletionEditingStore;
      await tester.runAsync(() => seed(store));
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await until(tester, find.byTooltip('저장되지 않은 기록 1개'));
      await tester.tap(find.byTooltip('저장되지 않은 기록 1개'));
      await until(tester, find.text('임시 기록 삭제'));
      await tap(tester, '임시 기록 삭제');
      expect(find.text('저장 대기 내용을 삭제할까요?'), findsOneWidget);
      expect(
        find.text('아직 저장되지 않은 임시 내용만 삭제됩니다. 이미 정상 저장된 완료 기록은 삭제되지 않습니다.'),
        findsOneWidget,
      );
      await tap(tester, '취소');
      expect(find.text('저장 대기 원문'), findsOneWidget);
      await tap(tester, '임시 기록 삭제');
      await tap(tester, '임시 기록 삭제');
      await until(tester, find.text('저장되지 않은 기록이 없습니다.'));
      expect(
        (await tester.runAsync(() => store.findById('legacy')))!.toJson(),
        fixture('legacy').toJson(),
      );
      await tester.pageBack();
      await until(tester, find.byType(ProgressCard));
      expect(
        tester
            .widget<ProgressCard>(find.byType(ProgressCard).first)
            .progress
            .completedCount,
        1,
      );
      expect(find.byTooltip('저장되지 않은 기록 1개'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await until(tester, find.byType(ProgressCard));
      expect(find.byTooltip('저장되지 않은 기록 1개'), findsNothing);
    },
  );
  testWidgets(
    'history recovery route opens unified screen instead of read-only archive',
    (tester) async {
      size(tester);
      final store = completionRepository as CompletionEditingStore;
      await tester.runAsync(() => seed(store));
      await tester.pumpWidget(const MaterialApp(home: CompletionHistoryPage()));
      await until(tester, find.byTooltip('저장되지 않은 기록 1개'));
      await tester.tap(find.byTooltip('저장되지 않은 기록 1개'));
      await until(tester, find.byType(UnsavedRecordsPage));
      await until(tester, find.text('다시 저장'));
      expect(find.text('복구 보관함'), findsNothing);
    },
  );
  testWidgets(
    'new completion content detail labels creation and never writes on inspection',
    (tester) async {
      size(tester);
      final store = CompletionRepository();
      await tester.runAsync(
        () => store.stageRecovery(
          CompletionRecovery(
            record: fixture('new'),
            attemptedAt: DateTime(2026),
          ),
        ),
      );
      await tester.pumpWidget(UnsavedRecordsApp(store: store));
      await until(tester, find.text('내용 확인'));
      await tap(tester, '내용 확인');
      expect(find.text('신규 완료 기록 저장'), findsOneWidget);
      expect(await tester.runAsync(() => store.loadAll()), isEmpty);
      expect((await tester.runAsync(() => store.listRecoveries()))!.length, 1);
      await tap(tester, '확인');
    },
  );
  for (final oldRoute in ['pending', 'archive']) {
    testWidgets(
      'old $oldRoute entry point delegates to unified recovery screen',
      (tester) async {
        size(tester);
        final store = completionRepository as CompletionEditingStore;
        await tester.runAsync(() => seed(store));
        await tester.pumpWidget(
          MaterialApp(
            home: oldRoute == 'pending'
                ? const PendingGracePage()
                : const LegacyGraceArchivePage(),
          ),
        );
        await until(tester, find.text('다시 저장'));
        expect(find.text('저장되지 않은 기록'), findsOneWidget);
        expect(find.text('복구 보관함'), findsNothing);
        expect(find.text('내용 확인'), findsOneWidget);
        expect(find.text('임시 기록 삭제'), findsOneWidget);
      },
    );
  }
  test(
    'legacy snapshot ID stays stable across attempt and repository recreation',
    () async {
      final repo = LegacyRecoveryRepository();
      await repo.append(legacySnapshot('legacy'));
      final before = (await repo.list()).single.id;
      await repo.markAttempt(before, DateTime(2026, 10, 16));
      final reopened = (await LegacyRecoveryRepository().list()).single;
      expect(reopened.id, before);
      expect(reopened.attemptedAt, DateTime(2026, 10, 16));
    },
  );
  test('selected legacy snapshot deletion preserves all other archives and records', () async {
    final store = CompletionRepository();
    await seed(store, id: 'first');
    await seed(store, id: 'second', text: '다른 대기');
    final pending = await CompletionActions(store).pending();
    await CompletionActions(store)
        .discard(pending.firstWhere((e) => e.recordId == 'first'));
    expect((await GraceConflictRecovery.archives()).length, 1);
    expect(
      (await CompletionActions(store).pending()).single.recordId,
      'second',
    );
    expect((await store.loadAll()).length, 2);
  });
  test(
    'legacy retry refuses overwriting a newer edit and preserves source',
    () async {
      final store = CompletionRepository();
      await seed(store);
      final entry = (await CompletionActions(store).pending()).single;
      await store.saveGraceReflection('legacy', '더 최신 내용');
      await expectLater(
        CompletionActions(store).retry(entry),
        throwsStateError,
      );
      expect((await store.findById('legacy'))!.graceReflection, '더 최신 내용');
      expect((await GraceConflictRecovery.archives()).length, 1);
    },
  );
  test('legacy native SQLite retry is UPDATE only and repeated retry never adds a row', () async {
    final app = AppDatabase(databasePath: inMemoryDatabasePath);
    final db = await app.database;
    final store = SqliteCompletionRepository(app);
    try {
      await seed(store);
      await db.execute(
        "CREATE TRIGGER no_insert BEFORE INSERT ON completion_records BEGIN SELECT RAISE(ABORT, 'unexpected insert'); END",
      );
      final actions = CompletionActions(store);
      final entry = (await actions.pending()).single;
      await actions.retry(entry);
      expect(
        (await store.findById('legacy'))!.toJson(),
        fixture('legacy').withGraceReflection('저장 대기 원문').toJson(),
      );
      expect(await actions.pending(), isEmpty);
      await expectLater(
        actions.retry(entry),
        throwsStateError,
      ); // stale UI cannot invent another operation
      expect((await store.loadAll()).length, 1);
    } finally {
      await db.close();
    }
  });
  test('legacy archive corruption is kept intact and cannot be rewritten by listing', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(GraceConflictRecovery.archiveKey, '{broken');
    await expectLater(
      LegacyRecoveryRepository().list(),
      throwsA(isA<StorageReadException>()),
    );
    expect(prefs.getString(GraceConflictRecovery.archiveKey), '{broken');
  });
}

class UnsavedRecordsApp extends StatelessWidget {
  const UnsavedRecordsApp({super.key, required this.store});
  final CompletionEditingStore store;
  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: UnsavedRecordsPage(store: store));
}
