part of '../main.dart';

class GraceDraft {
  const GraceDraft({required this.id, required this.courseNumber,
    required this.courseTitle, required this.participationMode,
    required this.myName, required this.partnerName, this.reflection = '',
    this.awaitingSignature = false, this.pendingRecord});
  final String id;
  final int courseNumber;
  final String courseTitle;
  final ParticipationMode participationMode;
  final String myName;
  final String partnerName;
  final String reflection;
  final bool awaitingSignature;
  final CompletionRecord? pendingRecord;

  GraceDraft copy({String? reflection, bool? awaitingSignature,
      CompletionRecord? pendingRecord}) => GraceDraft(
    id: id, courseNumber: courseNumber, courseTitle: courseTitle,
    participationMode: participationMode, myName: myName,
    partnerName: partnerName, reflection: reflection ?? this.reflection,
    awaitingSignature: awaitingSignature ?? this.awaitingSignature,
    pendingRecord: pendingRecord ?? this.pendingRecord,
  );
  bool matchesCompletion(CompletionRecord record) {
    final expected = pendingRecord;
    if (expected != null) return record.hasSameCompletionContent(expected);
    return record.id == id && record.courseNumber == courseNumber &&
        record.courseTitle == courseTitle &&
        record.participationMode == participationMode &&
        record.myName == myName && record.partnerName == partnerName &&
        record.graceReflection == reflection && !record.graceReflectionPending &&
        (participationMode != ParticipationMode.together || record.partnerSignedAt != null);
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'courseNumber': courseNumber, 'courseTitle': courseTitle,
    'participationMode': participationMode.name, 'myName': myName,
    'partnerName': partnerName, 'reflection': reflection,
    'awaitingSignature': awaitingSignature,
    'pendingRecord': pendingRecord?.toJson(),
  };
  factory GraceDraft.fromJson(Map<String, dynamic> data) {
    final mode = data['participationMode'];
    if (mode != 'solo' && mode != 'together') {
      throw const StorageReadException();
    }
    final draft = GraceDraft(
      id: data['id'] as String, courseNumber: data['courseNumber'] as int,
      courseTitle: data['courseTitle'] as String,
      participationMode: mode == 'solo' ? ParticipationMode.solo : ParticipationMode.together,
      myName: data['myName'] as String, partnerName: data['partnerName'] as String,
      reflection: data['reflection'] as String,
      awaitingSignature: data['awaitingSignature'] as bool,
      pendingRecord: data['pendingRecord'] == null ? null
          : CompletionRecord.fromJson(Map<String, dynamic>.from(data['pendingRecord'] as Map)),
    );
    if (draft.id.isEmpty || (draft.pendingRecord != null &&
        draft.pendingRecord!.id != draft.id)) {
      throw const StorageReadException();
    }
    return draft;
  }
}

class GraceDraftRepository {
  static const storageKey = 'neorang_narang_grace_draft_v1';
  static const closedKey = 'neorang_narang_last_finished_grace_v1';
  Future<void>? _tail;

  Future<GraceDraft?> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;
    try {
      return GraceDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      throw const StorageReadException();
    }
  }

  Future<GraceDraft?> load() async {
    final pending = _tail;
    if (pending != null) await pending;
    return _read();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final pending = _tail;
    final result = pending == null
        ? Future<void>.sync(operation)
        : pending.then((_) => operation());
    late final Future<void> barrier;
    final completed = result.whenComplete(() {
      if (identical(_tail, barrier)) _tail = null;
    });
    barrier = completed.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _tail = barrier;
    return completed;
  }

  Future<void> save(GraceDraft draft) => _enqueue(() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(closedKey) == draft.id) {
      throw StateError('grace_session_already_finished');
    }
    final old = await _read();
    if (old != null && old.id != draft.id) {
      throw StateError('another_grace_draft_exists');
    }
    var value = draft;
    if (old != null && old.pendingRecord != null) {
      if (draft.reflection != old.reflection ||
          (draft.pendingRecord != null &&
           !old.pendingRecord!.hasSameCompletionContent(draft.pendingRecord!))) {
        throw StateError('pending_completion_conflict');
      }
      value = old;
    } else if (old?.awaitingSignature == true && !draft.awaitingSignature) {
      return; // A delayed reflection autosave must not reverse the stage.
    }
    if (!await prefs.setString(storageKey, jsonEncode(value.toJson()))) {
      throw StateError('grace_draft_write_failed');
    }
  });

  Future<CompletionRecord> prepareCompletion(
      GraceDraft draft, CompletionRecord candidate) async {
    if (candidate.id != draft.id) {
      throw StateError('completion_identity_conflict');
    }
    await save(draft.copy(awaitingSignature: true, pendingRecord: candidate));
    final stored = await load();
    if (stored == null || stored.id != draft.id || stored.pendingRecord == null) {
      throw StateError('pending_completion_missing');
    }
    return stored.pendingRecord!;
  }

  Future<void> clearIfId(String id) => _enqueue(() async {
    final old = await _read();
    if (old == null || old.id != id) return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(closedKey, id)) {
      throw StateError('grace_finish_marker_failed');
    }
    if (!await prefs.remove(storageKey)) {
      throw StateError('grace_draft_remove_failed');
    }
  });
}

