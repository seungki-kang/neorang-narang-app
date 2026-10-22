import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Fault injection uses the platform interface already provided by the plugin.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:neorang_narang_app/main.dart';

import 'history_recovery_repository_test.dart' show fixture;

class RejectingPreferences extends InMemorySharedPreferencesStore {
  RejectingPreferences() : super.empty();
  bool fail = false;
  bool throwError = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (fail) {
      if (throwError) throw StateError('injected_write');
      return false;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  for (final backend in ['prefs', 'sqlite']) {
    group('trash $backend', () {
      late CompletionTrashStore store;
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

      test('move preserves snapshot separates queues and restore keeps every field', () async {
        final pending = CompletionRecovery(
          before: fixture('a'),
          record: fixture('a', text: '미저장'),
          attemptedAt: DateTime(2026),
        );
        await store.stageRecovery(pending);
        await CompletionActions(store).delete('a');
        final trash = (await store.listTrash()).single;
        expect(trash.record.toJson(), fixture('a').toJson());
        expect(trash.deletedAt, isNotNull);
        expect(trash.toJson()['kind'], 'deletedCompletion');
        expect(trash.toJson()['schemaVersion'], 1);
        expect(trash.toJson()['snapshot'], fixture('a').toJson());
        expect(await store.findById('a'), isNull);
        expect(await store.countForCourse(1), 0);
        expect(await store.countForCourse(2), 1);
        expect(await store.listRecoveries(), isEmpty);
        expect(await CompletionActions(store).pending(), isEmpty);
        expect(await store.listTrash(), hasLength(1));
        await expectLater(store.retryRecovery(trash.id), throwsStateError);
        await expectLater(store.discardRecovery(trash.id), throwsStateError);
        await store.restoreTrash('a');
        expect((await store.findById('a'))!.toJson(), fixture('a').toJson());
        expect(await store.countForCourse(1), 1);
        expect(await store.wasDeleted('a'), isFalse);
        expect(await store.listTrash(), isEmpty);
        expect(
          (await store.listRecoveries()).single.toJson(),
          pending.toJson(),
        );
      });

      test(
        'permanent deletion preserves other records and blocks stale writes',
        () async {
          await store.deleteById('a');
          await store.deleteById('a');
          expect(await store.listTrash(), hasLength(1));
          await store.permanentlyDeleteTrash('a');
          await store.permanentlyDeleteTrash('a');
          expect(await store.listTrash(), isEmpty);
          expect(await store.wasDeleted('a'), isTrue);
          await expectLater(store.restoreTrash('a'), throwsStateError);
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
          expect(
            (await store.loadAll()).single.toJson(),
            fixture('b', course: 2).toJson(),
          );
        },
      );

      test(
        'stale permanent delete never marks a restored active record',
        () async {
          await store.deleteById('a');
          await store.restoreTrash('a');
          await expectLater(
            store.permanentlyDeleteTrash('a'),
            throwsStateError,
          );
          expect((await store.findById('a'))!.toJson(), fixture('a').toJson());
          expect(await store.wasDeleted('a'), isFalse);
        },
      );

      test('missing original never creates a recoverable entry', () async {
        await expectLater(store.deleteById('missing'), throwsStateError);
        expect(await store.listTrash(), isEmpty);
        await store.permanentlyDeleteTrash('old-deleted');
        expect(await store.listTrash(), isEmpty);
        await expectLater(store.restoreTrash('old-deleted'), throwsStateError);
      });

      test('50 to 49 to 50 restores chapter season and leaves chapter two unchanged', () async {
        for (var i = 1; i < 50; i++) {
          await store.add(fixture('a$i'));
        }
        await store.deleteById('a');
        expect(ChapterProgress(await store.countForCourse(1)).season, 1);
        expect(
          ChapterProgress(await store.countForCourse(1)).countInSeason,
          49,
        );
        await store.restoreTrash('a');
        expect(ChapterProgress(await store.countForCourse(1)).season, 2);
        expect(ChapterProgress(await store.countForCourse(1)).countInSeason, 0);
        expect(await store.countForCourse(2), 1);
      });

      test(
        'same ID conflict preserves active record and archived snapshot',
        () async {
          await store.deleteById('a');
          final conflict = fixture('a', text: '충돌 원본');
          if (db != null) {
            final row = Map<String, Object?>.from(
              (await db!.query('completion_records')).single,
            );
            row['id'] = conflict.id;
            row['grace_reflection'] = conflict.graceReflection;
            await db!.insert('completion_records', row);
          } else {
            final prefs = await SharedPreferences.getInstance();
            final state = jsonDecode(
              prefs.getString(CompletionRepository.stateKey)!,
            ) as Map<String, dynamic>;
            (state['records'] as List).add(conflict.toJson());
            await prefs.setString(
              CompletionRepository.stateKey,
              jsonEncode(state),
            );
          }
          final before = (await store.findById('a'))!.toJson();
          await expectLater(store.restoreTrash('a'), throwsStateError);
          expect((await store.findById('a'))!.toJson(), before);
          expect(
            (await store.listTrash()).single.record.toJson(),
            fixture('a').toJson(),
          );
        },
      );

      test('kindless legacy recovery remains save retry data', () async {
        final entry = CompletionRecovery(
          before: fixture('a'),
          record: fixture('a', text: '이전 대기'),
          attemptedAt: DateTime(2026),
        );
        final payload = entry.toJson()
          ..remove('kind')
          ..remove('schemaVersion');
        if (db != null) {
          await db!.insert('completion_recoveries', {
            'id': entry.id,
            'record_id': 'a',
            'payload': jsonEncode(payload),
          });
        } else {
          final prefs = await SharedPreferences.getInstance();
          final state = jsonDecode(
            prefs.getString(CompletionRepository.stateKey)!,
          ) as Map<String, dynamic>;
          (state['recoveries'] as List).add(payload);
          await prefs.setString(
            CompletionRepository.stateKey,
            jsonEncode(state),
          );
        }
        expect(await store.listTrash(), isEmpty);
        expect((await store.listRecoveries()).single.id, entry.id);
        await store.retryRecovery(entry.id);
        expect((await store.findById('a'))!.graceReflection, '이전 대기');
      });

      if (backend == 'sqlite') {
        for (final trigger in [
          "CREATE TRIGGER fail_archive BEFORE INSERT ON completion_recoveries BEGIN SELECT RAISE(ABORT, 'injected'); END",
          "CREATE TRIGGER fail_remove BEFORE DELETE ON completion_records BEGIN SELECT RAISE(ABORT, 'injected'); END",
        ]) {
          test('atomic move rollback: $trigger', () async {
            await db!.execute(trigger);
            await expectLater(store.deleteById('a'), throwsA(isA<DatabaseException>()));
            expect(
              (await store.findById('a'))!.toJson(),
              fixture('a').toJson(),
            );
            expect(await store.listTrash(), isEmpty);
            expect(await store.wasDeleted('a'), isFalse);
          });
        }
        for (final trigger in [
          "CREATE TRIGGER fail_restore BEFORE INSERT ON completion_records BEGIN SELECT RAISE(ABORT, 'injected'); END",
          "CREATE TRIGGER fail_cleanup BEFORE DELETE ON completion_recoveries BEGIN SELECT RAISE(ABORT, 'injected'); END",
          "CREATE TRIGGER fail_marker BEFORE DELETE ON deleted_completion_ids BEGIN SELECT RAISE(ABORT, 'injected'); END",
        ]) {
          test('atomic restore rollback: $trigger', () async {
            await store.deleteById('a');
            await db!.execute(trigger);
            await expectLater(store.restoreTrash('a'), throwsA(isA<DatabaseException>()));
            expect(await store.findById('a'), isNull);
            expect(await store.listTrash(), hasLength(1));
            expect(await store.wasDeleted('a'), isTrue);
          });
        }
        test(
          'v2 schema unchanged and archive persists across store recreation',
          () async {
            final schema = await db!.rawQuery(
              "SELECT name, sql FROM sqlite_master ORDER BY name",
            );
            await store.deleteById('a');
            expect(await db!.getVersion(), 2);
            expect(
              await db!.rawQuery(
                "SELECT name, sql FROM sqlite_master ORDER BY name",
              ),
              schema,
            );
            final recreated = SqliteCompletionRepository(
              AppDatabase(database: db),
            );
            expect(
              (await recreated.listTrash()).single.record.toJson(),
              fixture('a').toJson(),
            );
            await recreated.restoreTrash('a');
            expect(
              (await store.findById('a'))!.toJson(),
              fixture('a').toJson(),
            );
          },
        );
      }
    });
  }

  test('v2 file reopen retains trash snapshot and restoration', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('nn-trash-fixture-');
    final filename = '${dir.path}/fixture.db';
    final app = AppDatabase(databasePath: filename);
    final store = SqliteCompletionRepository(app);
    await store.add(fixture('a'));
    await store.deleteById('a');
    await (await app.database).close();
    final reopenedApp = AppDatabase(databasePath: filename);
    final reopened = SqliteCompletionRepository(reopenedApp);
    expect(
      (await reopened.listTrash()).single.record.toJson(),
      fixture('a').toJson(),
    );
    expect(await reopened.loadAll(), isEmpty);
    await reopened.restoreTrash('a');
    await (await reopenedApp.database).close();
    final finalApp = AppDatabase(databasePath: filename);
    final finalStore = SqliteCompletionRepository(finalApp);
    expect((await finalStore.loadAll()).single.toJson(), fixture('a').toJson());
    expect(await finalStore.listTrash(), isEmpty);
    expect(await (await finalApp.database).getVersion(), 2);
    await (await finalApp.database).close();
    // Independent fixture only; never opens or deletes a user's database.
  });

