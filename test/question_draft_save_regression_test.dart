import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

class ControlledDraftStore implements QuestionDraftStore {
  QuestionDraft? persisted;
  final attempts = <QuestionDraft>[];
  bool fail = false;
  bool failAfterWrite = false;
  Completer<void>? gate;
  @override
  Future<QuestionDraft?> load() async => persisted;
  @override
  Future<void> clear() async {
    persisted = null;
  }

  @override
  Future<void> save(QuestionDraft draft) async {
    attempts.add(draft);
    if (gate != null) await gate!.future;
    if (fail) throw StateError('injected_write_failure');
    persisted = draft;
    if (failAfterWrite) throw StateError('injected_ack_failure');
  }
}

Future<void> openQuestions(
  WidgetTester tester,
  ControlledDraftStore store, {
  int index = 0,
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => QuestionPage(
                  courseNumber: 1,
                  courseTitle: '다 끝났다',
                  participationMode: ParticipationMode.together,
                  myName: '원래 이름',
                  myHonorific: '',
                  partnerName: '상대 이름',
                  partnerHonorific: '',
                  firstAskerIsMe: true,
                  initialQuestionIndex: index,
                  draftStore: store,
                ),
              ),
            ),
            child: const Text('테스트 시작'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('테스트 시작'));
  await tester.pumpAndSettle();
}

Future<void> drain(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          null,
        );
  });
  testWidgets('initial draft failure retries exact draft and blocks progress', (
    tester,
  ) async {
    final store = ControlledDraftStore()..fail = true;
    await openQuestions(tester, store);
    expect(find.byKey(const ValueKey('question-save-error')), findsOneWidget);
    expect(store.persisted, isNull);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, '선포 완료 · 다음'),
          )
          .onPressed,
      isNull,
    );
    store.fail = false;
    await tester.tap(find.text('다시 저장'));
    await tester.pumpAndSettle();
    expect(identical(store.attempts[0], store.attempts[1]), isTrue);
    expect(store.persisted!.currentQuestionIndex, 0);
    expect(find.byKey(const ValueKey('question-save-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final forward in [true, false]) {
    testWidgets(
      'failed movement preserves position and retry moves once: $forward',
      (tester) async {
        final store = ControlledDraftStore();
        await openQuestions(tester, store, index: 1);
        store.fail = true;
        await tester.tap(find.text(forward ? '선포 완료 · 다음' : '이전'));
        await tester.pumpAndSettle();
        expect(find.text('2 / 45'), findsOneWidget);
        expect(store.persisted!.currentQuestionIndex, 1);
        store.fail = false;
        await tester.tap(find.text('다시 저장'));
        await tester.pumpAndSettle();
        final expected = forward ? 2 : 0;
        expect(store.persisted!.currentQuestionIndex, expected);
        expect(find.text('${expected + 1} / 45'), findsOneWidget);
        expect(identical(store.attempts[1], store.attempts[2]), isTrue);
      },
    );
  }
  testWidgets('failed name edit retains both inputs until retry', (
    tester,
  ) async {
    final store = ControlledDraftStore();
    await openQuestions(tester, store);
    await tester.tap(find.byTooltip('이름과 호칭 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '수정한 나');
    await tester.enterText(find.byType(TextField).at(1), '수정한 상대');
    store.fail = true;
    await tester.tap(find.text('수정 적용'));
    await tester.pumpAndSettle();
    expect(store.persisted!.myDisplayName, '원래 이름');
    expect(store.persisted!.partnerDisplayName, '상대 이름');
    expect(find.text('저장 대기 이름: 수정한 나 수정한 상대'), findsOneWidget);
    store.fail = false;
    await tester.tap(find.text('다시 저장'));
    await tester.pumpAndSettle();
    expect(store.persisted!.myDisplayName, '수정한 나');
    expect(store.persisted!.partnerDisplayName, '수정한 상대');
    expect(find.text('묻는 사람: 수정한 나'), findsOneWidget);
  });
  testWidgets('failed exit stays on question and retry saves before leaving', (
    tester,
  ) async {
    final store = ControlledDraftStore();
    await openQuestions(tester, store, index: 2);
    await tester.tap(find.byTooltip('저장하고 나가기'));
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.tap(find.text('저장하고 나가기'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestionPage), findsOneWidget);
    expect(store.persisted!.currentQuestionIndex, 2);
    store.fail = false;
    await tester.tap(find.text('다시 저장'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestionPage), findsNothing);
    expect(find.text('테스트 시작'), findsOneWidget);
  });
  testWidgets('pending draft save blocks duplicate movement edit and back', (
    tester,
  ) async {
    final store = ControlledDraftStore();
    await openQuestions(tester, store);
    store.gate = Completer<void>();
    await tester.tap(find.text('선포 완료 · 다음'));
    await tester.tap(find.text('선포 완료 · 다음'));
    await tester.pump();
    expect(store.attempts, hasLength(2));
    expect(find.text('1 / 45'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '이름과 호칭 수정',
            ),
          )
          .onPressed,
      isNull,
    );
    await Navigator.of(tester.element(find.byType(QuestionPage))).maybePop();
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(QuestionPage), findsOneWidget);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('2 / 45'), findsOneWidget);
    expect(store.persisted!.currentQuestionIndex, 1);
  });
  testWidgets('write acknowledgement failure reads back committed position', (
    tester,
  ) async {
    final store = ControlledDraftStore();
    await openQuestions(tester, store);
    store.failAfterWrite = true;
    await tester.tap(find.text('선포 완료 · 다음'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 45'), findsOneWidget);
    expect(find.byKey(const ValueKey('question-save-error')), findsNothing);
    expect(store.persisted!.currentQuestionIndex, 1);
  });
  testWidgets('disposed question ignores delayed save result', (tester) async {
    final store = ControlledDraftStore();
    await openQuestions(tester, store);
    store.gate = Completer<void>();
    await tester.tap(find.text('선포 완료 · 다음'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('다른 화면')));
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final mode in ['empty', 'question', 'grace', 'corrupt']) {
    testWidgets('home archive opens independently of drafts: $mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        if (mode == 'question') {
          await questionDraftRepository.save(
            QuestionDraft(
              courseNumber: 1,
              courseTitle: '다 끝났다',
              participationMode: ParticipationMode.solo,
              myDisplayName: '나',
              partnerDisplayName: '',
              firstAskerIsMe: true,
              currentQuestionIndex: 0,
              savedAt: DateTime(2026),
            ),
          );
        } else if (mode == 'grace') {
          await graceDraftRepository.save(
            const GraceDraft(
              id: 'archive-test',
              courseNumber: 1,
              courseTitle: '다 끝났다',
              participationMode: ParticipationMode.solo,
              myName: '나',
              partnerName: '',
            ),
          );
        } else if (mode == 'corrupt') {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('neorang_narang_question_draft_v1', '{broken');
        }
      });
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await drain(tester);
      expect(find.byTooltip('복구 보관함'), findsOneWidget);
      await tester.tap(find.byTooltip('복구 보관함'));
      await drain(tester);
      expect(find.byType(GraceRecoveryArchivePage), findsOneWidget);
      expect(find.text('복구 보관 기록이 없습니다.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
}