final GraceDraftRepository graceDraftRepository = GraceDraftRepository();

Future<void> clearQuestionForGrace(GraceDraft grace) async {
  final question = await questionDraftRepository.load();
  if (question != null && question.courseNumber == grace.courseNumber &&
      question.participationMode == grace.participationMode &&
      question.myDisplayName == grace.myName &&
      question.partnerDisplayName == grace.partnerName) {
    await questionDraftRepository.clear();
  }
}


class GraceConflictRecovery {
  static const archiveKey = 'neorang_narang_grace_conflict_archive_v1';

  static bool canUseDraft(GraceDraft draft, CompletionRecord saved) {
    final pending = draft.pendingRecord;
    final source = pending ?? saved.withGraceReflection(draft.reflection);
    return saved.id == draft.id && saved.courseNumber == draft.courseNumber &&
        saved.courseTitle == draft.courseTitle &&
        saved.participationMode == draft.participationMode &&
        saved.myName == draft.myName && saved.partnerName == draft.partnerName &&
        saved.withGraceReflection(source.graceReflection)
            .hasSameCompletionContent(source.withGraceReflection(source.graceReflection));
  }

  static Future<List<Map<String, dynamic>>> archives() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(archiveKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((entry) {
        final value = Map<String, dynamic>.from(entry as Map);
        CompletionRecord.fromJson(Map<String, dynamic>.from(value['saved'] as Map));
        GraceDraft.fromJson(Map<String, dynamic>.from(value['draft'] as Map));
        if (value['choice'] != 'saved' && value['choice'] != 'draft') {
          throw const StorageReadException();
        }
        return value;
      }).toList();
    } catch (_) {
      throw const StorageReadException();
    }
  }

  static Future<void> resolve({required GraceDraft draft,
      required CompletionRecord saved, required bool useDraft,
      CompletionStore? store}) async {
    final target = store ?? completionRepository;
    if (useDraft && !canUseDraft(draft, saved)) {
      throw StateError('recovery_identity_conflict');
    }
    final currentDraft = await graceDraftRepository.load();
    if (currentDraft == null || jsonEncode(currentDraft.toJson()) != jsonEncode(draft.toJson())) {
      throw StateError('recovery_draft_changed');
    }
    final records = await target.loadAll();
    final existing = records.where((record) => record.id == saved.id).toList();
    if (existing.length != 1 || jsonEncode(existing.single.toJson()) != jsonEncode(saved.toJson())) {
      throw StateError('recovery_completion_changed');
    }
    final entries = await archives();
    // Keep every original snapshot, including a second choice after a partial failure.
    final snapshot = <String, dynamic>{
      'saved': saved.toJson(), 'draft': draft.toJson(),
      'choice': useDraft ? 'draft' : 'saved',
    };
    if (!entries.any((entry) => jsonEncode(entry) == jsonEncode(snapshot))) {
      entries.add(snapshot);
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(entries);
    if (!await prefs.setString(archiveKey, encoded) || prefs.getString(archiveKey) != encoded) {
      throw StateError('recovery_archive_failed');
    }
    final reflection = draft.pendingRecord?.graceReflection ?? draft.reflection;
    if (useDraft) {
      await target.saveGraceReflection(saved.id, reflection);
    }
    final expected = useDraft ? saved.withGraceReflection(reflection) : saved;
    final verified = (await target.loadAll()).where((record) => record.id == saved.id).toList();
    if (verified.length != 1 || jsonEncode(verified.single.toJson()) != jsonEncode(expected.toJson())) {
      throw StateError('recovery_verify_failed');
    }
    await clearQuestionForGrace(draft);
    await graceDraftRepository.clearIfId(draft.id);
  }
}