  test('legacy sources stay untouched while in trash and return only after restore', () async {
    SharedPreferences.setMockInitialValues({});
    final record = fixture('a');
    final draft = GraceDraft(
      id: record.id,
      courseNumber: 1,
      courseTitle: record.courseTitle,
      participationMode: record.participationMode,
      myName: record.myName,
      partnerName: record.partnerName,
      reflection: '미저장 원본',
    );
    final raw = jsonEncode([
      {'saved': record.toJson(), 'draft': draft.toJson(), 'choice': 'draft'},
    ]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(GraceConflictRecovery.archiveKey, raw);
    final store = CompletionRepository();
    await store.add(record);
    await CompletionActions(store).delete(record.id);
    expect(await CompletionActions(store).pending(), isEmpty);
    expect(prefs.getString(GraceConflictRecovery.archiveKey), raw);
    await store.restoreTrash(record.id);
    expect((await CompletionActions(store).pending()).single.legacy, isNotNull);
    expect((await store.findById(record.id))!.toJson(), record.toJson());
  });

  test(
    'corrupt archive cannot appear as restorable or be silently erased',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = CompletionRepository();
      await store.add(fixture('a'));
      await store.deleteById('a');
      final prefs = await SharedPreferences.getInstance();
      final state = jsonDecode(
        prefs.getString(CompletionRepository.stateKey)!,
      ) as Map<String, dynamic>;
      ((state['recoveries'] as List).single as Map).remove('snapshot');
      final corrupt = jsonEncode(state);
      await prefs.setString(CompletionRepository.stateKey, corrupt);
      await expectLater(
        store.listTrash(),
        throwsA(isA<StorageReadException>()),
      );
      await expectLater(
        store.restoreTrash('a'),
        throwsA(isA<StorageReadException>()),
      );
      await expectLater(
        store.permanentlyDeleteTrash('a'),
        throwsA(isA<StorageReadException>()),
      );
      expect(prefs.getString(CompletionRepository.stateKey), corrupt);
    },
  );

