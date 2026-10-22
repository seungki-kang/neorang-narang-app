part of '../main.dart';

/// Carries a fixed code only; never includes personal stored content.
class StorageReadException implements Exception {
  const StorageReadException();
  @override
  String toString() => 'storage_read_failed';
}

class StorageFailureView extends StatelessWidget {
  const StorageFailureView({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber, size: 48),
          const SizedBox(height: 16),
          const Text('저장된 기록을 읽지 못했습니다.', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            '기록을 초기화하거나 앱을 삭제하지 마세요.\n'
            '다시 시도해도 같다면 데이터 복구 확인이 필요합니다.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    ),
  );
}

class StorageStartupPage extends StatefulWidget {
  const StorageStartupPage({super.key});
  @override
  State<StorageStartupPage> createState() => _StorageStartupPageState();
}

class _StorageStartupPageState extends State<StorageStartupPage> {
  bool retrying = false;
  Future<void> retry() async {
    if (retrying) return;
    setState(() => retrying = true);
    try {
      await initializeStorage();
      if (mounted) runApp(const MyApp());
    } catch (_) {
      AppLogger.error(AppLogEvent.storageReadFailed);
      if (mounted) setState(() => retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('너랑나랑')),
    body: retrying
        ? const Center(child: CircularProgressIndicator())
        : StorageFailureView(onRetry: retry),
  );
}
