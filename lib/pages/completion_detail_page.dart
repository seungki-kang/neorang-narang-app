part of '../main.dart';

class CompletionDetailPage extends StatefulWidget {
  const CompletionDetailPage({
    super.key,
    required this.record,
    required this.store,
    this.onChanged,
  });
  final CompletionRecord record;
  final CompletionEditingStore store;
  final Future<void> Function()? onChanged;
  @override
  State<CompletionDetailPage> createState() => _CompletionDetailPageState();
}

class _CompletionDetailPageState extends State<CompletionDetailPage> {
  late CompletionRecord record = widget.record;
  late final TextEditingController controller = TextEditingController(
    text: record.graceReflection,
  );
  bool editing = false;
  bool keepInHeart = false;
  bool busy = false;
  String? error;
  CompletionActions get actions => CompletionActions(widget.store);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<bool> confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> save() async {
    if (busy) return;
    final text = keepInHeart ? '' : controller.text.trim();
    if (!keepInHeart && text.isEmpty) {
      setState(() => error = '은혜 내용을 입력해 주세요. 공백만 저장할 수 없습니다.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    if (keepInHeart && record.graceReflection.trim().isNotEmpty) {
      final approved = await confirm(
        '마음에 담고 마무리할까요?',
        '저장하면 기존 은혜 본문이 지워지고 마음에 담고 마무리한 상태로 변경됩니다.',
        '변경하고 저장',
      );
      if (!mounted) return;
      if (!approved) {
        setState(() => busy = false);
        return;
      }
    }
    try {
      await actions.saveEdit(record, text);
      final saved = await widget.store.findById(record.id);
      if (saved == null ||
          !sameCompletion(saved, record.withGraceReflection(text))) {
        throw StateError('edit_unverified');
      }
      await widget.onChanged?.call();
      if (!mounted) return;
      setState(() {
        record = saved;
        editing = false;
        busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              '저장하지 못했습니다. 기존 기록과 입력을 유지했습니다. 다시 저장하거나 저장되지 않은 기록에서 확인해 주세요.';
        });
      }
    }
  }

  Future<void> delete() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final related =
          (await widget.store.listRecoveries()).any(
            (r) => r.record.id == record.id,
          ) ||
          (await graceDraftRepository.load())?.id == record.id ||
          (await GraceConflictRecovery.archives()).any(
            (e) =>
                (e['saved'] as Map)['id'] == record.id ||
                (e['draft'] as Map)['id'] == record.id,
          );
      if (!mounted) return;
      final approved = await confirm(
        '문답 기록을 삭제할까요?',
        '삭제하면 이 완료 기록과 은혜 기록이 사라지고 시즌 진행도에도 반영됩니다. 이 작업은 되돌릴 수 없습니다.${related ? ' 이 기록에 연결된 저장 대기 내용과 이전 복구 원본도 함께 삭제합니다. 다른 기록은 유지됩니다.' : ''}',
        '기록 삭제',
      );
      if (!mounted) return;
      if (!approved) {
        setState(() => busy = false);
        return;
      }
      final cleaned = await actions.delete(record.id);
      await widget.onChanged?.call();
      if (!cleaned && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '완료 기록은 삭제되었습니다. 연결된 이전 임시 데이터 정리는 다음 실행에서 다시 시도합니다.',
            ),
          ),
        );
      }
      if (!mounted) return;
      setState(() => busy = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '기록을 삭제하지 못했습니다. 기록을 유지했습니다. 다시 시도해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('문답 기록 상세'),
        automaticallyImplyLeading: !busy,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${record.courseNumber}장 · ${record.courseTitle}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('완료 날짜와 시간: ${formatSignedAt(record.completedAt)}'),
          Text(
            record.participationMode == ParticipationMode.solo
                ? '혼자 하기'
                : '함께 하기',
          ),
          Text(
            '참여자: ${record.myName}${record.participationMode == ParticipationMode.together ? ' · ${record.partnerName}' : ''}',
          ),
          Text('나의 완료 확인: ${formatSignedAt(record.mySignedAt)}'),
          if (record.partnerSignedAt != null)
            Text('상대방 완료 확인: ${formatSignedAt(record.partnerSignedAt!)}'),
          const SizedBox(height: 20),
          Text(
            '마무리 상태: ${record.graceReflectionPending
                ? '은혜 기록 대기'
                : record.graceReflection.trim().isEmpty
                ? '마음에 담고 마무리했습니다'
                : '은혜 기록 남김'}',
          ),
          const SizedBox(height: 12),
          if (!editing) ...[
            if (record.graceReflection.trim().isNotEmpty)
              SelectableText(record.graceReflection),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      editing = true;
                      keepInHeart = record.graceReflection.trim().isEmpty;
                      controller.text = record.graceReflection;
                      error = null;
                    }),
              child: const Text('수정'),
            ),
          ] else ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('은혜 기록 남기기')),
                ButtonSegment(value: true, label: Text('마음에 담고 마무리했습니다')),
              ],
              selected: {keepInHeart},
              onSelectionChanged: busy
                  ? null
                  : (v) => setState(() => keepInHeart = v.first),
            ),
            if (!keepInHeart)
              TextField(
                controller: controller,
                enabled: !busy,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(labelText: '은혜 내용'),
              ),
            FilledButton(
              onPressed: busy ? null : save,
              child: const Text('저장'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      editing = false;
                      error = null;
                    }),
              child: const Text('수정 취소'),
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: busy ? null : delete,
            child: const Text('기록 삭제'),
          ),
          if (busy) const Center(child: CircularProgressIndicator()),
          if (error != null) Text(error!, key: const ValueKey('history-error')),
        ],
      ),
    ),
  );
}