  for (final throwing in [false, true]) {
    test(
      'prefs failed move restore permanent preserves disk and cache throwing=$throwing',
      () async {
        SharedPreferences.setMockInitialValues({});
        final platform = RejectingPreferences()..throwError = throwing;
        SharedPreferencesStorePlatform.instance = platform;
        final store = CompletionRepository();
        await store.add(fixture('a'));
        final prefs = await SharedPreferences.getInstance();
        final before = prefs.getString(CompletionRepository.stateKey);
        platform.fail = true;
        await expectLater(store.deleteById('a'), throwsStateError);
        expect(prefs.getString(CompletionRepository.stateKey), before);
        expect((await store.findById('a'))!.toJson(), fixture('a').toJson());
        expect(await store.listTrash(), isEmpty);
        platform.fail = false;
        await store.deleteById('a');
        final archived = prefs.getString(CompletionRepository.stateKey);
        platform.fail = true;
        await expectLater(store.restoreTrash('a'), throwsStateError);
        expect(prefs.getString(CompletionRepository.stateKey), archived);
        await expectLater(store.permanentlyDeleteTrash('a'), throwsStateError);
        expect(prefs.getString(CompletionRepository.stateKey), archived);
        expect(await store.listTrash(), hasLength(1));
        expect(await store.findById('a'), isNull);
        expect(await store.wasDeleted('a'), isTrue);
        platform.fail = false;
      },
    );
  }
}
