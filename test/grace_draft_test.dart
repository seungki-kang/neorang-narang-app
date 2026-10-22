import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

GraceDraft sample([String id = 'grace-fixture']) => GraceDraft(
  id: id,
  courseNumber: 1,
  courseTitle: '테스트',
  participationMode: ParticipationMode.solo,
  myName: '테스트',
  partnerName: '',
);
CompletionRecord completed(GraceDraft draft) => CompletionRecord(
  id: draft.id,
  courseNumber: draft.courseNumber,
  courseTitle: draft.courseTitle,
  participationMode: draft.participationMode,
  myName: draft.myName,
  partnerName: draft.partnerName,
  completedAt: DateTime(2026, 10, 9),
  mySignedAt: DateTime(2026, 10, 9),
  partnerSignedAt: null,
  graceReflection: draft.reflection,
  graceReflectionPending: false,
);

class AcknowledgementStore implements CompletionStore {
  bool fail = true;
  final Map<String, CompletionRecord> records = {};
  @override
  Future<void> add(CompletionRecord record) async {
    records.putIfAbsent(record.id, () => record);
    if (fail) throw StateError('test_failure');
  }

  @override
  Future<List<CompletionRecord>> loadAll() async => records.values.toList();
  @override
  Future<int> countForCourse(int courseNumber) async => records.length;
  @override
  Future<List<CompletionRecord>> pendingGraceRecords() async => [];
  @override
  Future<void> saveGraceReflection(String recordId, String reflection) async {}
}

void screenSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// Wait for a concrete UI state, rather than for all animations to stop.
Future<void> waitForGraceState(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(() async {
      // Let platform/preferences asynchronous work complete in real time.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
    await tester.pump(const Duration(milliseconds: 50));
    if (target.evaluate().isNotEmpty) return;
  }
  expect(
    target,
    findsOneWidget,
    reason: 'Expected grace screen state did not appear after initialization.',
  );
}

Future<void> pumpUntilVisible(WidgetTester tester, Finder target) =>
    waitForGraceState(tester, target);

Widget graceScreen() => const MaterialApp(
  home: GraceReflectionPage(
    courseNumber: 1,
    courseTitle: '테스트',
    participationMode: ParticipationMode.solo,
    myName: '테스트',
    partnerName: '',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await initializeStorage();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
  setUp(() async {
    try {
      await graceDraftRepository.load();
    } catch (_) {}
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
  });

  test(
    'queued writes preserve newest reflection across repository restart',
    () async {
      final repo = GraceDraftRepository();
      await Future.wait([
        repo.save(sample().copy(reflection: '처음')),
        repo.save(sample().copy(reflection: '마지막')),
      ]);
      expect((await GraceDraftRepository().load())!.reflection, '마지막');
    },
  );

  test('other session cannot replace or remove draft', () async {
    final repo = GraceDraftRepository();
    await repo.save(sample());
    await expectLater(repo.save(sample('other')), throwsStateError);
    await repo.clearIfId('other');
    expect((await repo.load())!.id, 'grace-fixture');
  });

  test('corrupt grace draft survives save and clear attempts', () async {
    SharedPreferences.setMockInitialValues({
      GraceDraftRepository.storageKey: '{broken',
    });
    final repo = GraceDraftRepository();
    await expectLater(
      repo.save(sample()),
      throwsA(isA<StorageReadException>()),
    );
    await expectLater(
      repo.clearIfId(sample().id),
      throwsA(isA<StorageReadException>()),
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        GraceDraftRepository.storageKey,
      ),
      '{broken',
    );
  });

  test(
    'pending completion restores identity, signature and reflection',
    () async {
      final value = sample().copy(
        reflection: '보존할 은혜',
        awaitingSignature: true,
      );
      final record = completed(value);
      await graceDraftRepository.save(value.copy(pendingRecord: record));
      final restored = (await GraceDraftRepository().load())!;
      expect(restored.pendingRecord!.toJson(), record.toJson());
      expect(restored.awaitingSignature, isTrue);
    },
  );

  testWidgets('autosaved reflection restores after screen recreation', (
    tester,
  ) async {
    screenSize(tester);
    await tester.pumpWidget(graceScreen());
    await waitForGraceState(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), '작성하던 은혜');
    await tester.pump(const Duration(milliseconds: 400));
    await waitForGraceState(tester, find.text('임시저장 완료'));
    expect(
      (await tester.runAsync(() => graceDraftRepository.load()))!.reflection,
      '작성하던 은혜',
    );
    expect(find.text('임시저장 완료'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => graceDraftRepository.load());
    await tester.pumpWidget(graceScreen());
    await waitForGraceState(tester, find.byType(TextField));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '작성하던 은혜',
    );
    await tester.tap(find.text('은혜 기록하고 서명하기'));
    await waitForGraceState(tester, find.byType(CompletionSignaturePage));
    expect(
      (await tester.runAsync(() => graceDraftRepository.load()))!
          .awaitingSignature,
      isTrue,
    );
    expect(
      (await tester.runAsync(() => graceDraftRepository.load()))!.reflection,
      '작성하던 은혜',
    );
  });

  testWidgets(
    'failed completion survives recreation and retries without duplicate',
    (tester) async {
      screenSize(tester);

      final value = sample().copy(reflection: '은혜', awaitingSignature: true);
      debugPrint('NN-RESTORE: 1 initial save start');
      await tester.runAsync(
        () => graceDraftRepository
            .save(value)
            .timeout(const Duration(seconds: 10)),
      );
      debugPrint('NN-RESTORE: 2 initial save done');
      final store = AcknowledgementStore();
      Widget signature(GraceDraft draft) => MaterialApp(
        home: CompletionSignaturePage(
          courseNumber: draft.courseNumber,
          courseTitle: draft.courseTitle,
          participationMode: draft.participationMode,
          myName: draft.myName,
          partnerName: draft.partnerName,
          graceReflection: draft.reflection,
          graceReflectionPending: false,
          completionStore: store,
          graceDraft: draft,
        ),
      );
      debugPrint('NN-RESTORE: 3 open signature');
      await tester.pumpWidget(signature(value));
      debugPrint('NN-RESTORE: 4 signature opened');
      await pumpUntilVisible(tester, find.text('서명하기'));
      await tester.tap(find.text('서명하기'));
      await tester.pump();
      debugPrint('NN-RESTORE: save button tap');
      await tester.tap(find.text('서명 완료하고 마무리'));
      await pumpUntilVisible(
        tester,
        find.text('기록을 저장하지 못했습니다. 서명과 내용은 유지됩니다. 다시 저장해 주세요.'),
      );
      debugPrint('NN-RESTORE: read saved draft');
      final restored = (await tester.runAsync(
        () => graceDraftRepository.load().timeout(const Duration(seconds: 10)),
      ))!;
      expect(restored.pendingRecord, isNotNull);
      final before = restored.pendingRecord!.toJson();
      await tester.pumpWidget(const SizedBox.shrink());
      store.fail = false;
      debugPrint('NN-RESTORE: reopen restored signature');
      await tester.pumpWidget(signature(restored));
      await pumpUntilVisible(tester, find.text('서명됨'));
      expect(find.text('서명됨'), findsOneWidget);
      debugPrint('NN-RESTORE: save button tap');
      await tester.tap(find.text('서명 완료하고 마무리'));
      for (var attempt = 0; attempt < 60; attempt++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        });
        await tester.pump(const Duration(milliseconds: 50));
        if (store.records.length == 1 &&
            find.text('기록 저장 중...').evaluate().isEmpty) {
          break;
        }
      }
      expect(find.text('기록 저장 중...'), findsNothing);
      expect(store.records.length, 1);
      expect(store.records.values.single.toJson(), before);
      expect(
        await tester.runAsync(
          () =>
              graceDraftRepository.load().timeout(const Duration(seconds: 10)),
        ),
        isNull,
      );
    },
  );

  testWidgets('home offers grace resume and blocks a new session', (
    tester,
  ) async {
    screenSize(tester);
    await tester.runAsync(
      () => graceDraftRepository.save(sample().copy(reflection: '보존할 은혜')),
    );
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await waitForGraceState(tester, find.text('은혜 기록 이어쓰기'));
    expect(find.text('은혜 기록 이어쓰기'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, '문답 시작하기'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('은혜 기록 이어쓰기'));
    await waitForGraceState(tester, find.byType(TextField));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '보존할 은혜',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => graceDraftRepository.load());
  });
  testWidgets(
    'home cleans acknowledged completion left by interrupted cleanup',
    (tester) async {
      screenSize(tester);
      final value = sample().copy(
        reflection: '완료한 은혜',
        awaitingSignature: true,
      );
      final record = completed(value);
      await tester.runAsync(
        () => graceDraftRepository.save(value.copy(pendingRecord: record)),
      );
      await tester.runAsync(() => completionRepository.add(record));
      await tester.runAsync(
        () => questionDraftRepository.save(
          QuestionDraft(
            courseNumber: value.courseNumber,
            courseTitle: value.courseTitle,
            participationMode: value.participationMode,
            myDisplayName: value.myName,
            partnerDisplayName: value.partnerName,
            firstAskerIsMe: true,
            currentQuestionIndex: 44,
            savedAt: DateTime(2026, 10, 9),
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await waitForGraceState(tester, find.byType(ProgressCard));
      expect(await tester.runAsync(() => graceDraftRepository.load()), isNull);
      expect(
        await tester.runAsync(() => questionDraftRepository.load()),
        isNull,
      );
      expect(
        (await tester.runAsync(() => completionRepository.loadAll()))!.length,
        1,
      );
      expect(find.text('마무리하지 않은 은혜 기록'), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, '문답 시작하기'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
