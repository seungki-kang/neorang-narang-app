part of '../main.dart';

class CompletionHistoryPage extends StatefulWidget {
  const CompletionHistoryPage({super.key});

  @override
  State<CompletionHistoryPage> createState() =>
      _CompletionHistoryPageState();
}

class _CompletionHistoryPageState extends State<CompletionHistoryPage> {
  List<CompletionRecord> records = [];
  int selectedCourse = 0;
  bool isLoading = true;

  List<CompletionRecord> get filteredRecords {
    if (selectedCourse == 0) return records;
    return records
        .where((record) => record.courseNumber == selectedCourse)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    loadRecords();
  }

  Future<void> loadRecords() async {
    final loaded = await completionRepository.loadAll();
    loaded.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    if (!mounted) return;
    setState(() {
      records = loaded;
      isLoading = false;
    });
  }

  String participantText(CompletionRecord record) {
    if (record.participationMode == ParticipationMode.solo) {
      return '${record.myName} · 혼자 하기';
    }
    return '${record.myName} · ${record.partnerName} · 함께 하기';
  }

  void showRecordDetail(CompletionRecord record) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            24 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${record.courseNumber}장 「${record.courseTitle}」',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                formatSignedAt(record.completedAt),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              _HistoryDetailRow(
                icon: Icons.people,
                title: '참여자',
                value: participantText(record),
              ),
              const SizedBox(height: 12),
              _HistoryDetailRow(
                icon: Icons.verified,
                title: '나의 완료 확인',
                value: formatSignedAt(record.mySignedAt),
              ),
              if (record.partnerSignedAt != null) ...[
                const SizedBox(height: 12),
                _HistoryDetailRow(
                  icon: Icons.verified_user,
                  title: '상대방 완료 확인',
                  value: formatSignedAt(record.partnerSignedAt!),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepPurple.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '하나님이 주신 은혜',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      record.graceReflection.trim().isEmpty
                          ? '마음에 담고 마무리했습니다.'
                          : record.graceReflection,
                      style: const TextStyle(fontSize: 16, height: 1.55),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('확인'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleRecords = filteredRecords;
    return Scaffold(
      appBar: AppBar(
        title: const Text('나의 문답 기록'),
        backgroundColor: Colors.deepPurple.shade200,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                children: [
                  Text(
                    '총 ${records.length}회의 문답을 마쳤습니다.',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('전체')),
                      ButtonSegment(value: 1, label: Text('1장')),
                      ButtonSegment(value: 2, label: Text('2장')),
                    ],
                    selected: {selectedCourse},
                    onSelectionChanged: (values) {
                      setState(() => selectedCourse = values.first);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : visibleRecords.isEmpty
                      ? const _EmptyHistoryView()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          itemCount: visibleRecords.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final record = visibleRecords[index];
                            final bool hasGrace =
                                record.graceReflection.trim().isNotEmpty;
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => showRecordDetail(record),
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.deepPurple.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '${record.courseNumber}장',
                                              style: const TextStyle(
                                                color: Colors.deepPurple,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              record.courseTitle,
                                              style: const TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            formatSignedAt(record.completedAt),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        participantText(record),
                                        style: const TextStyle(
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Icon(
                                            hasGrace
                                                ? Icons.auto_awesome
                                                : Icons.favorite_border,
                                            size: 18,
                                            color: Colors.deepPurple,
                                          ),
                                          const SizedBox(width: 7),
                                          Expanded(
                                            child: Text(
                                              hasGrace
                                                  ? record.graceReflection
                                                  : '마음에 담고 마무리했습니다.',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.black54,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: Colors.black38,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryDetailRow extends StatelessWidget {
  const _HistoryDetailRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.deepPurple),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyHistoryView extends StatelessWidget {
  const _EmptyHistoryView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 64,
              color: Colors.deepPurple.shade200,
            ),
            const SizedBox(height: 16),
            const Text(
              '아직 문답 기록이 없습니다.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '문답을 마치고 완료를 확인하면\n여기에 기록이 차곡차곡 쌓입니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

