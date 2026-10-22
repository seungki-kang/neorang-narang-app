import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:neorang_narang_app/main.dart';
import '../test/support/operations_contract.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real sqflite platform plugin, not FFI and not a SharedPreferences mock.
  // Never invoke main()/initializeStorage(): those open the user's normal DB.
  for (final scenario in operationsScenarios().entries) {
    testWidgets('device sqlite ${scenario.key}', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('SQLite test fixture'))));
      await tester.runAsync(() async {
        final dir = await Directory('${await getDatabasesPath()}/nn-operations-${DateTime.now().microsecondsSinceEpoch}').create();
        final app = AppDatabase(databasePath: '${dir.path}/fixture.db');
        final db = await app.database;
        try {
          await scenario.value(SqliteCompletionRepository(app));
        } finally {
          await db.close();
          await dir.delete(recursive: true);
        }
      });
    });
  }
  testWidgets('device sqlite closed file reopens with pending recovery', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('SQLite reopen fixture'))));
    await tester.runAsync(() async {
      final dir = await Directory('${await getDatabasesPath()}/nn-reopen-${DateTime.now().microsecondsSinceEpoch}').create();
      final path = '${dir.path}/fixture.db';
      Database? db;
      try {
        final firstApp = AppDatabase(databasePath: path);
        db = await firstApp.database;
        final first = SqliteCompletionRepository(firstApp);
        final original = operationsRecord('mobile');
        final edit = CompletionRecovery(before: original, record: original.withGraceReflection('after reopen'), attemptedAt: DateTime.utc(2026));
        await first.add(original);
        await first.stageRecovery(edit);
        await db.close();
        final nextApp = AppDatabase(databasePath: path);
        db = await nextApp.database;
        final next = SqliteCompletionRepository(nextApp);
        expect((await next.findById(original.id))!.toJson(), original.toJson());
        expect((await next.listRecoveries()).single.toJson(), edit.toJson());
        await next.retryRecovery(edit.id);
        expect((await next.loadAll()).single.toJson(), edit.record.toJson());
        expect(await next.listRecoveries(), isEmpty);
      } finally {
        await db?.close();
        await dir.delete(recursive: true);
      }
    });
  });
}
