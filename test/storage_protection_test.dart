import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neorang_narang_app/main.dart';

const completionKey = 'neorang_narang_completion_records_v1';
const draftKey = 'neorang_narang_question_draft_v1';

CompletionRecord sampleRecord() => CompletionRecord(
  id: 'fixture',
  courseNumber: 1,
  courseTitle: '테스트',
  participationMode: ParticipationMode.solo,
  myName: '테스트',
  partnerName: '',
  completedAt: DateTime(2026, 10, 9),
  mySignedAt: DateTime(2026, 10, 9),
  partnerSignedAt: null,
  graceReflection: '보존할 기록',
  graceReflectionPending: false,
);
QuestionDraft sampleDraft() => QuestionDraft(
  courseNumber: 1,
  courseTitle: '테스트',
  participationMode: ParticipationMode.solo,
  myDisplayName: '테스트',
  partnerDisplayName: '',
  firstAskerIsMe: true,
  currentQuestionIndex: 0,
  savedAt: DateTime(2026, 10, 9),
);

class RetryingStore implements CompletionStore {
  bool fail = true;
  @override
  Future<List<CompletionRecord>> loadAll() async {
    if (fail) throw const StorageReadException();
    return [sampleRecord()];
  }

  @override
  Future<void> add(CompletionRecord record) async {}
  @override
  Future<int> countForCourse(int courseNumber) async => 0;
  @override
  Future<List<CompletionRecord>> pendingGraceRecords() async => [];
  @override
  Future<void> saveGraceReflection(String recordId, String reflection) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('absent storage is genuinely empty', () async {
    expect(await CompletionRepository().loadAll(), isEmpty);
    expect(await QuestionDraftRepository().load(), isNull);
  });

  for (final raw in ['', '{broken', '{}', '[{"id":"partial"}]']) {
    test(
      'unreadable completion blocks writes and preserves raw: $raw',
      () async {
        SharedPreferences.setMockInitialValues({completionKey: raw});
        final store = CompletionRepository();
        await expectLater(
          store.loadAll(),
          throwsA(isA<StorageReadException>()),
        );
        await expectLater(
          store.add(sampleRecord()),
          throwsA(isA<StorageReadException>()),
        );
        await expectLater(
          store.saveGraceReflection('fixture', 'new'),
          throwsA(isA<StorageReadException>()),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(completionKey), raw);
      },
    );
  }

  for (final raw in ['', '{broken', '[]', '{"courseNumber":1}']) {
    test('unreadable draft blocks save and clear: $raw', () async {
      SharedPreferences.setMockInitialValues({draftKey: raw});
      final store = QuestionDraftRepository();
      await expectLater(store.load(), throwsA(isA<StorageReadException>()));
      await expectLater(
        store.save(sampleDraft()),
        throwsA(isA<StorageReadException>()),
      );
      await expectLater(store.clear(), throwsA(isA<StorageReadException>()));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(draftKey), raw);
    });
  }

  test('valid existing records survive append and retry', () async {
    final old = sampleRecord();
    SharedPreferences.setMockInitialValues({
      completionKey: jsonEncode([old.toJson()]),
      draftKey: jsonEncode(sampleDraft().toJson()),
    });
    final store = CompletionRepository();
    await store.add(old);
    expect((await store.loadAll()).single.toJson(), old.toJson());
    await store.saveGraceReflection(old.id, '수정한 기록');
    expect((await store.loadAll()).single.graceReflection, '수정한 기록');
    final draftStore = QuestionDraftRepository();
    await draftStore.save(sampleDraft());
    expect((await draftStore.load())!.courseNumber, 1);
    await draftStore.clear();
    expect(await draftStore.load(), isNull);
  });

  testWidgets('history error is distinct from empty and retry recovers', (
    tester,
  ) async {
    final store = RetryingStore();
    await tester.pumpWidget(
      MaterialApp(home: CompletionHistoryPage(completionStore: store)),
    );
    await tester.pumpAndSettle();
    expect(find.text('저장된 기록을 읽지 못했습니다.'), findsOneWidget);
    expect(find.text('총 0회의 문답을 마쳤습니다.'), findsNothing);
    expect(tester.takeException(), isNull);
    store.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('총 1회의 문답을 마쳤습니다.'), findsOneWidget);
    expect(find.text('저장된 기록을 읽지 못했습니다.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
