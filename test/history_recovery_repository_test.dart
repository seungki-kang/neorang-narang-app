import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:neorang_narang_app/main.dart';

CompletionRecord fixture(String id, {int course = 1, String text = '기존 은혜'}) =>
    CompletionRecord(
      id: id,
      courseNumber: course,
      courseTitle: course == 1 ? '다 끝났다' : '다 이루었다',
      participationMode: ParticipationMode.together,
      myName: '테스트 나',
      partnerName: '테스트 상대',
      completedAt: DateTime(2026, 10, 10, 12),
      mySignedAt: DateTime(2026, 10, 10, 11),
      partnerSignedAt: DateTime(2026, 10, 10, 11, 1),
      graceReflection: text,
      graceReflectionPending: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  for (final backend in ['prefs', 'sqlite']) {
    group(backend, () {
      late CompletionEditingStore store;
      Database? db;
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        if (backend == 'sqlite') {
          final app = AppDatabase(databasePath: inMemoryDatabasePath);
          db = await app.database;
          store = SqliteCompletionRepository(app);
        } else {
          store = CompletionRepository();
        }
        await store.add(fixture('a'));
        await store.add(fixture('b', course: 2));
      });
      tearDown(() async {
        await db?.close();
      });
      test(
        'edit keeps ID dates signatures counts and unrelated chapter',
        () async {
          final old = (await store.findById('a'))!;
          await CompletionActions(store).saveEdit(old, '수정 은혜');
          final saved = (await store.findById('a'))!;
          expect(saved.toJson(), old.withGraceReflection('수정 은혜').toJson());
          expect(await store.countForCourse(1), 1);
          expect(await store.countForCourse(2), 1);
        },
      );
      test(
        'reflection and heart states can be changed in both directions',
        () async {
          await CompletionActions(store)
              .saveEdit((await store.findById('a'))!, '');
          expect((await store.findById('a'))!.graceReflection, isEmpty);
          await CompletionActions(store)
              .saveEdit((await store.findById('a'))!, '새 은혜');
          expect((await store.findById('a'))!.graceReflection, '새 은혜');
          expect((await store.loadAll()).length, 2);
        },
      );
      test(
        'failed optimistic edit preserves original and durable recovery',
        () async {
          final old = fixture('a');
          await store.stageRecovery(
            CompletionRecovery(
              before: old,
              record: old.withGraceReflection('대기'),
              attemptedAt: DateTime(2026),
            ),
          );
          await store.saveGraceReflection('a', '다른 화면 수정');
          await expectLater(store.retryRecovery('edit:a'), throwsStateError);
          expect((await store.findById('a'))!.graceReflection, '다른 화면 수정');
          expect((await store.listRecoveries()).length, 1);
        },
      );
      test('delete removes only target and its recoveries', () async {
        await store.stageRecovery(
          CompletionRecovery(
            before: fixture('a'),
            record: fixture('a', text: '대기'),
            attemptedAt: DateTime(2026),
          ),
        );
        await store.stageRecovery(
          CompletionRecovery(
            before: fixture('b', course: 2),
            record: fixture('b', course: 2, text: '다른 대기'),
            attemptedAt: DateTime(2026),
          ),
        );
        await store.deleteById('a');
        expect(await store.findById('a'), isNull);
        expect(await store.countForCourse(1), 0);
        expect(await store.countForCourse(2), 1);
        expect((await store.listRecoveries()).single.record.id, 'b');
      });
      test(
        '50 to 49 deletion recalculates season without changing chapter 2',
        () async {
          for (var i = 1; i < 50; i++) {
            await store.add(fixture('a$i'));
          }
          expect(ChapterProgress(await store.countForCourse(1)).season, 2);
          await store.deleteById('a');
          final progress = ChapterProgress(await store.countForCourse(1));
          expect(progress.season, 1);
          expect(progress.countInSeason, 49);
          expect(progress.stars, 0);
          expect(await store.countForCourse(2), 1);
        },
      );
      test('new retry is idempotent and removes only its recovery', () async {
        final entry = CompletionRecovery(
          record: fixture('new'),
          attemptedAt: DateTime(2026),
        );
        await store.stageRecovery(entry);
        await store.stageRecovery(
          CompletionRecovery(
            record: fixture('other'),
            attemptedAt: DateTime(2026),
          ),
        );
        await store.retryRecovery(entry.id);
        await store.retryRecovery(entry.id);
        await store.stageRecovery(entry);
        await store.retryRecovery(entry.id);
        expect((await store.loadAll()).where((r) => r.id == 'new').length, 1);
        expect((await store.listRecoveries()).single.record.id, 'other');
      });
      test('edit retry uses existing row and preserves timestamps', () async {
        final before = fixture('a');
        final entry = CompletionRecovery(
          before: before,
          record: before.withGraceReflection('대기 수정'),
          attemptedAt: DateTime(2026),
        );
        await store.stageRecovery(entry);
        await store.retryRecovery(entry.id);
        await store.stageRecovery(entry);
        await store.retryRecovery(entry.id);
        expect((await store.loadAll()).length, 2);
        expect(
          (await store.findById('a'))!.toJson(),
          before.withGraceReflection('대기 수정').toJson(),
        );
      });
      test(
        'discarding temporary edit never deletes completed record',
        () async {
          final entry = CompletionRecovery(
            before: fixture('a'),
            record: fixture('a', text: '대기'),
            attemptedAt: DateTime(2026),
          );
          await store.stageRecovery(entry);
          await store.discardRecovery(entry.id);
          expect((await store.findById('a'))!.toJson(), fixture('a').toJson());
          expect(await store.listRecoveries(), isEmpty);
        },
      );
      test(
        'deleted ID cannot be resurrected by stale new or edit retries',
        () async {
          await store.deleteById('a');
          await expectLater(store.add(fixture('a')), throwsStateError);
          await expectLater(
            store.stageRecovery(
              CompletionRecovery(
                record: fixture('a'),
                attemptedAt: DateTime(2026),
              ),
            ),
            throwsStateError,
          );
          await expectLater(
            store.stageRecovery(
              CompletionRecovery(
                before: fixture('a'),
                record: fixture('a', text: '수정'),
                attemptedAt: DateTime(2026),
              ),
            ),
            throwsStateError,
          );
        },
      );
      test(
        'already committed recovery is safely cleaned by ID and content',
        () async {
          await store.stageRecovery(
            CompletionRecovery(
              record: fixture('a'),
              attemptedAt: DateTime(2026),
            ),
          );
          expect(await CompletionActions(store).pending(), isEmpty);
          expect(await store.listRecoveries(), isEmpty);
          expect((await store.loadAll()).length, 2);
        },
      );
      test('changed identity cannot be applied as an edit', () async {
        final entry = CompletionRecovery(
          before: fixture('a'),
          record: fixture('a', course: 2),
          attemptedAt: DateTime(2026),
        );
        await expectLater(
          store.stageRecovery(entry).then((_) => store.retryRecovery(entry.id)),
          throwsA(anything),
        );
        expect((await store.findById('a'))!.courseNumber, 1);
      });
      test(
        'response failure after committed edit is verified without duplicate',
        () async {
          final ack = _AcknowledgementEditingStore(store);
          await CompletionActions(ack).saveEdit(fixture('a'), '응답 유실 수정');
          expect((await store.findById('a'))!.graceReflection, '응답 유실 수정');
          expect((await store.loadAll()).length, 2);
          expect(await store.listRecoveries(), isEmpty);
        },
      );
      test(
        'response failure after deletion confirms persisted tombstone',
        () async {
          final ack = _AcknowledgementEditingStore(store);
          await CompletionActions(ack).delete('a');
          expect(await store.findById('a'), isNull);
          expect(await store.countForCourse(2), 1);
        },
      );
      if (backend == 'sqlite') {
        test(
          'new completion INSERT failure keeps recovery through retry',
          () async {
            await db!.execute(
              "CREATE TRIGGER fail_insert BEFORE INSERT ON completion_records BEGIN SELECT RAISE(ABORT, 'injected'); END",
            );
            await expectLater(
              CompletionActions(store).saveNew(fixture('pending-new')),
              throwsA(anything),
            );
            expect(await store.findById('pending-new'), isNull);
            expect((await store.listRecoveries()).single.id, 'new:pending-new');
            await db!.execute('DROP TRIGGER fail_insert');
            await store.retryRecovery('new:pending-new');
            expect(
              (await store.loadAll())
                  .where((r) => r.id == 'pending-new')
                  .length,
              1,
            );
            expect(await store.listRecoveries(), isEmpty);
          },
        );
        test(
          'recovery cleanup failure rolls back completed UPDATE too',
          () async {
            final entry = CompletionRecovery(
              before: fixture('a'),
              record: fixture('a', text: '대기'),
              attemptedAt: DateTime(2026),
            );
            await store.stageRecovery(entry);
            await db!.execute(
              "CREATE TRIGGER fail_cleanup BEFORE DELETE ON completion_recoveries BEGIN SELECT RAISE(ABORT, 'injected'); END",
            );
            await expectLater(store.retryRecovery(entry.id), throwsA(anything));
            expect((await store.findById('a'))!.graceReflection, '기존 은혜');
            expect((await store.listRecoveries()).single.id, entry.id);
          },
        );

        test(
          'rollback after UPDATE failure keeps row and pending operation',
          () async {
            await db!.execute(
              "CREATE TRIGGER fail_update BEFORE UPDATE ON completion_records BEGIN SELECT RAISE(ABORT, 'injected'); END",
            );
            final entry = CompletionRecovery(
              before: fixture('a'),
              record: fixture('a', text: '대기'),
              attemptedAt: DateTime(2026),
            );
            await store.stageRecovery(entry);
            await expectLater(store.retryRecovery(entry.id), throwsA(anything));
            expect((await store.findById('a'))!.graceReflection, '기존 은혜');
            expect((await store.listRecoveries()).single.id, entry.id);
            await db!.execute('DROP TRIGGER fail_update');
            await store.retryRecovery(entry.id);
            expect(await store.listRecoveries(), isEmpty);
          },
        );
        test(
          'rollback after DELETE failure preserves counts and recovery',
          () async {
            await db!.execute(
              "CREATE TRIGGER fail_delete BEFORE DELETE ON completion_records BEGIN SELECT RAISE(ABORT, 'injected'); END",
            );
            await store.stageRecovery(
              CompletionRecovery(
                before: fixture('a'),
                record: fixture('a', text: '대기'),
                attemptedAt: DateTime(2026),
              ),
            );
            await expectLater(store.deleteById('a'), throwsA(anything));
            expect(await store.countForCourse(1), 1);
            expect(await store.wasDeleted('a'), isFalse);
            expect((await store.listRecoveries()).length, 1);
          },
        );
        test(
          'update trigger proves edit retry never INSERTs another completion',
          () async {
            await db!.execute(
              "CREATE TRIGGER no_insert BEFORE INSERT ON completion_records BEGIN SELECT RAISE(ABORT, 'unexpected insert'); END",
            );
            await CompletionActions(store).saveEdit(fixture('a'), '수정');
            expect((await store.findById('a'))!.graceReflection, '수정');
          },
        );
      }
    });
  }
  test(
    'v1 to v2 migration preserves every existing row and question draft',
    () async {
      final dir = await Directory.systemTemp.createTemp('nn-migration-test-');
      final filename = '${dir.path}/fixture.db';
      final old = await databaseFactoryFfi.openDatabase(
        filename,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE completion_records (id TEXT PRIMARY KEY, course_number INTEGER NOT NULL, course_title TEXT NOT NULL, participation_mode TEXT NOT NULL, my_name TEXT NOT NULL, partner_name TEXT NOT NULL, completed_at TEXT NOT NULL, my_signed_at TEXT NOT NULL, partner_signed_at TEXT, grace_reflection TEXT NOT NULL, grace_reflection_pending INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE question_drafts (id TEXT PRIMARY KEY, course_number INTEGER NOT NULL, course_title TEXT NOT NULL, participation_mode TEXT NOT NULL, my_display_name TEXT NOT NULL, partner_display_name TEXT NOT NULL, first_asker_is_me INTEGER NOT NULL, current_question_index INTEGER NOT NULL, saved_at TEXT NOT NULL)',
            );
          },
        ),
      );
      final oldStore = SqliteCompletionRepository(AppDatabase(database: old));
      // v1 cannot call the new repository's add, which consults v2 tombstones.
      final f = fixture('legacy');
      await old.insert('completion_records', {
        'id': f.id,
        'course_number': f.courseNumber,
        'course_title': f.courseTitle,
        'participation_mode': f.participationMode.name,
        'my_name': f.myName,
        'partner_name': f.partnerName,
        'completed_at': f.completedAt.toIso8601String(),
        'my_signed_at': f.mySignedAt.toIso8601String(),
        'partner_signed_at': f.partnerSignedAt!.toIso8601String(),
        'grace_reflection': f.graceReflection,
        'grace_reflection_pending': 0,
      });
      await old.insert('question_drafts', {
        'id': StorageSchema.activeDraftId,
        'course_number': 1,
        'course_title': '다 끝났다',
        'participation_mode': 'solo',
        'my_display_name': '테스트',
        'partner_display_name': '',
        'first_asker_is_me': 1,
        'current_question_index': 12,
        'saved_at': DateTime(2026).toIso8601String(),
      });
      final before = await oldStore.loadAll();
      final questionBefore = await old.query('question_drafts');
      await old.close();
      final app = AppDatabase(databasePath: filename);
      final upgraded = await app.database;
      final store = SqliteCompletionRepository(app);
      expect(await upgraded.getVersion(), 2);
      expect((await store.loadAll()).single.toJson(), before.single.toJson());
      expect(await upgraded.query('question_drafts'), questionBefore);
      expect(await store.listRecoveries(), isEmpty);
      await store.stageRecovery(
        CompletionRecovery(
          before: f,
          record: f.withGraceReflection('복구 대기'),
          attemptedAt: DateTime(2026),
        ),
      );
      await upgraded.close();
      final reopenedApp = AppDatabase(databasePath: filename);
      final reopened = SqliteCompletionRepository(reopenedApp);
      expect(
        (await reopened.listRecoveries()).single.record.graceReflection,
        '복구 대기',
      );
      await reopened.retryRecovery('edit:legacy');
      expect(
        (await reopened.findById('legacy'))!.toJson(),
        f.withGraceReflection('복구 대기').toJson(),
      );
      await (await reopenedApp.database).close();
      // Fixture directory intentionally retained; no user database is opened/deleted.
    },
  );
}

