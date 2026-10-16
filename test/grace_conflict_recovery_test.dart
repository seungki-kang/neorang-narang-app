import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

GraceDraft conflictDraft() => GraceDraft(
  id: 'recovery-fixture', courseNumber: 1, courseTitle: '다 끝났다',
  participationMode: ParticipationMode.solo, myName: '테스트', partnerName: '',
  reflection: '대기 내용', awaitingSignature: true,
  pendingRecord: conflictRecord().withGraceReflection('대기 내용'),
);
CompletionRecord conflictRecord() => CompletionRecord(
  id: 'recovery-fixture', courseNumber: 1, courseTitle: '다 끝났다',
  participationMode: ParticipationMode.solo, myName: '테스트', partnerName: '',
  completedAt: DateTime(2026, 10, 10, 1), mySignedAt: DateTime(2026, 10, 10),
  partnerSignedAt: null, graceReflection: '완료 내용', graceReflectionPending: false,
);
class FailingRecoveryStore extends CompletionRepository {
  @override
  Future<void> saveGraceReflection(String recordId, String reflection) async {
    throw StateError('injected_write_failure');
  }
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
  Future<void> seed(CompletionStore store) async {
    await graceDraftRepository.save(conflictDraft());
    await store.add(conflictRecord());
  }
  test('keep saved preserves both originals and clears unfinished draft', () async {
    final store = CompletionRepository();
    await seed(store);
    await GraceConflictRecovery.resolve(draft: conflictDraft(),
      saved: conflictRecord(), useDraft: false, store: store);
    expect((await store.loadAll()).single.toJson(), conflictRecord().toJson());
    expect(await graceDraftRepository.load(), isNull);
    final archive = (await GraceConflictRecovery.archives()).single;
    expect(archive['saved'], conflictRecord().toJson());
    expect(archive['draft'], conflictDraft().toJson());
  });
  test('select pending changes only reflection without adding a completion', () async {
    final store = CompletionRepository();
    await seed(store);
    await GraceConflictRecovery.resolve(draft: conflictDraft(),
      saved: conflictRecord(), useDraft: true, store: store);
    expect((await store.loadAll()).single.toJson(),
      conflictRecord().withGraceReflection('대기 내용').toJson());
    expect(await graceDraftRepository.load(), isNull);
    expect((await GraceConflictRecovery.archives()).single['choice'], 'draft');
  });
  test('failed replacement preserves original completion draft and archive', () async {
    final store = FailingRecoveryStore();
    await seed(store);
    await expectLater(GraceConflictRecovery.resolve(draft: conflictDraft(),
      saved: conflictRecord(), useDraft: true, store: store), throwsStateError);
    expect((await store.loadAll()).single.toJson(), conflictRecord().toJson());
    expect((await graceDraftRepository.load())!.toJson(), conflictDraft().toJson());
    expect((await GraceConflictRecovery.archives()).length, 1);
  });
  test('corrupt archive prevents writes and cleanup and preserves raw', () async {
    final store = CompletionRepository();
    await seed(store);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(GraceConflictRecovery.archiveKey, '{broken');
    await expectLater(GraceConflictRecovery.resolve(draft: conflictDraft(),
      saved: conflictRecord(), useDraft: true, store: store),
      throwsA(isA<StorageReadException>()));
    expect(prefs.getString(GraceConflictRecovery.archiveKey), '{broken');
    expect((await store.loadAll()).single.toJson(), conflictRecord().toJson());
    expect(await graceDraftRepository.load(), isNotNull);
  });
  testWidgets('home shows recovery action instead of generic read failure', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => seed(completionRepository));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('두 기록 비교하고 복구하기').evaluate().isNotEmpty) break;
    }
    expect(find.text('두 기록 비교하고 복구하기'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('두 기록 비교하고 복구하기'));
    await tester.tap(find.text('두 기록 비교하고 복구하기'));
    await tester.pump(const Duration(milliseconds: 500));
     // NN-RECOVERY-WAIT: wait for the pushed route to appear.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(GraceConflictPage).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GraceConflictPage), findsOneWidget);
    expect(find.text('완료 내용'), findsOneWidget);
    expect(find.text('대기 내용'), findsOneWidget);
  });
}
