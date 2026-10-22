import 'package:flutter_test/flutter_test.dart';
import 'package:neorang_narang_app/main.dart';
import '../support/operations_contract.dart';

void main() {
  // Explicit business examples, not the implementation's arithmetic copied back.
  final cases = <int, List<int>>{
    0: [0, 1, 0], 1: [0, 1, 1], 49: [0, 1, 49],
    50: [1, 2, 0], 51: [1, 2, 1], 99: [1, 2, 49],
    100: [2, 3, 0], 149: [2, 3, 49], 150: [3, 4, 0],
  };
  for (final entry in cases.entries) {
    test('progress boundary ${entry.key}', () {
      final value = ChapterProgress(entry.key);
      expect([value.stars, value.season, value.countInSeason], entry.value);
    });
  }
  test('reflection update preserves all identity and signature fields', () {
    final original = operationsRecord('identity');
    final updated = original.withGraceReflection('changed');
    final expected = Map<String, dynamic>.from(original.toJson());
    expected['graceReflection'] = 'changed';
    expected['graceReflectionPending'] = false;
    expect(updated.toJson(), expected);
    expect(original.graceReflection, 'fixture');
  });
  test('unknown recovery version is rejected', () {
    final json = CompletionRecovery(record: operationsRecord('a'), attemptedAt: DateTime.utc(2026)).toJson();
    json['schemaVersion'] = 999;
    expect(() => CompletionRecovery.fromJson(json), throwsA(isA<StorageReadException>()));
  });
  test('recovery with changed identity is rejected before applying', () {
    final json = CompletionRecovery(before: operationsRecord('a'), record: operationsRecord('a'), attemptedAt: DateTime.utc(2026)).toJson();
    (json['record'] as Map<String, dynamic>)['courseNumber'] = 2;
    expect(() => CompletionRecovery.fromJson(json), throwsA(isA<StorageReadException>()));
  });
  test('recovery with missing together signature is rejected', () {
    final json = CompletionRecovery(record: operationsRecord('a'), attemptedAt: DateTime.utc(2026)).toJson();
    (json['record'] as Map<String, dynamic>)['partnerSignedAt'] = null;
    expect(() => CompletionRecovery.fromJson(json), throwsA(isA<StorageReadException>()));
  });
}
