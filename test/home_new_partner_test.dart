import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

Future<void> waitUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
  }
  expect(ready(), isTrue);
}

Future<void> tapLabel(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder.hitTestable());
  await tester.pump();
}

void main() {
  setUpAll(() {
    completionRepository = CompletionRepository();
    questionDraftRepository = QuestionDraftRepository();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, {bool recent = true}) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => ParticipantPreferencesRepository()
        .remember('샘플본인', recent ? '샘플상대' : null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await waitUntil(tester, () => find.text('함께 하기').evaluate().isNotEmpty);
  }

  testWidgets('new partner opens together with own name and blank partner; cancel preserves preferences', (tester) async {
    await open(tester);
    final before = await tester.runAsync(() => ParticipantPreferencesRepository().load());
    await tapLabel(tester, '함께 하기');
    await waitUntil(tester, () => find.byKey(const ValueKey('together-partner-name')).evaluate().isNotEmpty);
    expect(find.text('내 이름: 샘플본인'), findsWidgets);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(tester.widget<ParticipantSetupPage>(find.byType(ParticipantSetupPage)).initialMode,
        ParticipationMode.together);
    Navigator.of(tester.element(find.byType(ParticipantSetupPage))).pop();
    await waitUntil(tester, () => find.byType(ParticipantSetupPage).evaluate().isEmpty &&
        find.text('함께 하기').hitTestable().evaluate().isNotEmpty);
    final after = await tester.runAsync(() => ParticipantPreferencesRepository().load());
    expect(after!.myName, before!.myName);
    expect(after.recentPartners, before.recentPartners);
    expect(await tester.runAsync(() => completionRepository.loadAll()), isEmpty);
  });

  testWidgets('first partner requires a name and reaches together course selection', (tester) async {
    await open(tester, recent: false);
    expect(find.text('최근 함께한 분'), findsNothing);
    await tapLabel(tester, '함께 하기');
    await waitUntil(tester, () => find.byKey(const ValueKey('together-partner-name')).evaluate().isNotEmpty);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '함께 시작')).onPressed, isNull);
    expect(find.byType(CourseSelectionPage), findsNothing);
    await tester.enterText(find.byType(TextField).last, '새샘플상대');
    await tapLabel(tester, '함께 시작');
    await waitUntil(tester, () => find.byType(CourseSelectionPage).evaluate().isNotEmpty);
    final page = tester.widget<CourseSelectionPage>(find.byType(CourseSelectionPage));
    expect(page.myName, '샘플본인');
    expect(page.partnerName, '새샘플상대');
    expect(page.participationMode, ParticipationMode.together);
    final people = await tester.runAsync(() => ParticipantPreferencesRepository().load());
    expect(people!.recentPartners, ['새샘플상대']);
  });

  testWidgets('new partner rechecks drafts before opening setup', (tester) async {
    await open(tester);
    await tester.runAsync(() => questionDraftRepository.save(QuestionDraft(
      courseNumber: 1, courseTitle: '다 끝났다',
      participationMode: ParticipationMode.solo,
      myDisplayName: '샘플본인', partnerDisplayName: '', firstAskerIsMe: true,
      currentQuestionIndex: 3, savedAt: DateTime(2026, 11, 5),
    )));
    await tapLabel(tester, '함께 하기');
    await waitUntil(tester, () => find.text('진행 중인 기록을 먼저 이어서 마무리해 주세요.').evaluate().isNotEmpty);
    expect(find.byType(ParticipantSetupPage), findsNothing);
    final draft = await tester.runAsync(() => questionDraftRepository.load());
    expect(draft!.currentQuestionIndex, 3);
  });

  testWidgets('recent selection needs confirmation and edited name takes precedence', (tester) async {
    await open(tester);
    await tapLabel(tester, '함께 하기');
    await waitUntil(tester, () => find.byType(TextField).evaluate().isNotEmpty);
    final recent = find.widgetWithText(ListTile, '샘플상대');
    await tester.ensureVisible(recent);
    await tester.tap(recent.hitTestable());
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '샘플상대');
    expect(find.byType(CourseSelectionPage), findsNothing);
    await tester.enterText(find.byType(TextField), '다른샘플');
    await tapLabel(tester, '함께 시작');
    await waitUntil(tester, () => find.byType(CourseSelectionPage).evaluate().isNotEmpty);
    expect(tester.widget<CourseSelectionPage>(find.byType(CourseSelectionPage)).partnerName, '다른샘플');
    final people = await tester.runAsync(() => ParticipantPreferencesRepository().load());
    expect(people!.recentPartners, ['다른샘플', '샘플상대']);
  });

  testWidgets('draft created while choosing together prevents saving names', (tester) async {
    await open(tester);
    await tapLabel(tester, '함께 하기');
    await waitUntil(tester, () => find.byType(TextField).evaluate().isNotEmpty);
    await tester.enterText(find.byType(TextField), '저장안할샘플');
    await tester.runAsync(() => questionDraftRepository.save(QuestionDraft(
      courseNumber: 1, courseTitle: '다 끝났다',
      participationMode: ParticipationMode.solo,
      myDisplayName: '샘플본인', partnerDisplayName: '', firstAskerIsMe: true,
      currentQuestionIndex: 3, savedAt: DateTime(2026, 11, 5),
    )));
    await tapLabel(tester, '함께 시작');
    await waitUntil(tester, () => find.text('진행 중인 기록을 먼저 이어서 마무리해 주세요.').evaluate().isNotEmpty);
    expect(find.byType(CourseSelectionPage), findsNothing);
    final people = await tester.runAsync(() => ParticipantPreferencesRepository().load());
    expect(people!.recentPartners, ['샘플상대']);
  });

  testWidgets('rapid together taps open one course; recent name stays unique', (tester) async {
    await open(tester);
    await tapLabel(tester, '함께 하기');
    await waitUntil(tester, () => find.byType(TextField).evaluate().isNotEmpty);
    await tester.enterText(find.byType(TextField), '샘플상대');
    final button = find.widgetWithText(ElevatedButton, '함께 시작');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button.hitTestable());
    await tester.tap(button.hitTestable());
    await waitUntil(tester, () => find.byType(CourseSelectionPage).evaluate().isNotEmpty);
    Navigator.of(tester.element(find.byType(CourseSelectionPage))).pop();
    await waitUntil(tester, () => find.byType(CourseSelectionPage).evaluate().isEmpty &&
        find.byType(ParticipantSetupPage).evaluate().isNotEmpty);
    expect(find.byType(CourseSelectionPage), findsNothing);
    final people = await tester.runAsync(() => ParticipantPreferencesRepository().load());
    expect(people!.recentPartners, ['샘플상대']);
  });

}
