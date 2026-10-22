import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('own name persists and can be changed', () async {
    final repo = ParticipantPreferencesRepository();
    expect((await repo.load()).myName, isEmpty);
    await repo.remember(' 이름 ', null);
    expect((await ParticipantPreferencesRepository().load()).myName, '이름');
    await repo.remember('새 이름', null);
    expect((await repo.load()).myName, '새 이름');
  });

  test('recent partners deduplicate, reorder and keep five', () async {
    final repo = ParticipantPreferencesRepository();
    for (var i = 0; i < 6; i++) {
      await repo.remember('나', '상대$i');
    }
    expect((await repo.load()).recentPartners, [
      '상대5',
      '상대4',
      '상대3',
      '상대2',
      '상대1',
    ]);
    await repo.remember('나', '상대3');
    expect((await repo.load()).recentPartners, [
      '상대3',
      '상대5',
      '상대4',
      '상대2',
      '상대1',
    ]);
    await repo.remember('나', null);
    expect((await repo.load()).recentPartners.length, 5);
  });

  test(
    'removing a recent partner preserves own name and unrelated records',
    () async {
      const key = 'neorang_narang_completion_records_v1';
      SharedPreferences.setMockInitialValues({key: 'untouched fixture'});
      final repo = ParticipantPreferencesRepository();
      await repo.remember('나', '상대');
      await repo.removePartner('상대');
      expect((await repo.load()).myName, '나');
      expect((await repo.load()).recentPartners, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), 'untouched fixture');
    },
  );

  test('corrupt preferences are preserved and cannot be overwritten', () async {
    final key = ParticipantPreferencesRepository.storageKey;
    SharedPreferences.setMockInitialValues({key: '{broken'});
    final repo = ParticipantPreferencesRepository();
    await expectLater(
      repo.remember('나', '상대'),
      throwsA(isA<StorageReadException>()),
    );
    await expectLater(
      repo.removePartner('상대'),
      throwsA(isA<StorageReadException>()),
    );
    expect((await SharedPreferences.getInstance()).getString(key), '{broken');
  });

  testWidgets('name restores and recent partner requires explicit selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await ParticipantPreferencesRepository().remember('내 이름', '함께할 이름');
    await tester.pumpWidget(const MaterialApp(home: ParticipantSetupPage()));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '내 이름',
    );
    await tester.tap(find.text('함께 하기'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      isEmpty,
    );
    await tester.tap(find.widgetWithText(InputChip, '함께할 이름'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '함께할 이름',
    );
    await tester.tap(find.text('과정 선택으로'));
    await tester.pumpAndSettle();
    final page = tester.widget<CourseSelectionPage>(
      find.byType(CourseSelectionPage),
    );
    expect(page.myName, '내 이름');
    expect(page.partnerName, '함께할 이름');
  });
}
