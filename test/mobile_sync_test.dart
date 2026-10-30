import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neorang_narang_app/mobile/mobile_page.dart';
import 'package:neorang_narang_app/main.dart' as app;
import 'package:neorang_narang_app/mobile/mobile_sync.dart';
import 'package:neorang_narang_app/mobile/mobile_transport_io.dart'
    as transport;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Server {
  String owner = 'synthetic-a';
  int generation = 0;
  bool active = false;
  int through = 0;
  bool offline = false;
  bool loseDeleteResponse = false;
  bool loseSendResponse = false;
  bool loggedOut = false;
  String? rejection;
  Completer<void>? logoutGate;
  final records = <String, String>{};
  final uploads = <String>[];
  Completer<void>? sendGate;
  Completer<void>? sendStarted;
  Map<String, dynamic> status() => {
    'generation': generation,
    'active': active,
    'deletion_through': through,
    'deletion_status': through > 0 ? 'complete' : 'none',
  };
  Future<Map<String, dynamic>> call(
    String method,
    String path,
    Map<String, dynamic>? body,
    String? token,
  ) async {
    if (offline) throw StateError('offline');
    if (path.endsWith('login-transactions')) {
      expect(body!['challenge'], hasLength(43));
      return {
        'transaction': 'synthetic-transaction',
        'authorize_url': '$mobileOrigin$mobilePrefix/authorize?state=synthetic',
      };
    }
    if (path.endsWith('session-exchange')) {
      return {
        'sub': owner,
        'access_token': 'memory-only-$owner',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600,
      };
    }
    expect(token, 'memory-only-$owner');
    if (path.endsWith('/logout')) {
      loggedOut = true;
      await logoutGate?.future;
      return {};
    }
    if (rejection != null && !path.endsWith('synthetic-completion')) {
      throw StateError(rejection!);
    }
    if (path.endsWith('/consent/revoke')) {
      through = body!['generation'] as int;
      active = false;
      records.clear();
      if (loseDeleteResponse) throw StateError('lost_response');
      return status();
    }
    if (path.endsWith('/consent')) {
      if (method == 'POST' && !active) {
        generation++;
        active = true;
      }
      return status();
    }
    if (path.endsWith('synthetic-completion')) {
      uploads.add(jsonEncode(body));
      sendStarted?.complete();
      await sendGate?.future;
      if (rejection != null) throw StateError(rejection!);
      if (active && body!['generation'] == generation) {
        records[body['sync_id'] as String] = jsonEncode(body);
      }
      if (loseSendResponse) throw StateError('lost_response');
      return {'status': 'stored'};
    }
    throw StateError('unexpected_request');
  }
}

class NoWidgetDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Widget test must not access SQLite');
}

// Observe real MobileSync completion without putting SQLite in fake async.
class UploadWidgetSync extends MobileSync {
  UploadWidgetSync(super.db, super.request);
  var initialized = Completer<void>();
  final sent = Completer<void>();
  final revoked = Completer<void>();
  final loggedOut = Completer<void>();

  @override
  Future<void> refreshStatus() async {
    await super.refreshStatus();
    if (!initialized.isCompleted) initialized.complete();
  }

  @override
  Future<void> send() async {
    try {
      await super.send();
    } finally {
      sent.complete();
    }
  }

  @override
  Future<void> revoke() async {
    try {
      await super.revoke();
    } finally {
      revoked.complete();
    }
  }

  @override
  Future<void> logout() async {
    try {
      await super.logout();
    } finally {
      loggedOut.complete();
    }
  }
}

class WidgetMobileSync extends MobileSync {
  WidgetMobileSync()
    : super(NoWidgetDatabase(), (_, _, _, _) async {
        throw StateError('Widget test must not make requests');
      }) {
    account = 'synthetic-a';
    generation = 1;
    consentActive = true;
  }
  int refreshCalls = 0;
  int sendCalls = 0;
  int resumeCalls = 0;
  @override
  bool get loggedIn => true;
  @override
  Future<void> refreshStatus() async {
    refreshCalls++;
  }

  @override
  Future<void> send() async {
    sendCalls++;
  }

  @override
  Future<bool> resumeDeletion() async {
    resumeCalls++;
    return false;
  }
}

