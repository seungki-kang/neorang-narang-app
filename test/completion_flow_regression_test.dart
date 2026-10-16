import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

GraceDraft fixture() => const GraceDraft(
  id: 'flow-regression', courseNumber: 2, courseTitle: '다 이루었다',
  participationMode: ParticipationMode.solo, myName: '시험 참여자',
  partnerName: '', reflection: '복원할 기록', awaitingSignature: true,
);
CompletionRecord recordFor(GraceDraft draft, [int seconds = 0]) => CompletionRecord(
  id: draft.id, courseNumber: draft.courseNumber, courseTitle: draft.courseTitle,
  participationMode: draft.participationMode, myName: draft.myName,
  partnerName: draft.partnerName,
  completedAt: DateTime(2026, 10, 10, 10, 0, seconds + 1),
  mySignedAt: DateTime(2026, 10, 10, 10, 0, seconds), partnerSignedAt: null,
  graceReflection: draft.reflection, graceReflectionPending: false,
);
Future<void> settleUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try { await initializeStorage(); }
    finally { debugDefaultTargetPlatformOverride = null; }
  });
  setUp(() async {
    await graceDraftRepository.load();
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
  });
  test('first durable signature survives stale autosave and later attempt', () async {
    final repo = GraceDraftRepository();
    final draft = fixture();
    final first = recordFor(draft);
    await repo.save(draft.copy(pendingRecord: first));
    await repo.save(draft);
    final restored = await repo.prepareCompletion(draft, recordFor(draft, 8));
    expect(restored.toJson(), first.toJson());
  });
  test('signature stage cannot regress to reflection by delayed save', () async {
    final repo = GraceDraftRepository();
    await repo.save(fixture());
    await repo.save(fixture().copy(awaitingSignature: false));
    expect((await repo.load())!.awaitingSignature, isTrue);
  });
  test('completed session cannot be resurrected by delayed autosave', () async {
    final repo = GraceDraftRepository();
    await repo.save(fixture());
    await repo.clearIfId(fixture().id);
    await expectLater(repo.save(fixture()), throwsStateError);
    expect(await repo.load(), isNull);
  });
  test('same ID with changed reflection preserves original pending record', () async {
    final repo = GraceDraftRepository();
    final original = recordFor(fixture());
    await repo.save(fixture().copy(pendingRecord: original));
    await expectLater(repo.save(fixture().copy(reflection: '다른 내용')), throwsStateError);
    expect((await repo.load())!.pendingRecord!.toJson(), original.toJson());
  });
  test('first completion keeps timestamps and rejects payload conflict', () async {
    final repo = CompletionRepository();
    final first = recordFor(fixture());
    await repo.add(first);
    await repo.add(recordFor(fixture(), 8));
    await expectLater(repo.add(first.withGraceReflection('다른 내용')), throwsStateError);
    expect((await repo.loadAll()).single.toJson(), first.toJson());
  });
  testWidgets('home recovers committed record even if pending signature was lost', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await graceDraftRepository.save(fixture());
      await completionRepository.add(recordFor(fixture()));
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await settleUntil(tester, find.byType(ProgressCard));
    expect(await tester.runAsync(() => graceDraftRepository.load()), isNull);
    expect(find.text('마무리하지 않은 은혜 기록'), findsNothing);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(
      ElevatedButton, '문답 시작하기')).onPressed, isNotNull);
  });
  testWidgets('resume reflection finish builds fresh home and clears resume card', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => graceDraftRepository.save(
      fixture().copy(awaitingSignature: false)));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await settleUntil(tester, find.text('은혜 기록 이어쓰기'));
    await tester.tap(find.text('은혜 기록 이어쓰기'));
    await settleUntil(tester, find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('은혜 기록하고 서명하기'));
    await tester.tap(find.text('은혜 기록하고 서명하기'));
    await settleUntil(tester, find.text('서명하기'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('서명하기'));
    expect(find.text('서명하기').hitTestable(), findsOneWidget);
    await tester.tap(find.text('서명하기').hitTestable());
    await tester.pump();
    expect(find.text('서명됨'), findsOneWidget);
    final finishButton = find.widgetWithText(
      FilledButton, '서명 완료하고 마무리');
    expect(tester.widget<FilledButton>(finishButton).onPressed, isNotNull);
    await tester.ensureVisible(finishButton);
    await tester.tap(finishButton.hitTestable());
    await settleUntil(tester, find.byType(ProgressCard));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CompletionSignaturePage), findsNothing);
    expect(await tester.runAsync(() => graceDraftRepository.load()), isNull);
    expect((await tester.runAsync(() => completionRepository.loadAll()))!.length, 1);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(
      ElevatedButton, '문답 시작하기')).onPressed, isNotNull);
  });
}
