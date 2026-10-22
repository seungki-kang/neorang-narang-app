import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';
import '../support/operations_contract.dart';
import '../support/operations_widget.dart';

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
  for (final useDraft in [false, true]) {
    testWidgets('recovery selection reaches fresh home without duplicate count useDraft=$useDraft', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = operationsRecord('widget-conflict', text: 'fixture saved');
      final pending = saved.withGraceReflection('fixture pending');
      final draft = GraceDraft(id: saved.id, courseNumber: saved.courseNumber,
          courseTitle: saved.courseTitle, participationMode: saved.participationMode,
          myName: saved.myName, partnerName: saved.partnerName,
          reflection: pending.graceReflection, awaitingSignature: true, pendingRecord: pending);
      await tester.runAsync(() async {
        await completionRepository.add(saved);
        await graceDraftRepository.save(draft);
      });
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tapOperationsWidget(tester, find.text('두 기록 비교하고 복구하기'));
      await waitForOperationsWidget(tester, find.byType(GraceConflictPage));
      await tapOperationsWidget(tester, find.text(useDraft ? '마무리 대기 내용 반영' : '기존 완료 기록 유지'));
      // NN-ROUTE-READY-101
      for (var frame = 0; frame < 100; frame++) {
        await tester.runAsync(() =>
            Future<void>.delayed(const Duration(milliseconds: 2)));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        if (find.byType(HomePage, skipOffstage: false).evaluate().length == 1 &&
            find.byType(GraceConflictPage, skipOffstage: false).evaluate().isEmpty) {
          break;
        }
      }
      expect(find.byType(HomePage, skipOffstage: false), findsOneWidget);
      expect(find.byType(GraceConflictPage, skipOffstage: false), findsNothing);
      final start = find.widgetWithText(ElevatedButton, '문답 시작하기');
      await waitForOperationsWidget(tester, find.byWidgetPredicate(
          (widget) => widget is ElevatedButton && widget.onPressed != null));
      await waitForOperationsWidget(tester, start, hittable: true);
      expect(tester.widget<ElevatedButton>(start).onPressed, isNotNull);
      expect(find.byType(GraceConflictPage), findsNothing);
      expect(find.text('두 기록 비교하고 복구하기'), findsNothing);
      await tester.runAsync(() async {
        final records = await completionRepository.loadAll();
        expect(records, hasLength(1));
        expect(records.single.toJson(), (useDraft ? saved.withGraceReflection(pending.graceReflection) : saved).toJson());
        expect(await graceDraftRepository.load(), isNull);
        final archives = await GraceConflictRecovery.archives();
        if (useDraft) {
          // Current product policy consumes an acknowledged legacy edit.
          expect(archives, isEmpty);
        } else {
          final archive = archives.single;
          expect(archive['saved'], saved.toJson());
          expect(archive['draft'], draft.toJson());
          expect(archive['choice'], 'saved');
        }
      });
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