class GraceConflictPage extends StatefulWidget {
  const GraceConflictPage({super.key, required this.draft, required this.saved});
  final GraceDraft draft;
  final CompletionRecord saved;
  @override
  State<GraceConflictPage> createState() => _GraceConflictPageState();
}

class _GraceConflictPageState extends State<GraceConflictPage> {
  bool saving = false;
  String? error;
  Future<void> resolve(bool useDraft) async {
    if (saving) return;
    setState(() { saving = true; error = null; });
    try {
      await GraceConflictRecovery.resolve(draft: widget.draft,
          saved: widget.saved, useDraft: useDraft);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '복구를 완료하지 못했습니다. 두 내용을 보존했습니다. 첫 화면으로 돌아가 다시 확인해 주세요.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => saving = false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomePage()), (_) => false);
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('은혜 기록 복구'), automaticallyImplyLeading: !saving),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('같은 회차의 은혜 내용이 서로 다릅니다. 두 내용은 복구 보관함에 보존하고, 선택한 내용을 완료 기록에 남깁니다.'),
        const SizedBox(height: 16),
        const Text('기존 완료 기록', style: TextStyle(fontWeight: FontWeight.bold)),
        SelectableText(widget.saved.graceReflection.isEmpty ? '(내용 없음)' : widget.saved.graceReflection),
        const SizedBox(height: 24),
        const Text('마무리 대기 기록', style: TextStyle(fontWeight: FontWeight.bold)),
        SelectableText(widget.draft.pendingRecord?.graceReflection ?? widget.draft.reflection),
        if (widget.draft.pendingRecord != null &&
            widget.draft.reflection != widget.draft.pendingRecord!.graceReflection) ...[
          const SizedBox(height: 16), const Text('임시저장에 남은 다른 내용'),
          SelectableText(widget.draft.reflection),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: saving ? null : () => resolve(false),
          child: const Text('기존 완료 기록 유지')),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: saving || !GraceConflictRecovery.canUseDraft(widget.draft, widget.saved)
            ? null : () => resolve(true), child: const Text('마무리 대기 내용 반영')),
        const Text('회차 수는 늘어나지 않습니다. 기존 서명 시각은 유지됩니다. 선택하지 않은 내용은 첫 화면 위의 복구 보관함에서 볼 수 있습니다.'),
        if (!GraceConflictRecovery.canUseDraft(widget.draft, widget.saved))
          const Text('참여자 또는 회차 정보도 달라 내용 교체는 제한됩니다. 기존 기록 유지로 두 원본을 보관할 수 있습니다.'),
        if (saving) const Center(child: CircularProgressIndicator()),
        if (error != null) Text(error!),
      ]),
    ),
  );
}

class GraceRecoveryArchivePage extends StatefulWidget {
  const GraceRecoveryArchivePage({super.key});
  @override
  State<GraceRecoveryArchivePage> createState() => _GraceRecoveryArchivePageState();
}
class _GraceRecoveryArchivePageState extends State<GraceRecoveryArchivePage> {
  late final Future<List<Map<String, dynamic>>> entries = GraceConflictRecovery.archives();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('복구 보관함')),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: entries, builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Text('보관 기록을 읽지 못했습니다. 원본은 변경하지 않았습니다.'));
      }
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      if (snapshot.data!.isEmpty) return const Center(child: Text('복구 보관 기록이 없습니다.'));
      return ListView(padding: const EdgeInsets.all(24), children: snapshot.data!.reversed.map((entry) {
        final saved = CompletionRecord.fromJson(Map<String, dynamic>.from(entry['saved'] as Map));
        final draft = GraceDraft.fromJson(Map<String, dynamic>.from(entry['draft'] as Map));
        return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${saved.courseNumber}장 · ${saved.courseTitle}'),
            Text(entry['choice'] == 'draft' ? '마무리 대기 내용 선택' : '기존 완료 기록 선택'),
            const SizedBox(height: 12), const Text('기존 완료 내용'),
            SelectableText(saved.graceReflection),
            const SizedBox(height: 12), const Text('마무리 대기 내용'),
            SelectableText(draft.pendingRecord?.graceReflection ?? draft.reflection),
            if (draft.pendingRecord != null && draft.reflection != draft.pendingRecord!.graceReflection) ...[
              const SizedBox(height: 12), const Text('임시저장에 남은 다른 내용'),
              SelectableText(draft.reflection),
            ],
          ],
        )));
      }).toList());
    }),
  );
}
