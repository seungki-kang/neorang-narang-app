import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
  }
  expect(finder, findsOneWidget);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder.hitTestable());
  await tester.pump();
}

Future<void> openHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: HomePage()));
  await waitFor(tester, find.byType(ProgressCard));
}

QuestionDraft pendingQuestion() => QuestionDraft(
  courseNumber: 1,
  courseTitle: '다 끝났다',
  participationMode: ParticipationMode.solo,
  myDisplayName: '진행참여자',
  partnerDisplayName: '',
  firstAskerIsMe: true,
  currentQuestionIndex: 3,
  savedAt: DateTime(2026, 11, 5),
);

void main() {
  setUpAll(() {
    completionRepository = CompletionRepository();
    questionDraftRepository = QuestionDraftRepository();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> remember(WidgetTester tester) async {
    await tester.runAsync(() async {
      await ParticipantPreferencesRepository().remember('샘플본인', '샘플상대');
    });
  }

  testWidgets('first use retains guide and participant setup', (tester) async {
    await openHome(tester);
    expect(find.text('혼자 하기'), findsNothing);
    await tapText(tester, '문답 시작하기');
    await waitFor(tester, find.byType(UsageGuidePage));
    await tapText(tester, '문답 방법 선택하기');
    await waitFor(tester, find.byType(ParticipantSetupPage));
  });

  testWidgets('solo quick start reuses own name without stale partner',
      (tester) async {
    await remember(tester);
    await openHome(tester);
    await waitFor(tester, find.text('혼자 하기'));
    await tapText(tester, '혼자 하기');
    await waitFor(tester, find.byType(CourseSelectionPage));
    final page = tester.widget<CourseSelectionPage>(find.byType(CourseSelectionPage));
    expect(page.myName, '샘플본인');
    expect(page.partnerName, isEmpty);
    expect(page.participationMode, ParticipationMode.solo);
    expect(await tester.runAsync(() => completionRepository.loadAll()), isEmpty);
  });

  testWidgets('together requires explicit partner selection; cancel changes nothing',
      (tester) async {
    await remember(tester);
    await openHome(tester);
    await waitFor(tester, find.text('함께 하기'));
    await tapText(tester, '함께 하기');
    await waitFor(tester, find.byKey(const ValueKey('together-partner-name')));
    expect(find.byType(CourseSelectionPage), findsNothing);
    Navigator.of(tester.element(find.byType(ParticipantSetupPage))).pop();
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ParticipantSetupPage).evaluate().isEmpty &&
          find.text('함께 하기').hitTestable().evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byType(ParticipantSetupPage), findsNothing);
    final before = await tester.runAsync(() => ParticipantPreferencesRepository().load());
    expect(before!.recentPartners, ['샘플상대']);
    await tapText(tester, '함께 하기');
    await waitFor(tester, find.byKey(const ValueKey('together-partner-name')));
    await tapText(tester, '샘플상대');
    expect(find.byType(CourseSelectionPage), findsNothing);
    await tapText(tester, '함께 시작');
    await waitFor(tester, find.byType(CourseSelectionPage));
    final page = tester.widget<CourseSelectionPage>(find.byType(CourseSelectionPage));
    expect(page.partnerName, '샘플상대');
    expect(page.participationMode, ParticipationMode.together);
  });

  testWidgets('pending question suppresses shortcuts without losing position',
      (tester) async {
    await remember(tester);
    await tester.runAsync(() => questionDraftRepository.save(pendingQuestion()));
    await openHome(tester);
    expect(find.byKey(const ValueKey('home-quick-start')), findsNothing);
    final draft = await tester.runAsync(() => questionDraftRepository.load());
    expect(draft!.currentQuestionIndex, 3);
  });

  testWidgets('pending grace suppresses shortcuts and remains unchanged',
      (tester) async {
    await remember(tester);
    const grace = GraceDraft(
      id: 'quick-grace-only', courseNumber: 1, courseTitle: '다 끝났다',
      participationMode: ParticipationMode.solo, myName: '샘플본인',
      partnerName: '', reflection: '합성 초안',
    );
    await tester.runAsync(() => graceDraftRepository.save(grace));
    await openHome(tester);
    expect(find.byKey(const ValueKey('home-quick-start')), findsNothing);
    expect(find.text('은혜 기록 이어쓰기'), findsOneWidget);
    final draft = await tester.runAsync(() => graceDraftRepository.load());
    expect(draft!.toJson(), grace.toJson());
  });

  testWidgets('draft created after home load blocks shortcut navigation',
      (tester) async {
    await remember(tester);
    await openHome(tester);
    await waitFor(tester, find.text('혼자 하기'));
    await tester.runAsync(() => questionDraftRepository.save(pendingQuestion()));
    await tapText(tester, '혼자 하기');
    await waitFor(tester, find.text('진행 중인 기록을 먼저 이어서 마무리해 주세요.'));
    expect(find.byType(CourseSelectionPage), findsNothing);
    final draft = await tester.runAsync(() => questionDraftRepository.load());
    expect(draft!.currentQuestionIndex, 3);
  });

  testWidgets('corrupt participant preferences do not block history or get overwritten',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ParticipantPreferencesRepository.storageKey: '{broken',
    });
    await openHome(tester);
    await waitFor(tester, find.text('이름 다시 불러오기'));
    expect(find.text('혼자 하기'), findsNothing);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getString(ParticipantPreferencesRepository.storageKey), '{broken');
    await tapText(tester, '나의 문답 기록');
    await waitFor(tester, find.byType(CompletionHistoryPage));
  });

  testWidgets('rapid solo taps open only one course route and preserve preferences',
      (tester) async {
    await remember(tester);
    await openHome(tester);
    await waitFor(tester, find.text('혼자 하기'));
    final finder = find.text('혼자 하기');
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.tap(finder);
    await waitFor(tester, find.byType(CourseSelectionPage));
    Navigator.of(tester.element(find.byType(CourseSelectionPage))).pop();
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CourseSelectionPage).evaluate().isEmpty &&
          find.byKey(const ValueKey('home-quick-start')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byType(CourseSelectionPage), findsNothing);
    expect(find.byKey(const ValueKey('home-quick-start')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '혼자 하기'),
      ).onPressed,
      isNotNull,
    );
    final value = await tester.runAsync(() => ParticipantPreferencesRepository().load());
    expect(jsonEncode(value!.recentPartners), jsonEncode(['샘플상대']));
  });
}
