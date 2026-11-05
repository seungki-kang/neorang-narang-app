import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neorang_narang_app/main.dart';

class SearchStore implements CompletionStore {
  SearchStore(this.records);
  final List<CompletionRecord> records;
  int reads = 0;
  int writes = 0;
  @override
  Future<List<CompletionRecord>> loadAll() async {
    reads++;
    return List.of(records);
  }

  @override
  Future<void> add(CompletionRecord record) async {
    writes++;
    throw StateError('unexpected_write');
  }

  @override
  Future<void> saveGraceReflection(String recordId, String reflection) async {
    writes++;
    throw StateError('unexpected_write');
  }

  @override
  Future<int> countForCourse(int courseNumber) async =>
      records.where((record) => record.courseNumber == courseNumber).length;
  @override
  Future<List<CompletionRecord>> pendingGraceRecords() async => [];
}

CompletionRecord sample(String id, int chapter, String name, String reflection,
    int day, {String partner = ''}) => CompletionRecord(
  id: id,
  courseNumber: chapter,
  courseTitle: chapter == 1 ? '다 끝났다' : '다 이루었다',
  participationMode:
      partner.isEmpty ? ParticipationMode.solo : ParticipationMode.together,
  myName: name,
  partnerName: partner,
  completedAt: DateTime(2026, 11, day, 12),
  mySignedAt: DateTime(2026, 11, day, 11),
  partnerSignedAt: partner.isEmpty ? null : DateTime(2026, 11, day, 11),
  graceReflection: reflection,
  graceReflectionPending: false,
);

Future<SearchStore> openHistory(WidgetTester tester,
    {bool empty = false}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = SearchStore(empty ? [] : [
    sample('a', 1, '샘플가', '감사와 평안', 5, partner: '동행인'),
    sample('b', 2, '샘플나', '감사와 기쁨', 4),
    sample('c', 1, 'Sample', 'Hope', 3),
  ]);
  await tester.pumpWidget(
    MaterialApp(home: CompletionHistoryPage(completionStore: store)),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const ValueKey('history-search')), query);
  await tester.pump();
}

void main() {
  testWidgets('name partner content and case-insensitive search are read-only',
      (tester) async {
    final store = await openHistory(tester);
    final original = store.records.map((record) => record.toJson()).toList();
    for (final query in ['샘플가', '동행인', '평안', 'hope', '다 이루었다']) {
      await search(tester, query);
      expect(find.text('현재 조건에 맞는 기록 1개'), findsOneWidget);
    }
    expect(store.reads, 1);
    expect(store.writes, 0);
    expect(store.records.map((record) => record.toJson()).toList(), original);
    expect(find.text('총 3회의 문답을 마쳤습니다.'), findsOneWidget);
  });

  testWidgets('chapter and all search words intersect; clearing keeps chapter',
      (tester) async {
    final store = await openHistory(tester);
    await search(tester, '  감사   평안  ');
    expect(find.text('현재 조건에 맞는 기록 1개'), findsOneWidget);
    await tester.tap(find.text('2장').first);
    await tester.pump();
    expect(find.text('현재 조건에 맞는 기록 0개'), findsOneWidget);
    expect(find.textContaining('조건에 맞는 기록이 없습니다.'), findsOneWidget);
    expect(find.text('아직 문답 기록이 없습니다.'), findsNothing);
    await tester.tap(find.byTooltip('검색어 지우기'));
    await tester.pump();
    expect(find.text('현재 조건에 맞는 기록 1개'), findsOneWidget);
    expect(find.text('감사와 기쁨'), findsOneWidget);
    expect(store.writes, 0);
  });

  testWidgets('date accepts dots hyphens and slashes', (tester) async {
    await openHistory(tester);
    for (final date in ['2026.11.05', '2026-11-05', '2026/11/05']) {
      await search(tester, date);
      expect(find.text('현재 조건에 맞는 기록 1개'), findsOneWidget);
      expect(find.text('감사와 평안'), findsOneWidget);
    }
  });

  testWidgets('whitespace search restores all records in newest-first order',
      (tester) async {
    await openHistory(tester);
    await search(tester, '없는내용');
    expect(find.text('현재 조건에 맞는 기록 0개'), findsOneWidget);
    await search(tester, '  ');
    expect(find.text('현재 조건에 맞는 기록 3개'), findsOneWidget);
    expect(tester.getTopLeft(find.text('감사와 평안')).dy,
        lessThan(tester.getTopLeft(find.text('감사와 기쁨')).dy));
  });

  testWidgets('empty store keeps empty-history guidance', (tester) async {
    final store = await openHistory(tester, empty: true);
    await search(tester, '감사');
    expect(find.text('아직 문답 기록이 없습니다.'), findsOneWidget);
    expect(store.writes, 0);
  });
}
