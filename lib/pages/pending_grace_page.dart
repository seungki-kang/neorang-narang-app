part of '../main.dart';

class PendingGracePage extends StatefulWidget {
  const PendingGracePage({super.key});

  @override
  State<PendingGracePage> createState() => _PendingGracePageState();
}

class _PendingGracePageState extends State<PendingGracePage> {
  List<CompletionRecord> records = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadRecords();
  }

  Future<void> loadRecords() async {
    final loaded = await completionRepository.pendingGraceRecords();
    if (!mounted) return;
    setState(() {
      records = loaded;
      isLoading = false;
    });
  }

  Future<void> writeGrace(CompletionRecord record) async {
    final controller = TextEditingController();
    final String? reflection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('하나님이 주신 은혜'),
        content: TextField(
          controller: controller,
          minLines: 4,
          maxLines: 7,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '은혜를 기록해 주세요.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reflection == null) return;
    await completionRepository.saveGraceReflection(record.id, reflection);
    await loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('다음에 기록할 은혜'),
        backgroundColor: Colors.deepPurple.shade200,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? const Center(child: Text('미뤄 둔 은혜 기록이 없습니다.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.auto_awesome,
                          color: Colors.deepPurple,
                        ),
                        title: Text(
                          '${record.courseNumber}장 「${record.courseTitle}」',
                        ),
                        subtitle: Text(formatSignedAt(record.completedAt)),
                        trailing: FilledButton.tonal(
                          onPressed: () => writeGrace(record),
                          child: const Text('기록하기'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

