import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('grace text disables skipping and clearing enables it',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: GraceReflectionPage(
      courseNumber: 1, courseTitle: '다 끝났다',
      participationMode: ParticipationMode.solo,
      myName: '테스트', partnerName: '',
    )));
    await tester.pumpAndSettle();
    final skip = find.widgetWithText(OutlinedButton, '마음에 담고 마무리하기');
    expect(tester.widget<OutlinedButton>(skip).onPressed, isNotNull);
    await tester.enterText(find.byType(TextField), '보존할 은혜');
    await tester.pump();
    expect(tester.widget<OutlinedButton>(skip).onPressed, isNull);
    await tester.tap(skip);
    await tester.pumpAndSettle();
    expect(find.byType(CompletionSignaturePage), findsNothing);
    await tester.tap(find.text('은혜 기록하고 서명하기'));
    await tester.pumpAndSettle();
    expect(tester.widget<CompletionSignaturePage>(
        find.byType(CompletionSignaturePage)).graceReflection, '보존할 은혜');
    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: GraceReflectionPage(
      key: ValueKey('fresh'), courseNumber: 1, courseTitle: '다 끝났다',
      participationMode: ParticipationMode.solo,
      myName: '테스트', partnerName: '',
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '내용');
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(tester.widget<OutlinedButton>(skip).onPressed, isNotNull);
    await tester.tap(skip);
    await tester.pumpAndSettle();
    expect(tester.widget<CompletionSignaturePage>(
        find.byType(CompletionSignaturePage)).graceReflection, isEmpty);
  });

  for (final course in [1, 2]) {
    testWidgets('signature course $course hides route back arrow', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
        Scaffold(body: TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => CompletionSignaturePage(
              courseNumber: course, courseTitle: '테스트',
              participationMode: ParticipationMode.solo,
              myName: '테스트', partnerName: '',
              graceReflection: '', graceReflectionPending: false,
            ),
          )), child: const Text('열기'),
        )),
      )));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsNothing);
      expect(tester.widget<AppBar>(find.byType(AppBar))
          .automaticallyImplyLeading, isFalse);
    });
  }
}