Future<void> login(MobileSync sync) async {
  await sync.beginLogin();
  await sync.finishLogin(
    '$mobileReturnUri?transaction=synthetic-transaction&code=${'x' * 43}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test('HTTP 401 is authentication failure; 403 is authorization denial', () {
    expect(transport.MobileHttpFailure(401).message, 'login_required');
    expect(transport.MobileHttpFailure(403).message, 'request_rejected');
  });
  testWidgets('resume without pending deletion preserves last result', (
    tester,
  ) async {
    final observed = WidgetMobileSync();
    const channel = MethodChannel('jesuslife/mobile_browser');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      observed.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(home: MobilePocPage(session: observed)),
    );
    await tester.pumpAndSettle();
    expect(observed.refreshCalls, 1);
    expect(observed.resumeCalls, 1);
    final checkbox = find.byType(CheckboxListTile);
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
    final send = find.text('선택한 1건 수동 전송 / 재시도');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('서버 저장 확인 완료.'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pumpAndSettle();
    expect(find.text('서버 저장 확인 완료.'), findsOneWidget);
    expect(find.text('서버 사본 삭제 확인 완료.'), findsNothing);
    expect(observed.refreshCalls, 1);
    expect(observed.sendCalls, 1);
    expect(observed.resumeCalls, 2);
    expect(tester.takeException(), isNull);
  });

  group('SQLite integration', () {
    late Directory directory;
    late Database db;
    late Server server;
    late MobileSync sync;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('nn-mobile-synthetic-');
      db = await databaseFactoryFfi.openDatabase(
        '${directory.path}/mobile-fixture.db',
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => createMobileTables(db),
        ),
      );
      server = Server();
      sync = MobileSync(db, server.call);
    });
    tearDown(() async {
      sync.dispose();
      await db.close();
      await directory.delete(recursive: true);
    });

    test(
      '401 preserves pending deletion and cancelled queue; login can resume',
      () async {
        await login(sync);
        await sync.grant();
        await sync.selectSynthetic(1);
        server.rejection = 'login_required';
        await expectLater(sync.revoke(), throwsStateError);
        expect(sync.loggedIn, isFalse);
        expect(sync.deletionPending, isTrue);
        expect(
          (await db.query('mobile_deletions')).single['status'],
          'pending',
        );
        expect((await db.query('mobile_queue')).single['status'], 'cancelled');
        server.rejection = null;
        await login(sync);
        expect(sync.loggedIn, isTrue);
        expect(
          (await db.query('mobile_deletions')).single['status'],
          'confirmed',
        );
      },
    );

    test(
      'upload 401 keeps queue; authorization denial keeps session',
      () async {
        await login(sync);
        await sync.grant();
        await sync.selectSynthetic(1);
        server.rejection = 'request_rejected';
        await expectLater(sync.send(), throwsStateError);
        expect(sync.loggedIn, isTrue);
        server.rejection = 'login_required';
        await expectLater(sync.send(), throwsStateError);
        expect(sync.loggedIn, isFalse);
        expect((await db.query('mobile_queue')).single['status'], 'queued');
        server.rejection = null;
        await login(sync);
        expect(sync.loggedIn, isTrue);
      },
    );

    test('late 401 from older session cannot invalidate new session', () async {
      await login(sync);
      await sync.grant();
      await sync.selectSynthetic(1);
      server.sendGate = Completer<void>();
      server.sendStarted = Completer<void>();
      final pending = expectLater(sync.send(), throwsStateError);
      await server.sendStarted!.future;
      await sync.logout();
      await login(sync);
      server.rejection = 'login_required';
      server.sendGate!.complete();
      await pending;
      expect(sync.loggedIn, isTrue);
      expect((await db.query('mobile_queue')).single['status'], 'queued');
    });

    for (final withdraw in [true, false]) {
      testWidgets(
        'real ${withdraw ? "withdrawal" : "logout"} button interrupts upload',
        (tester) async {
          await tester.runAsync(() async {
            sync.dispose();
            final observed = UploadWidgetSync(db, server.call);
            sync = observed;
            await login(sync);
            await sync.grant();
            await sync.selectSynthetic(1);
            const channel = MethodChannel('jesuslife/mobile_browser');
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              channel,
              (_) async => null,
            );
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                channel,
                null,
              );
            });
            observed.initialized = Completer<void>();
            await tester.pumpWidget(
              MaterialApp(home: MobilePocPage(session: sync)),
            );
            await observed.initialized.future;
            await tester.pump();
            await tester.tap(find.byType(CheckboxListTile));
            await tester.pump();
            server.sendGate = Completer<void>();
            server.sendStarted = Completer<void>();
            final send = find.text('선택한 1건 수동 전송 / 재시도');
            await tester.ensureVisible(send);
            await tester.tap(send);
            await server.sendStarted!.future;
            await tester.pump();
            if (!withdraw) server.logoutGate = Completer<void>();
            final button = find.text(
              withdraw ? '동의 철회 · 대기 취소 · 서버 사본 삭제' : '로그아웃',
            );
            await tester.ensureVisible(button);
            await tester.tap(button);
            await tester.pump();
            if (withdraw) {
              await observed.revoked.future;
              await tester.pump();
              expect(
                (await db.query('mobile_queue')).single['status'],
                'cancelled',
              );
              expect(
                (await db.query('mobile_deletions')).single['status'],
                'confirmed',
              );
            } else {
              expect(sync.loggedIn, isFalse);
              expect(server.loggedOut, isTrue);
              server.logoutGate!.complete();
              await observed.loggedOut.future;
            }
            server.sendGate!.complete();
            await observed.sent.future;
            await tester.pump();
            expect(find.text('서버 저장 확인 완료.'), findsNothing);
            expect(
              find.text(
                withdraw ? '철회 및 서버 사본 삭제 확인 완료.' : '로그아웃 완료. 대기 전송을 일시정지했습니다.',
              ),
              findsOneWidget,
            );
            expect(
              (await db.query('mobile_queue')).single['status'],
              withdraw ? 'cancelled' : 'queued',
            );
            expect(tester.takeException(), isNull);
          });
        },
      );
    }

    testWidgets('leaving and reopening cancels login and rejects late handoff', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const channel = MethodChannel('jesuslife/mobile_browser');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => null,
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        });
        await tester.pumpWidget(
          MaterialApp(home: MobilePocPage(session: sync)),
        );
        await tester.pump();
        await tester.tap(find.text('시스템 브라우저 로그인'));
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(home: MobilePocPage(session: sync)),
        );
        await tester.pump();
        final response = Completer<void>();
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(
              'returnUri',
              '$mobileReturnUri?transaction=synthetic-transaction&code=${'x' * 43}',
            ),
          ),
          (_) => response.complete(),
        );
        await response.future;
        await tester.pump();
        expect(sync.loggedIn, isFalse);
        expect(find.textContaining('인증 확인 실패'), findsOneWidget);
        await tester.tap(find.text('시스템 브라우저 로그인'));
        await tester.pump();
        await login(sync);
        expect(sync.loggedIn, isTrue);
        await expectLater(
          sync.finishLogin(
            '$mobileReturnUri?transaction=synthetic-transaction&code=${'x' * 43}',
          ),
          throwsStateError,
        );
      });
    });

    test('cancelled in-flight exchange cannot restore session', () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      var firstExchange = true;
      final observed = MobileSync(db, (method, path, body, token) async {
        if (path.endsWith('session-exchange') && firstExchange) {
          firstExchange = false;
          started.complete();
          await gate.future;
        }
        return server.call(method, path, body, token);
      });
      addTearDown(observed.dispose);
      await observed.beginLogin();
      final pending = expectLater(
        observed.finishLogin(
          '$mobileReturnUri?transaction=synthetic-transaction&code=${'x' * 43}',
        ),
        throwsStateError,
      );
      await started.future;
      observed.cancelPendingLogin();
      gate.complete();
      await pending;
      expect(observed.loggedIn, isFalse);
      await login(observed);
      expect(observed.loggedIn, isTrue);
    });

    test(
      'navigation cancellation also clears token during login status check',
      () async {
        final gate = Completer<void>();
        final started = Completer<void>();
        var hold = true;
        final observed = MobileSync(db, (method, path, body, token) async {
          if (path.endsWith('/consent') && hold) {
            hold = false;
            started.complete();
            await gate.future;
          }
          return server.call(method, path, body, token);
        });
        addTearDown(observed.dispose);
        final pending = expectLater(login(observed), throwsStateError);
        await started.future;
        observed.cancelPendingLogin();
        expect(observed.loggedIn, isFalse);
        gate.complete();
        await pending;
        expect(observed.loggedIn, isFalse);
        await login(observed);
        expect(observed.loggedIn, isTrue);
      },
    );

    test('cancelled transaction creation cannot accept a late return', () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final observed = MobileSync(db, (method, path, body, token) async {
        if (path.endsWith('login-transactions')) {
          started.complete();
          await gate.future;
        }
        return server.call(method, path, body, token);
      });
      addTearDown(observed.dispose);
      final pending = expectLater(observed.beginLogin(), throwsStateError);
      await started.future;
      observed.cancelPendingLogin();
      gate.complete();
      await pending;
      await expectLater(
        observed.finishLogin(
          '$mobileReturnUri?transaction=synthetic-transaction&code=${'x' * 43}',
        ),
        throwsStateError,
      );
      expect(observed.loggedIn, isFalse);
    });

    test(
      'successful sent item replays stored UUID and identical payload',
      () async {
        await login(sync);
        await sync.grant();
        await sync.selectSynthetic(1);
        final before = (await db.query('mobile_queue')).single;
        await sync.send();
        await sync.selectSynthetic(2);
        await sync.send();
        expect(server.uploads, [before['payload'], before['payload']]);
        final after = (await db.query('mobile_queue')).single;
        expect(after['sync_id'], before['sync_id']);
        expect(after['payload'], before['payload']);
        expect(after['status'], 'sent');
        expect(server.records, hasLength(1));
      },
    );

    test(
      'sent rows isolate account and generation and block cancelled',
      () async {
        await login(sync);
        await sync.grant();
        await sync.selectSynthetic(1);
        await sync.send();
        final before = (await db.query('mobile_queue')).single;
        await sync.logout();
        server.owner = 'synthetic-b';
        await login(sync);
        await expectLater(sync.send(), throwsStateError);
        await sync.logout();
        server.owner = 'synthetic-a';
        server.generation++;
        await login(sync);
        await expectLater(sync.send(), throwsStateError);
        server.generation = before['generation'] as int;
        await sync.refreshStatus();
        await db.update('mobile_queue', {'status': 'cancelled'});
        await expectLater(sync.send(), throwsStateError);
        expect(server.uploads, hasLength(1));
        final after = (await db.query('mobile_queue')).single;
        expect(after['payload'], before['payload']);
        expect(after['sync_id'], before['sync_id']);
        expect(after['status'], 'cancelled');
      },
    );

    test('selection, authentication and communication messages differ', () {
      expect(
        mobileFailureMessage(StateError('select_synthetic_first')),
        contains('선택한 합성 완료가 없습니다'),
      );
      expect(
        mobileFailureMessage(StateError('login_required')),
        contains('인증 확인 실패'),
      );
      expect(
        mobileFailureMessage(StateError('communication_failed')),
        contains('통신 실패'),
      );
      expect(
        mobileFailureMessage(StateError('unexpected')),
        isNot(contains('인증')),
      );
    });

    test('resume without pending SQLite deletion returns false', () async {
      await login(sync);
      await sync.grant();
      expect(await sync.resumeDeletion(), isFalse);
      expect(await db.query('mobile_deletions'), isEmpty);
    });
    test('cold start rejects handoff without memory PKCE transaction', () async {
      await expectLater(
        sync.finishLogin(
          '$mobileReturnUri?transaction=synthetic-transaction&code=${'x' * 43}',
        ),
        throwsStateError,
      );
      expect(sync.loggedIn, isFalse);
    });

    test(
      'manual consent, single immutable UUID, lost send response replay',
      () async {
        await login(sync);
        await expectLater(sync.selectSynthetic(1), throwsStateError);
        await sync.grant();
        await sync.selectSynthetic(1);
        await sync.selectSynthetic(2);
        expect(await db.query('mobile_queue'), hasLength(1));
        server.loseSendResponse = true;
        await expectLater(sync.send(), throwsStateError);
        final before = (await db.query('mobile_queue')).single;
        expect(before['status'], 'queued');
        server.loseSendResponse = false;
        await sync.send();
        expect(server.records, hasLength(1));
        final after = (await db.query('mobile_queue')).single;
        expect(after['sync_id'], before['sync_id']);
        expect(after['status'], 'sent');
        expect(jsonDecode(after['payload'] as String).keys.toSet(), {
          'sync_id',
          'generation',
          'course_number',
          'participation_mode',
          'completed_at',
          'synthetic',
        });
      },
    );

    test(
      'offline queue survives restart, token absent, B cannot send A queue',
      () async {
        await login(sync);
        await sync.grant();
        await sync.selectSynthetic(1);
        server.offline = true;
        await expectLater(sync.send(), throwsStateError);
        sync.dispose();
        await db.close();
        db = await openDatabase(
          '${directory.path}/mobile-fixture.db',
          version: 1,
        );
        sync = MobileSync(db, server.call);
        expect(sync.loggedIn, isFalse);
        server.offline = false;
        server.owner = 'synthetic-b';
        await login(sync);
        await sync.grant();
        await expectLater(sync.send(), throwsStateError);
        expect(server.records, isEmpty);
        expect(
          (await db.query('mobile_queue')).single['account'],
          'synthetic-a',
        );
        final rows = await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table'",
        );
        expect(rows.toString(), isNot(contains('token')));
      },
    );

    test('lost deletion response persists and restart confirms same-account deletion', () async {
      await login(sync);
      await sync.grant();
      await sync.selectSynthetic(1);
      await sync.send();
      server.loseDeleteResponse = true;
      await expectLater(sync.revoke(), throwsStateError);
      expect((await db.query('mobile_deletions')).single['status'], 'pending');
      expect((await db.query('mobile_queue')).single['status'], 'cancelled');
      expect(server.records, isEmpty);
      sync.dispose();
      await db.close();
      db = await openDatabase(
        '${directory.path}/mobile-fixture.db',
        version: 1,
      );
      sync = MobileSync(db, server.call);
      server.loseDeleteResponse = false;
      await login(sync);
      expect(
        (await db.query('mobile_deletions')).single['status'],
        'confirmed',
      );
      expect(sync.consentActive, isFalse);
      await sync.grant();
      await expectLater(sync.send(), throwsStateError);
    });

    test(
      'revoke during upload ignores late success and keeps cancellation',
      () async {
        await login(sync);
        await sync.grant();
        await sync.selectSynthetic(1);
        server.sendGate = Completer<void>();
        server.sendStarted = Completer<void>();
        final pending = sync.send();
        await server.sendStarted!.future;
        await sync.revoke();
        server.sendGate!.complete();
        await pending;
        expect((await db.query('mobile_queue')).single['status'], 'cancelled');
        expect(
          (await db.query('mobile_deletions')).single['status'],
          'confirmed',
        );
        expect(server.records, isEmpty);
      },
    );

    test(
      'logout pauses queue, disposes server session and ignores late response',
      () async {
        await login(sync);
        await sync.grant();
        await sync.selectSynthetic(1);
        server.sendGate = Completer<void>();
        server.sendStarted = Completer<void>();
        final pending = sync.send();
        await server.sendStarted!.future;
        await sync.logout();
        server.sendGate!.complete();
        await pending;
        expect(sync.loggedIn, isFalse);
        expect(server.loggedOut, isTrue);
        expect((await db.query('mobile_queue')).single['status'], 'queued');
        await expectLater(sync.send(), throwsStateError);
      },
    );

    test('migration failure rolls back auxiliary tables and preserves original bytes', () async {
      final original = File('${directory.path}/existing-records.db');
      final originalApp = app.AppDatabase(databasePath: original.path);
      final originalDb = await originalApp.database;
      final originalStore = app.SqliteCompletionRepository(originalApp);
      final record = app.CompletionRecord(
        id: 'synthetic-original',
        courseNumber: 1,
        courseTitle: '? ???',
        participationMode: app.ParticipationMode.solo,
        myName: '??',
        partnerName: '',
        completedAt: DateTime.utc(2026),
        mySignedAt: DateTime.utc(2026),
        partnerSignedAt: null,
        graceReflection: '?? ??',
        graceReflectionPending: false,
      );
      await originalStore.add(record);
      await originalStore.stageRecovery(
        app.CompletionRecovery(
          before: record,
          record: record.withGraceReflection('?? ???'),
          attemptedAt: DateTime.utc(2026),
        ),
      );
      await originalDb.close();
      final bytes = await original.readAsBytes();
      final failedPath = '${directory.path}/failed.db';
      await expectLater(
        openDatabase(
          failedPath,
          version: 1,
          onCreate: (tx, _) async {
            await createMobileTables(tx);
            throw StateError('injected_migration_failure');
          },
        ),
        throwsStateError,
      );
      final failed = await openDatabase(failedPath);
      expect(await failed.getVersion(), 0);
      expect(
        await failed.rawQuery(
          "SELECT name FROM sqlite_master WHERE name LIKE 'mobile_%'",
        ),
        isEmpty,
      );
      await failed.close();
      expect(await original.readAsBytes(), bytes);
      final restored = await openDatabase(
        failedPath,
        version: 1,
        onCreate: (tx, _) => createMobileTables(tx),
      );
      expect(await restored.getVersion(), 1);
      await restored.close();
      expect(await original.readAsBytes(), bytes);
    });
  });
}
