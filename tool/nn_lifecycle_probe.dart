import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:neorang_narang_app/main.dart' as app;

const probeBuild = String.fromEnvironment('NN_PROBE_BUILD');
const stateKey = 'nn_lifecycle_probe_state_v1';
const baselineKey = 'nn_lifecycle_probe_baseline_v1';
const owner = 'NN_LIFECYCLE_SYNTHETIC';
final stamp = DateTime.utc(2026, 10, 22, 1, 2, 3);

class ProbeFailure implements Exception {
  const ProbeFailure(this.code);
  final String code;
}

void require(bool ok, String code) {
  if (!ok) {
    throw ProbeFailure(code);
  }
}

app.CompletionRecord record(String id, int chapter, {bool together = false}) =>
    app.CompletionRecord(
      id: 'nn-lifecycle-$id',
      courseNumber: chapter,
      courseTitle: chapter == 1 ? '다 끝났다' : '다 이루었다',
      participationMode: together
          ? app.ParticipationMode.together
          : app.ParticipationMode.solo,
      myName: owner,
      partnerName: together ? 'NN_PARTNER' : '',
      completedAt: stamp.add(const Duration(seconds: 2)),
      mySignedAt: stamp,
      partnerSignedAt: together ? stamp.add(const Duration(seconds: 1)) : null,
      graceReflection: 'SYNTHETIC_REFLECTION_$id',
      graceReflectionPending: false,
    );

app.GraceDraft grace() => app.GraceDraft(
  id: record('signature', 2, together: true).id,
  courseNumber: 2,
  courseTitle: '다 이루었다',
  participationMode: app.ParticipationMode.together,
  myName: owner,
  partnerName: 'NN_PARTNER',
  reflection: record('signature', 2, together: true).graceReflection,
);

app.QuestionDraft question() => app.QuestionDraft(
  courseNumber: 2,
  courseTitle: '다 이루었다',
  participationMode: app.ParticipationMode.together,
  myDisplayName: owner,
  partnerDisplayName: 'NN_PARTNER',
  firstAskerIsMe: false,
  currentQuestionIndex: 3,
  savedAt: stamp,
);

app.CompletionRecovery edit() => app.CompletionRecovery(
  before: record('solo', 1),
  record: record('solo', 1).withGraceReflection('SYNTHETIC_EDIT'),
  attemptedAt: stamp,
);

app.CompletionRecovery unsaved() => app.CompletionRecovery(
  record: record('unsaved', 2),
  attemptedAt: stamp,
);

// Sort map keys and collection order so equality compares content, not SQL order.
Object? canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonical(value[key])};
  }
  if (value is List) {
    return value.map(canonical).toList();
  }
  return value;
}
String encoded(Object? value) => jsonEncode(canonical(value));
void same(Object? actual, Object? expected, String code) =>
    require(encoded(actual) == encoded(expected), code);

Future<Map<String, Object?>> snapshot(app.CompletionTrashStore store) async {
  final records = (await store.loadAll())..sort((a, b) => a.id.compareTo(b.id));
  final recoveries = (await store.listRecoveries())
    ..sort((a, b) => a.id.compareTo(b.id));
  final trash = (await store.listTrash())..sort((a, b) => a.id.compareTo(b.id));
  final deleted = (await store.deletedIds())..sort();
  final names = await app.ParticipantPreferencesRepository().load();
  return {
    'records': records.map((r) => r.toJson()).toList(),
    'recoveries': recoveries.map((r) => r.toJson()).toList(),
    'trash': trash.map((r) => r.toJson()).toList(),
    'deleted': deleted,
    'question': (await app.questionDraftRepository.load())?.toJson(),
    'grace': (await app.graceDraftRepository.load())?.toJson(),
    'names': {'myName': names.myName, 'recentPartners': names.recentPartners},
    'count1': await store.countForCourse(1),
    'count2': await store.countForCourse(2),
  };
}

