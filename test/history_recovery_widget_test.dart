import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

import 'history_recovery_repository_test.dart' show fixture;

class ControlledHistoryStore extends CompletionRepository {
  bool failSave = false;
  bool failDelete = false;
  int retries = 0;
  int deletions = 0;
  Completer<void>? gate;
  Completer<void>? deleteGate;
  @override
  Future<void> retryRecovery(String id) async {
    retries++;
    if (gate != null) await gate!.future;
    if (failSave) throw StateError('injected_save_failure');
    await super.retryRecovery(id);
  }

  @override
  Future<void> deleteById(String id) async {
    deletions++;
    if (deleteGate != null) await deleteGate!.future;
    if (failDelete) throw StateError('injected_delete_failure');
    await super.deleteById(id);
  }
}

Future<void> tick(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 2)),
  );
  await tester.pump(const Duration(milliseconds: 40));
}

Future<void> until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await tick(tester);
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 350));
      return;
    }
  }
  fail('bounded wait exceeded for $finder');
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  for (var i = 0; i < 12; i++) {
    await tick(tester);
  }
}

Future<void> open(WidgetTester tester, ControlledHistoryStore store) async {
  await tester.runAsync(() async {
    await store.add(fixture('a'));
    await store.add(fixture('b', course: 2));
  });
  await tester.pumpWidget(
    MaterialApp(home: CompletionHistoryPage(completionStore: store)),
  );
  await until(tester, find.text('총 2회의 문답을 마쳤습니다.'));
  await until(tester, find.text('다 끝났다'));
  await tap(tester, '다 끝났다');
  await until(tester, find.text('문답 기록 상세'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    completionRepository = CompletionRepository();
    questionDraftRepository = QuestionDraftRepository();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('edit refreshes detail and list preserving identity and dates', (
    tester,
  ) async {
    await size(tester);
    final store = ControlledHistoryStore();
    await open(tester, store);
    await tap(tester, '수정');
    await tester.enterText(find.byType(TextField), '수정한 은혜');
    await tap(tester, '저장');
    expect(find.text('수정한 은혜'), findsOneWidget);
    expect(
      (await tester.runAsync(() => store.findById('a')))!.toJson(),
      fixture('a').withGraceReflection('수정한 은혜').toJson(),
    );
    await tester.pageBack();
    await until(tester, find.text('수정한 은혜'));
    expect(find.text('총 2회의 문답을 마쳤습니다.'), findsOneWidget);
  });
  testWidgets('blank reflection cannot save', (tester) async {
    await size(tester);
    final store = ControlledHistoryStore();
    await open(tester, store);
    await tap(tester, '수정');
    await tester.enterText(find.byType(TextField), '   ');
    await tap(tester, '저장');
    expect(find.textContaining('공백만 저장할 수 없습니다'), findsOneWidget);
    expect(store.retries, 0);
  });
  testWidgets('heart conversion requires confirmation and can change back', (
    tester,
  ) async {
    await size(tester);
    final store = ControlledHistoryStore();
    await open(tester, store);
    await tap(tester, '수정');
    await tap(tester, '마음에 담고 마무리했습니다');
    expect(find.byType(TextField), findsNothing);
    await tap(tester, '저장');
    expect(find.text('마음에 담고 마무리할까요?'), findsOneWidget);
    await tap(tester, '취소');
    expect(
      (await tester.runAsync(() => store.findById('a')))!.graceReflection,
      '기존 은혜',
    );
    await tap(tester, '저장');
    await tap(tester, '변경하고 저장');
    expect(
      (await tester.runAsync(() => store.findById('a')))!.graceReflection,
      isEmpty,
    );
    await tap(tester, '수정');
    await tap(tester, '은혜 기록 남기기');
    await tester.enterText(find.byType(TextField), '다시 기록');
    await tap(tester, '저장');
    expect(find.text('다시 기록'), findsOneWidget);
  });
  testWidgets(
    'failed save retains original input and recovery after recreation',
    (tester) async {
      await size(tester);
      final store = ControlledHistoryStore()..failSave = true;
      await open(tester, store);
      await tap(tester, '수정');
      await tester.enterText(find.byType(TextField), '보존할 입력');
      await tap(tester, '저장');
      expect(find.byKey(const ValueKey('history-error')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '보존할 입력',
      );
      expect(
        (await tester.runAsync(() => store.findById('a')))!.graceReflection,
        '기존 은혜',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(home: UnsavedRecordsPage(store: CompletionRepository())),
      );
      await until(tester, find.text('보존할 입력'));
      expect(find.text('기존 은혜'), findsOneWidget);
      await tap(tester, '다시 저장');
      await tap(tester, '다시 저장');
      await until(tester, find.text('저장되지 않은 기록이 없습니다.'));
      expect(
        await tester.runAsync(() => CompletionRepository().listRecoveries()),
        isEmpty,
      );
      expect((await tester.runAsync(() => store.loadAll()))!.length, 2);
    },
  );
  testWidgets('continuous save taps and back are blocked until commit', (
    tester,
  ) async {
    await size(tester);
    final store = ControlledHistoryStore();
    await open(tester, store);
    await tap(tester, '수정');
    await tester.enterText(find.byType(TextField), '저장 대기');
    store.gate = Completer<void>();
    await tester.tap(find.text('저장'));
    await tester.tap(find.text('저장'));
    for (var i = 0; i < 12; i++) {
      await tick(tester);
    }
    expect(store.retries, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
          .onPressed,
      isNull,
    );
    await Navigator.of(tester.element(find.byType(CompletionDetailPage)))
        .maybePop();
    await tester.pump();
    expect(find.byType(CompletionDetailPage), findsOneWidget);
    store.gate!.complete();
    await until(tester, find.text('수정'));
    expect((await tester.runAsync(() => store.loadAll()))!.length, 2);
  });
  testWidgets('delete cancel changes nothing', (tester) async {
    await size(tester);
    final store = ControlledHistoryStore();
    await open(tester, store);
    await tap(tester, '기록 삭제');
    expect(find.text('문답 기록을 삭제할까요?'), findsOneWidget);
    await tap(tester, '취소');
    expect(store.deletions, 0);
    expect((await tester.runAsync(() => store.loadAll()))!.length, 2);
  });
  testWidgets(
    'successful delete returns to refreshed list only target disappears',
    (tester) async {
      await size(tester);
      final store = ControlledHistoryStore();
      await open(tester, store);
      await tap(tester, '기록 삭제');
      await tap(tester, '기록 삭제');
      await until(tester, find.text('총 1회의 문답을 마쳤습니다.'));
      expect(find.byType(CompletionDetailPage), findsNothing);
      expect(find.text('다 끝났다'), findsNothing);
      expect(find.text('다 이루었다'), findsOneWidget);
    },
  );
  testWidgets('delete failure keeps detail and stored record', (tester) async {
    await size(tester);
    final store = ControlledHistoryStore()..failDelete = true;
    await open(tester, store);
    await tap(tester, '기록 삭제');
    await tap(tester, '기록 삭제');
    expect(find.byType(CompletionDetailPage), findsOneWidget);
    expect(find.textContaining('기록을 삭제하지 못했습니다'), findsOneWidget);
    expect((await tester.runAsync(() => store.loadAll()))!.length, 2);
  });
  testWidgets('temporary discard preserves normal completion', (tester) async {
    await size(tester);
    final store = CompletionRepository();
    await tester.runAsync(() async {
      await store.add(fixture('a'));
      await store.stageRecovery(
        CompletionRecovery(
          before: fixture('a'),
          record: fixture('a', text: '대기'),
          attemptedAt: DateTime(2026),
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: UnsavedRecordsPage(store: store)),
    );
    await until(tester, find.text('대기'));
    await tap(tester, '임시 기록 삭제');
    expect(
      find.text('아직 저장되지 않은 임시 내용만 삭제됩니다. 이미 정상 저장된 완료 기록은 삭제되지 않습니다.'),
      findsOneWidget,
    );
    await tap(tester, '임시 기록 삭제');
    await until(tester, find.text('저장되지 않은 기록이 없습니다.'));
    expect(
      (await tester.runAsync(() => store.findById('a')))!.graceReflection,
      '기존 은혜',
    );
  });
  testWidgets('failed archive retry keeps card and original completion', (
    tester,
  ) async {
    await size(tester);
    final store = ControlledHistoryStore()..failSave = true;
    await tester.runAsync(() async {
      await store.add(fixture('a'));
      await store.stageRecovery(
        CompletionRecovery(
          before: fixture('a'),
          record: fixture('a', text: '실패 대기'),
          attemptedAt: DateTime(2026),
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: UnsavedRecordsPage(store: store)),
    );
    await until(tester, find.text('실패 대기'));
    await tap(tester, '다시 저장');
    await tap(tester, '다시 저장');
    expect(
      find.textContaining('저장을 완료하지 못했습니다. 저장 대기 내용은 유지됩니다.'),
      findsOneWidget,
    );
    expect(find.text('실패 대기'), findsOneWidget);
    expect((await tester.runAsync(() => store.listRecoveries()))!.length, 1);
    expect(
      (await tester.runAsync(() => store.findById('a')))!.graceReflection,
      '기존 은혜',
    );
  });
  testWidgets('delete in progress blocks duplicate action and back', (
    tester,
  ) async {
    await size(tester);
    final store = ControlledHistoryStore();
    await open(tester, store);
    store.deleteGate = Completer<void>();
    await tap(tester, '기록 삭제');
    await tap(tester, '기록 삭제');
    expect(store.deletions, 1);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '기록 삭제'))
          .onPressed,
      isNull,
    );
    await Navigator.of(tester.element(find.byType(CompletionDetailPage)))
        .maybePop();
    await tester.pump();
    expect(find.byType(CompletionDetailPage), findsOneWidget);
    store.deleteGate!.complete();
    await until(tester, find.text('총 1회의 문답을 마쳤습니다.'));
  });
  testWidgets('history deletion refreshes home chapter season after return', (
    tester,
  ) async {
    await size(tester);
    final store = completionRepository as CompletionEditingStore;
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        await store.add(fixture('home$i'));
      }
      await store.add(fixture('chapter2', course: 2));
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await until(tester, find.byType(ProgressCard));
    expect(
      tester
          .widget<ProgressCard>(find.byType(ProgressCard).first)
          .progress
          .season,
      2,
    );
    await tester.tap(find.byTooltip('나의 문답 기록'));
    await until(tester, find.text('총 51회의 문답을 마쳤습니다.'));
    await tap(tester, '다 끝났다');
    await until(tester, find.byType(CompletionDetailPage));
    await tap(tester, '기록 삭제');
    await tap(tester, '기록 삭제');
    await until(tester, find.text('총 50회의 문답을 마쳤습니다.'));
    await tester.pageBack();
    await until(tester, find.byType(ProgressCard));
    final chapter1 = tester
        .widget<ProgressCard>(find.byType(ProgressCard).first)
        .progress;
    final chapter2 = tester
        .widget<ProgressCard>(find.byType(ProgressCard).last)
        .progress;
    expect(chapter1.completedCount, 49);
    expect(chapter1.season, 1);
    expect(chapter1.countInSeason, 49);
    expect(chapter2.completedCount, 1);
  });
  for (final count in [0, 2]) {
    testWidgets('home shows exact pending count only when present: $count', (
      tester,
    ) async {
      await size(tester);
      final store = completionRepository as CompletionEditingStore;
      await tester.runAsync(() async {
        for (var i = 0; i < count; i++) {
          await store.stageRecovery(
            CompletionRecovery(
              record: fixture('pending$i'),
              attemptedAt: DateTime(2026),
            ),
          );
        }
      });
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await until(tester, find.byType(ProgressCard));
      expect(
        find.byTooltip('저장되지 않은 기록 $count개'),
        count == 0 ? findsNothing : findsOneWidget,
      );
      if (count == 0) expect(find.textContaining('저장되지 않은 기록'), findsNothing);
    });
  }
}
