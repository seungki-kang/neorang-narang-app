import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

import 'history_recovery_repository_test.dart' show fixture;
import 'history_recovery_widget_test.dart' show tap, until;

class GatedTrashStore extends CompletionRepository {
  Completer<void>? gate;
  bool conflict = false;
  bool fail = false;
  int restores = 0;
  @override
  Future<void> restoreTrash(String id) async {
    restores++;
    await gate?.future;
    if (conflict) throw StateError('restore_conflict');
    if (fail) throw StateError('injected');
    await super.restoreTrash(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  setUpAll(() {
    completionRepository = CompletionRepository();
    questionDraftRepository = QuestionDraftRepository();
  });

  Future<void> prepare(WidgetTester tester, CompletionRepository store) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await store.add(fixture('a'));
      await store.deleteById('a');
    });
  }

  testWidgets(
    'separate trash route restores original and refreshes history count',
    (tester) async {
      final store = CompletionRepository();
      await prepare(tester, store);
      await tester.pumpWidget(
        MaterialApp(home: CompletionHistoryPage(completionStore: store)),
      );
      await until(tester, find.text('총 0회의 문답을 마쳤습니다.'));
      expect(find.byTooltip('저장되지 않은 기록 1개'), findsNothing);
      await tester.tap(find.byTooltip('복구 보관함'));
      await until(tester, find.text('복원'));
      expect(find.byType(UnsavedRecordsPage), findsNothing);
      expect(find.text('다시 저장'), findsNothing);
      await tap(tester, '복원');
      await until(tester, find.text('복원할 삭제 기록이 없습니다.'));
      await tester.pageBack();
      await until(tester, find.text('총 1회의 문답을 마쳤습니다.'));
      expect(
        (await tester.runAsync(() => store.findById('a')))!.toJson(),
        fixture('a').toJson(),
      );
    },
  );

  testWidgets(
    'permanent deletion requires confirmation cancel preserves snapshot',
    (tester) async {
      final store = CompletionRepository();
      await prepare(tester, store);
      await tester.pumpWidget(
        MaterialApp(home: DeletedRecordsPage(store: store)),
      );
      await until(tester, find.text('영구 삭제'));
      await tap(tester, '영구 삭제');
      expect(find.text('이 기록을 영구 삭제할까요?'), findsOneWidget);
      await tap(tester, '취소');
      expect((await tester.runAsync(() => store.listTrash()))!, hasLength(1));
      await tap(tester, '영구 삭제');
      await tap(tester, '영구 삭제 확인');
      await until(tester, find.text('복원할 삭제 기록이 없습니다.'));
      expect(await tester.runAsync(() => store.wasDeleted('a')), isTrue);
      await tester.runAsync(() async {
        await expectLater(store.add(fixture('a')), throwsStateError);
      });
    },
  );

  testWidgets(
    'restore conflict is explicit and does not remove archived entry',
    (tester) async {
      final store = GatedTrashStore()..conflict = true;
      await prepare(tester, store);
      await tester.pumpWidget(
        MaterialApp(home: DeletedRecordsPage(store: store)),
      );
      await until(tester, find.text('복원'));
      await tap(tester, '복원');
      expect(find.textContaining('동일한 ID'), findsOneWidget);
      expect((await tester.runAsync(() => store.listTrash()))!, hasLength(1));
    },
  );

  testWidgets(
    'busy restore blocks duplicate actions and back failure allows retry',
    (tester) async {
      final store = GatedTrashStore()
        ..gate = Completer<void>()
        ..fail = true;
      await prepare(tester, store);
      await tester.pumpWidget(
        MaterialApp(home: DeletedRecordsPage(store: store)),
      );
      await until(tester, find.text('복원'));
      await tap(tester, '복원');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '복원'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '영구 삭제'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      expect(store.restores, 1);
      store.gate!.complete();
      await until(tester, find.byKey(const ValueKey('trash-error')));
      expect((await tester.runAsync(() => store.listTrash()))!, hasLength(1));
      store.fail = false;
      await tap(tester, '복원');
      await until(tester, find.text('복원할 삭제 기록이 없습니다.'));
    },
  );

  testWidgets('tombstone without snapshot never presents restore button', (
    tester,
  ) async {
    final store = CompletionRepository();
    await tester.runAsync(() => store.permanentlyDeleteTrash('old-deleted'));
    await tester.pumpWidget(
      MaterialApp(home: DeletedRecordsPage(store: store)),
    );
    await until(tester, find.text('복원할 삭제 기록이 없습니다.'));
    expect(find.text('복원'), findsNothing);
  });
}