Future<void> setBaseline(
  app.CompletionTrashStore store,
  SharedPreferences prefs,
  String state,
) async {
  require(
    await prefs.setString(baselineKey, encoded(await snapshot(store))),
    'baseline_write',
  );
  require(await prefs.setString(stateKey, state), 'state_write');
}
Future<void> compareBaseline(
  app.CompletionTrashStore store,
  SharedPreferences prefs,
) async {
  final expected = prefs.getString(baselineKey);
  require(expected != null, 'baseline_missing_no_reseed');
  require(encoded(await snapshot(store)) == expected, 'persisted_snapshot_diff');
}

Future<void> verifyFixture(app.CompletionTrashStore store, bool signed) async {
  final records = await store.loadAll();
  require(records.length == 2, 'active_count');
  for (final expected in [record('solo', 1), record('together', 2, together: true)]) {
    final found = records.where((r) => r.id == expected.id).toList();
    require(found.length == 1, 'active_identity');
    same(found.single.toJson(), expected.toJson(), 'active_payload_or_signature');
  }
  require(await store.countForCourse(1) == 1, 'chapter1_count');
  require(await store.countForCourse(2) == 1, 'chapter2_count');
  final trash = await store.listTrash();
  require(trash.length == 1, 'trash_count');
  same(trash.single.record.toJson(), record('trash', 1).toJson(), 'trash_payload');
  require(trash.single.isTrash, 'trash_kind');
  require(await store.wasDeleted(record('trash', 1).id), 'trash_marker');
  require(await store.wasDeleted(record('permanent', 2).id), 'permanent_marker');
  require(await store.findById(record('permanent', 2).id) == null, 'permanent_absent');
  final pending = await store.listRecoveries();
  require(pending.length == 2, 'pending_count');
  for (final expected in [edit(), unsaved()]) {
    final found = pending.where((r) => r.id == expected.id).toList();
    require(found.length == 1, 'pending_identity');
    same(found.single.toJson(), expected.toJson(), 'pending_payload');
  }
  same((await app.questionDraftRepository.load())?.toJson(), question().toJson(), 'question_restore');
  final restored = await app.graceDraftRepository.load();
  require(restored != null, 'grace_restore');
  if (signed) {
    require(restored!.awaitingSignature, 'signature_stage');
    same(restored.pendingRecord?.toJson(), record('signature', 2, together: true).toJson(), 'pending_signatures');
    same(restored.copy().reflection, grace().reflection, 'signed_reflection');
  } else {
    same(restored!.toJson(), grace().toJson(), 'reflection_stage');
  }
  final names = await app.ParticipantPreferencesRepository().load();
  require(names.myName == owner, 'my_name');
  same(names.recentPartners, ['NN_PARTNER', 'NN_PREVIOUS'], 'partner_history');
}

Future<void> seed(app.CompletionTrashStore store) async {
  require((await store.loadAll()).isEmpty, 'seed_requires_empty_records');
  require((await store.listTrash()).isEmpty, 'seed_requires_empty_trash');
  require((await store.listRecoveries()).isEmpty, 'seed_requires_empty_pending');
  require(await app.graceDraftRepository.load() == null, 'seed_requires_empty_grace');
  await app.ParticipantPreferencesRepository().remember(owner, 'NN_PREVIOUS');
  await app.ParticipantPreferencesRepository().remember(owner, 'NN_PARTNER');
  for (final r in [record('solo', 1), record('together', 2, together: true), record('trash', 1), record('permanent', 2)]) {
    await app.CompletionActions(store).saveNew(r);
  }
  await store.deleteById(record('trash', 1).id);
  await store.deleteById(record('permanent', 2).id);
  await store.permanentlyDeleteTrash(record('permanent', 2).id);
  await store.stageRecovery(edit());
  await store.stageRecovery(unsaved());
  await app.questionDraftRepository.save(question());
  await app.graceDraftRepository.save(grace());
  await verifyFixture(store, false);
}

