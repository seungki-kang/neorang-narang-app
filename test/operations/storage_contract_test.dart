import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:neorang_narang_app/main.dart';
import '../support/operations_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  for (final backend in ['prefs', 'sqlite']) {
    group('operations $backend', () {
      late CompletionTrashStore store;
      Database? db;
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        db = null;
        if (backend == 'sqlite') {
          final app = AppDatabase(databasePath: inMemoryDatabasePath);
          db = await app.database;
          store = SqliteCompletionRepository(app);
        } else {
          store = CompletionRepository();
        }
      });
      tearDown(() async { await db?.close(); });
      for (final scenario in operationsScenarios().entries) {
        test(scenario.key, () => scenario.value(store));
      }
    });
  }
}
