part of '../main.dart';

class UnsavedRecordsPage extends StatefulWidget {
  const UnsavedRecordsPage({super.key, this.store});
  final CompletionEditingStore? store;
  @override
  State<UnsavedRecordsPage> createState() => _UnsavedRecordsPageState();
}

class _UnsavedRecordsPageState extends State<UnsavedRecordsPage> {
  CompletionEditingStore get store =>
      widget.store ?? completionRepository as CompletionEditingStore;
  CompletionActions get actions => CompletionActions(store);
  List<PendingCompletion> entries = [];
  Map<String, CompletionRecord?> saved = {};
  bool loading = true;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final list = await actions.pending();
      final records = <String, CompletionRecord?>{};
      for (final entry in list) {
        records[entry.recordId] = await store.findById(entry.recordId);
      }
      if (mounted) {
        setState(() {
          entries = list;
          saved = records;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '저장 대기 기록을 읽지 못했습니다. 원본은 유지됩니다. 다시 시도해 주세요.';
        });
      }
    }
  }

  Future<bool> confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
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
  Future<void> run(PendingCompletion entry, bool discard) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (discard) {
        if (!await confirm(
          '저장 대기 내용을 삭제할까요?',
          '아직 저장되지 않은 임시 내용만 삭제됩니다. 이미 정상 저장된 완료 기록은 삭제되지 않습니다.',
          '임시 기록 삭제',
        )) {
          return;
        }
        await actions.discard(entry);
      } else {
        final grace = entry.grace;
        if (grace != null && grace.pendingRecord == null) {
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => grace.awaitingSignature
                  ? CompletionSignaturePage(
                      courseNumber: grace.courseNumber,
                      courseTitle: grace.courseTitle,
                      participationMode: grace.participationMode,
                      myName: grace.myName,
                      partnerName: grace.partnerName,
                      graceReflection: grace.reflection,
                      graceReflectionPending: false,
                      graceDraft: grace,
                    )
                  : GraceReflectionPage(
                      courseNumber: grace.courseNumber,
                      courseTitle: grace.courseTitle,
                      participationMode: grace.participationMode,
                      myName: grace.myName,
                      partnerName: grace.partnerName,
                      initialDraft: grace,
                    ),
            ),
          );
        } else {
          final current = saved[entry.recordId];
          if (current != null &&
              current.graceReflection != entry.reflection &&
              !await confirm(
                '저장 대기 내용을 반영할까요?',
                '기존 완료 내용을 저장 대기 내용으로 변경합니다. 완료 날짜와 횟수는 유지됩니다.',
                '다시 저장',
              )) {
            return;
          }
          await actions.retry(entry);
        }
      }
      await load();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              '저장을 완료하지 못했습니다. 저장 대기 내용은 유지됩니다. 기존 기록이 변경되었거나 삭제되었는지 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> inspect(PendingCompletion entry) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('내용 확인'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.isEdit || saved[entry.recordId] != null
                    ? '기존 기록 수정'
                    : '신규 완료 기록 저장',
              ),
              const SizedBox(height: 12),
              const Text('기존 은혜 기록'),
              SelectableText(
                saved[entry.recordId]?.graceReflection ?? '정상 저장된 완료 기록이 없습니다.',
              ),
              const SizedBox(height: 16),
              const Text('저장 대기 중인 내용'),
              SelectableText(
                entry.reflection.isEmpty ? '마음에 담고 마무리했습니다' : entry.reflection,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('저장되지 않은 기록'),
        automaticallyImplyLeading: !busy,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text('저장을 완료하지 못한 기록입니다. 내용을 확인하고 다시 저장할 수 있습니다.'),
                if (entries.isEmpty && error == null)
                  const Text('저장되지 않은 기록이 없습니다.'),
                for (final entry in entries)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${entry.courseNumber}장 · ${entry.title}'),
                          Text(
                            entry.isEdit || saved[entry.recordId] != null
                                ? '수정 저장 대기'
                                : '저장 대기',
                          ),
                          Text(
                            '마지막 저장 시도: ${entry.attemptedAt == null ? '이전 기록에 시각 정보가 없습니다.' : formatSignedAt(entry.attemptedAt!)}',
                          ),
                          const SizedBox(height: 12),
                          const Text('기존 은혜 기록'),
                          SelectableText(
                            saved[entry.recordId] == null
                                ? '정상 저장된 완료 기록이 없습니다.'
                                : saved[entry.recordId]!.graceReflection.isEmpty
                                ? '마음에 담고 마무리했습니다'
                                : saved[entry.recordId]!.graceReflection,
                          ),
                          const SizedBox(height: 12),
                          const Text('저장 대기 중인 내용'),
                          SelectableText(
                            entry.reflection.isEmpty
                                ? '마음에 담고 마무리했습니다'
                                : entry.reflection,
                          ),
                          TextButton(
                            onPressed: busy ? null : () => inspect(entry),
                            child: const Text('내용 확인'),
                          ),
                          FilledButton(
                            onPressed: busy ? null : () => run(entry, false),
                            child: const Text('다시 저장'),
                          ),
                          OutlinedButton(
                            onPressed: busy ? null : () => run(entry, true),
                            child: const Text('임시 기록 삭제'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (busy) const Center(child: CircularProgressIndicator()),
                if (error != null) ...[
                  Text(error!),
                  TextButton(
                    onPressed: busy ? null : load,
                    child: const Text('다시 시도'),
                  ),
                ],
              ],
            ),
    ),
  );
}

/// Kept for source compatibility. Routes use UnsavedRecordsPage directly.
class GraceRecoveryArchivePage extends UnsavedRecordsPage {
  const GraceRecoveryArchivePage({super.key, super.store});
}
