part of '../main.dart';

class DeletedRecordsPage extends StatefulWidget {
  const DeletedRecordsPage({super.key, required this.store});
  final CompletionTrashStore store;
  @override
  State<DeletedRecordsPage> createState() => _DeletedRecordsPageState();
}

class _DeletedRecordsPageState extends State<DeletedRecordsPage> {
  List<CompletionRecovery> entries = [];
  bool loading = true;
  bool busy = false;
  bool loadFailed = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      loadFailed = false;
    });
    try {
      final result = await widget.store.listTrash();
      result.sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
      if (!mounted) return;
      setState(() {
        entries = result;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          loadFailed = true;
        });
      }
    }
  }

  Future<void> act(CompletionRecovery entry, {required bool permanent}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (permanent) {
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('이 기록을 영구 삭제할까요?'),
            content: const Text(
              '완료 기록과 은혜 기록, 연결된 저장 대기 원본이 영구 삭제됩니다. 이 작업은 되돌릴 수 없습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('영구 삭제 확인'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (confirmed != true) return;
        await widget.store.permanentlyDeleteTrash(entry.record.id);
        try {
          if (await widget.store.findById(entry.record.id) == null) {
            await CompletionActions(widget.store).cleanLegacy(entry.record.id);
          }
        } catch (_) {
          if (mounted) {
            setState(
              () => error =
                  '보관 기록은 영구 삭제되었습니다. 연결된 이전 임시 데이터 정리는 다음 조회에서 다시 시도합니다.',
            );
          }
        }
      } else {
        await widget.store.restoreTrash(entry.record.id);
      }
      await load();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError && e.message == 'restore_conflict'
              ? '동일한 ID의 완료 기록이 이미 있습니다. 기존 기록을 덮어쓰지 않았습니다.'
              : '처리하지 못했습니다. 목록을 다시 확인한 뒤 재시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('복구 보관함'),
        automaticallyImplyLeading: !busy,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : loadFailed
          ? StorageFailureView(onRetry: load)
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  '삭제한 완료 기록입니다. 보관 중에는 완료 횟수와 시즌에서 제외됩니다. 복원하면 원래 기록으로 돌아갑니다.',
                ),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('복원할 삭제 기록이 없습니다.'),
                  ),
                if (error != null)
                  Text(error!, key: const ValueKey('trash-error')),
                if (busy) const LinearProgressIndicator(),
                for (final entry in entries)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.record.courseNumber}장 · ${entry.record.courseTitle}',
                          ),
                          Text(
                            '완료: ${formatSignedAt(entry.record.completedAt)}',
                          ),
                          Text('삭제: ${formatSignedAt(entry.deletedAt!)}'),
                          Text(
                            entry.record.participationMode ==
                                    ParticipationMode.solo
                                ? '혼자 하기'
                                : '함께 하기',
                          ),
                          SelectableText(entry.record.graceReflection),
                          Wrap(
                            spacing: 12,
                            children: [
                              FilledButton(
                                onPressed: busy
                                    ? null
                                    : () => act(entry, permanent: false),
                                child: const Text('복원'),
                              ),
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => act(entry, permanent: true),
                                child: const Text('영구 삭제'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}
