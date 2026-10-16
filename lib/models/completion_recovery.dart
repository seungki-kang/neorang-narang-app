part of '../main.dart';

class CompletionRecovery {
  const CompletionRecovery({
    required this.record,
    required this.attemptedAt,
    this.before,
    this.deletedAt,
    this.suspendedRecoveries = const [],
  });
  final CompletionRecord record;
  final CompletionRecord? before;
  final DateTime attemptedAt;
  final DateTime? deletedAt;
  final List<CompletionRecovery> suspendedRecoveries;
  bool get isTrash => deletedAt != null;
  String get id =>
      (isTrash
          ? 'trash:'
          : before == null
          ? 'new:'
          : 'edit:') +
      record.id;
  Map<String, dynamic> toJson() => {
    'kind': isTrash ? 'deletedCompletion' : 'saveFailure',
    'schemaVersion': 1,
    if (isTrash) 'deletedAt': deletedAt!.toIso8601String(),
    if (isTrash) 'snapshot': record.toJson() else 'record': record.toJson(),
    if (isTrash)
      'suspendedRecoveries': suspendedRecoveries
          .map((e) => e.toJson())
          .toList(),
    'before': before?.toJson(),
    'attemptedAt': attemptedAt.toIso8601String(),
  };
  factory CompletionRecovery.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    if (kind != null &&
        (json['schemaVersion'] != 1 ||
            (kind != 'deletedCompletion' && kind != 'saveFailure'))) {
      throw const StorageReadException();
    }
    final trash = kind == 'deletedCompletion';
    final value = CompletionRecovery(
      record: CompletionRecord.fromJson(
        Map<String, dynamic>.from(json[trash ? 'snapshot' : 'record'] as Map),
      ),
      before: json['before'] == null
          ? null
          : CompletionRecord.fromJson(
              Map<String, dynamic>.from(json['before'] as Map),
            ),
      attemptedAt: DateTime.parse(json['attemptedAt'] as String),
      deletedAt: trash ? DateTime.parse(json['deletedAt'] as String) : null,
      suspendedRecoveries: trash
          ? (json['suspendedRecoveries'] as List? ?? [])
                .map(
                  (e) => CompletionRecovery.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList()
          : const [],
    );
    if ((value.record.participationMode == ParticipationMode.together &&
            value.record.partnerSignedAt == null) ||
        value.record.id.isEmpty ||
        (trash &&
            (value.before != null ||
                value.suspendedRecoveries.any(
                  (e) => e.isTrash || e.record.id != value.record.id,
                ))) ||
        (value.before != null &&
            !sameCompletionIdentity(value.before!, value.record))) {
      throw const StorageReadException();
    }
    return value;
  }
}

bool sameCompletion(CompletionRecord a, CompletionRecord b) =>
    mapEquals(a.toJson(), b.toJson());
bool sameCompletionIdentity(CompletionRecord a, CompletionRecord b) {
  final left = Map<String, dynamic>.from(a.toJson())
    ..remove('graceReflection')
    ..remove('graceReflectionPending');
  final right = Map<String, dynamic>.from(b.toJson())
    ..remove('graceReflection')
    ..remove('graceReflectionPending');
  return mapEquals(left, right);
}

CompletionRecord applyRecovery(
  CompletionRecovery entry,
  CompletionRecord? current,
) {
  if (entry.isTrash) throw StateError('trash_requires_restore');
  if (entry.before == null) {
    if (current == null) return entry.record;
    if (!current.hasSameCompletionContent(entry.record)) {
      throw StateError('completion_conflict');
    }
    return current;
  }
  if (current == null) throw StateError('completion_missing');
  if (sameCompletion(current, entry.record)) return current;
  if (!sameCompletion(current, entry.before!)) {
    throw StateError('completion_changed');
  }
  if (!sameCompletionIdentity(current, entry.record)) {
    throw StateError('completion_identity_changed');
  }
  return entry.record;
}