Future<void> verifyFinal(app.CompletionTrashStore store) async {
  final all = await store.loadAll();
  final expected = [edit().record, record('together', 2, together: true), record('trash', 1), unsaved().record, record('signature', 2, together: true)]
    ..sort((a, b) => a.id.compareTo(b.id));
  all.sort((a, b) => a.id.compareTo(b.id));
  same(all.map((r) => r.toJson()).toList(), expected.map((r) => r.toJson()).toList(), 'final_exact_records');
  require(await store.countForCourse(1) == 2, 'final_chapter1_count');
  require(await store.countForCourse(2) == 3, 'final_chapter2_count');
  require((await store.listTrash()).isEmpty, 'final_trash_empty');
  require((await store.listRecoveries()).isEmpty, 'final_pending_empty');
  require(await app.graceDraftRepository.load() == null, 'final_grace_cleared');
  require(await app.questionDraftRepository.load() == null, 'final_question_cleared');
  require(await store.wasDeleted(record('permanent', 2).id), 'final_tombstone');
  require(!await store.wasDeleted(record('trash', 1).id), 'restored_not_deleted');
  final names = await app.ParticipantPreferencesRepository().load();
  require(names.myName == owner, 'final_name');
  same(names.recentPartners, ['NN_PARTNER', 'NN_PREVIOUS'], 'final_partner_history');
}

Future<String> exercise() async {
  await app.initializeStorage();
  final target = app.completionRepository;
  require(target is app.SqliteCompletionRepository, 'real_android_sqlite_required');
  final store = target as app.CompletionTrashStore;
  final prefs = await SharedPreferences.getInstance();
  final state = prefs.getString(stateKey);
  if (state == null) {
    require(probeBuild == 'A', 'update_data_missing_no_reseed');
    await seed(store);
    await setBaseline(store, prefs, 'reflection');
    return 'seeded_reflection';
  }
  await compareBaseline(store, prefs);
  if (state == 'reflection') {
    require(probeBuild == 'A', 'wrong_stage');
    await verifyFixture(store, false);
    await app.graceDraftRepository.prepareCompletion(grace(), record('signature', 2, together: true));
    await verifyFixture(store, true);
    await setBaseline(store, prefs, 'signature');
    return 'reflection_restored_signature_prepared';
  }
  if (state == 'signature') {
    await verifyFixture(store, true);
    if (probeBuild == 'A') {
      return 'signature_restored';
    }
    require(probeBuild == 'B', 'build_unknown');
    // Verify everything before modifying any restored record.
    await store.retryRecovery(edit().id);
    await store.retryRecovery(unsaved().id);
    await store.restoreTrash(record('trash', 1).id);
    var replayRejected = false;
    try {
      await store.add(record('permanent', 2));
    } on StateError {
      replayRejected = true;
    }
    require(replayRejected, 'permanent_delete_replay_allowed');
    final pending = (await app.graceDraftRepository.load())!;
    await app.CompletionActions(store).saveNew(pending.pendingRecord!);
    await app.CompletionActions(store).saveNew(pending.pendingRecord!);
    await app.clearQuestionForGrace(pending);
    await app.graceDraftRepository.clearIfId(pending.id);
    await verifyFinal(store);
    await setBaseline(store, prefs, 'final');
    return 'update_preserved_and_recovery_completed';
  }
  require(state == 'final' && probeBuild == 'B', 'unexpected_state');
  await verifyFinal(store);
  return 'final_state_restored';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Refuse normal app data paths before initializeStorage opens the real DB.
  final directory = await getDatabasesPath();
  require(
    Platform.isAndroid && RegExp(r'/com\.example\.neorang_narang_app\.lifecycle\.r[a-f0-9]+/databases$').hasMatch(directory),
    'test_package_path_required',
  );
  final file = File('$directory/../files/nn-lifecycle-proof.json');
  final launchId = '${DateTime.now().microsecondsSinceEpoch}-$pid';
  var status = 'FAIL';
  var phase = 'failed';
  String? errorCode;
  try {
    phase = await exercise();
    status = 'PASS';
  } catch (error) {
    // Synthetic test codes only; never serialize app records or exception text.
    errorCode = error is ProbeFailure ? error.code : error.runtimeType.toString();
  }
  await file.parent.create(recursive: true);
  final payload = {
    'status': status,
    'build': probeBuild,
    'launchId': launchId,
    'pid': pid,
    'phase': phase,
    'errorType': errorCode,
  };
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(jsonEncode(payload), flush: true);
  await temporary.rename(file.path);
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text(
    '너랑나랑 테스트 전용\n$status\n$phase\n일반 사용자 기록은 사용하지 않습니다.',
    textAlign: TextAlign.center,
  )))));
}
