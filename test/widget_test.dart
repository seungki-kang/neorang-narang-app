import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neorang_narang_app/main.dart';

class ControlledCompletionStore implements CompletionStore {
  final List<CompletionRecord> attempts = [];
  final Map<String, CompletionRecord> persisted = {};
  bool failFirstAfterWrite = false;
  Completer<void>? gate;

  @override
  Future<void> add(CompletionRecord record) async {
    attempts.add(record);
    if (gate != null) await gate!.future;
    persisted.putIfAbsent(record.id, () => record);
    if (failFirstAfterWrite && attempts.length == 1) {
      throw StateError('simulated acknowledgement failure');
    }
  }

  @override
  Future<List<CompletionRecord>> loadAll() async => persisted.values.toList();
  @override
  Future<int> countForCourse(int courseNumber) async => persisted.values
      .where((record) => record.courseNumber == courseNumber)
      .length;
  @override
  Future<List<CompletionRecord>> pendingGraceRecords() async => [];
  @override
  Future<void> saveGraceReflection(String recordId, String reflection) async {}
}

Future<void> openSignature(
  WidgetTester tester,
  ControlledCompletionStore store,
) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CompletionSignaturePage(
                    courseNumber: 1,
                    courseTitle: '테스트 과정',
                    participationMode: ParticipationMode.solo,
                    myName: '테스트 참여자',
                    partnerName: '',
                    graceReflection: '보존할 은혜 기록',
                    graceReflectionPending: false,
                    completionStore: store,
                  ),
                ),
              ),
              child: const Text('시작'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('시작'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unsigned completion cannot be saved', (tester) async {
    final store = ControlledCompletionStore();
    await openSignature(tester, store);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '서명 완료하고 마무리'),
    );
    expect(button.onPressed, isNull);
    expect(store.attempts, isEmpty);
  });

  testWidgets('failed acknowledgement preserves content and retries once', (
    tester,
  ) async {
    final store = ControlledCompletionStore()..failFirstAfterWrite = true;
    await openSignature(tester, store);
    await tester.tap(find.text('서명하기'));
    await tester.pump();
    await tester.tap(find.text('서명 완료하고 마무리'));
    await tester.pumpAndSettle();
    expect(find.textContaining('기록을 저장하지 못했습니다.'), findsOneWidget);
    expect(find.text('서명됨'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(store.attempts, hasLength(1));
    await tester.tap(find.text('서명 완료하고 마무리'));
    await tester.pumpAndSettle();
    expect(store.attempts, hasLength(2));
    expect(store.attempts.last.id, store.attempts.first.id);
    expect(store.attempts.last.mySignedAt, store.attempts.first.mySignedAt);
    expect(store.attempts.last.graceReflection, '보존할 은혜 기록');
    expect(store.persisted, hasLength(1));
    expect(find.text('시작'), findsOneWidget);
    expect(find.byType(CompletionSignaturePage), findsNothing);
  });

  testWidgets('pending save blocks duplicate taps and leaving the screen', (
    tester,
  ) async {
    final store = ControlledCompletionStore()..gate = Completer<void>();
    await openSignature(tester, store);
    await tester.tap(find.text('서명하기'));
    await tester.pump();
    await tester.tap(find.text('서명 완료하고 마무리'));
    await tester.tap(find.text('서명 완료하고 마무리'));
    await tester.pump();
    expect(store.attempts, hasLength(1));
    final context = tester.element(find.byType(CompletionSignaturePage));
    await Navigator.of(context).maybePop();
    await tester.pump();
    expect(find.byType(CompletionSignaturePage), findsOneWidget);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(store.persisted, hasLength(1));
    expect(find.byType(CompletionSignaturePage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed screen does not update after delayed save', (
    tester,
  ) async {
    final store = ControlledCompletionStore()..gate = Completer<void>();
    await openSignature(tester, store);
    await tester.tap(find.text('서명하기'));
    await tester.pump();
    await tester.tap(find.text('서명 완료하고 마무리'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('다른 화면')));
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('다른 화면'), findsOneWidget);
  });
}