class _AcknowledgementEditingStore implements CompletionEditingStore {
  _AcknowledgementEditingStore(this.target);
  final CompletionEditingStore target;
  @override
  Future<List<CompletionRecord>> loadAll() => target.loadAll();
  @override
  Future<void> add(CompletionRecord r) => target.add(r);
  @override
  Future<int> countForCourse(int c) => target.countForCourse(c);
  @override
  Future<List<CompletionRecord>> pendingGraceRecords() =>
      target.pendingGraceRecords();
  @override
  Future<void> saveGraceReflection(String id, String text) =>
      target.saveGraceReflection(id, text);
  @override
  Future<CompletionRecord?> findById(String id) => target.findById(id);
  @override
  Future<void> stageRecovery(CompletionRecovery e) => target.stageRecovery(e);
  @override
  Future<List<CompletionRecovery>> listRecoveries() => target.listRecoveries();
  @override
  Future<void> retryRecovery(String id) async {
    await target.retryRecovery(id);
    throw StateError('injected_ack_failure');
  }

  @override
  Future<void> discardRecovery(String id) => target.discardRecovery(id);
  @override
  Future<void> deleteById(String id) async {
    await target.deleteById(id);
    throw StateError('injected_ack_failure');
  }

  @override
  Future<bool> wasDeleted(String id) => target.wasDeleted(id);
  @override
  Future<List<String>> deletedIds() => target.deletedIds();
}
