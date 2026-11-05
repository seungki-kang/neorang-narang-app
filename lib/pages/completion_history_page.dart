part of '../main.dart';

class CompletionHistoryPage extends StatefulWidget {
  const CompletionHistoryPage({super.key, this.completionStore});
  final CompletionStore? completionStore;

  @override
  State<CompletionHistoryPage> createState() => _CompletionHistoryPageState();
}

class _CompletionHistoryPageState extends State<CompletionHistoryPage> {
  List<CompletionRecord> records = [];
  int selectedCourse = 0;
  final searchController = TextEditingController();
  String searchQuery = '';

  String normalizeSearch(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[-/]'), '.');
  bool isLoading = true;
  bool hasStorageError = false;
  int pendingCount = 0;

  List<CompletionRecord> get filteredRecords {
    final terms = normalizeSearch(searchQuery.trim())
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    return records.where((record) {
      if (selectedCourse != 0 && record.courseNumber != selectedCourse) {
        return false;
      }
      final searchable = normalizeSearch([
        record.myName,
        record.partnerName,
        record.courseTitle,
        record.graceReflection,
        formatSignedAt(record.completedAt),
      ].join(' '));
      return terms.every(searchable.contains);
    }).toList();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    loadRecords();
  }

  Future<void> loadRecords() async {
    setState(() {
      isLoading = true;
      hasStorageError = false;
    });
    try {
      final store = widget.completionStore ?? completionRepository;
      final loaded = await store.loadAll();
      final pending = store is CompletionEditingStore
          ? await CompletionActions(store).pending()
          : <PendingCompletion>[];
      loaded.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      if (!mounted) return;
      setState(() {
        records = loaded;
        pendingCount = pending.length;
        isLoading = false;
      });
    } catch (_) {
      AppLogger.error(AppLogEvent.storageReadFailed);
      if (!mounted) return;
      setState(() {
        isLoading = false;
        hasStorageError = true;
      });
    }
  }

  String participantText(CompletionRecord record) {
    if (record.participationMode == ParticipationMode.solo) {
      return '${record.myName} · 혼자 하기';
    }
    return '${record.myName} · ${record.partnerName} · 함께 하기';
  }

  Future<void> showRecordDetail(CompletionRecord record) async {
    final store = widget.completionStore ?? completionRepository;
    if (store is! CompletionEditingStore) return;
    await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => CompletionDetailPage(
          record: record,
          store: store,
          onChanged: loadRecords,
        ),
      ),
    );
    if (mounted) await loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    if (hasStorageError) {
      return Scaffold(
        appBar: AppBar(title: const Text('나의 문답 기록')),
        body: StorageFailureView(onRetry: loadRecords),
      );
    }
    final visibleRecords = filteredRecords;
    return Scaffold(
      appBar: AppBar(
        title: const Text('나의 문답 기록'),
        actions: [
          if ((widget.completionStore ?? completionRepository)
              is CompletionTrashStore)
            IconButton(
              tooltip: '복구 보관함',
              icon: const Icon(Icons.restore_from_trash_outlined),
              onPressed: isLoading
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => DeletedRecordsPage(
                            store:
                                (widget.completionStore ?? completionRepository)
                                    as CompletionTrashStore,
                          ),
                        ),
                      );
                      if (mounted) await loadRecords();
                    },
            ),
          if (!isLoading && !hasStorageError && pendingCount > 0)
            IconButton(
              tooltip: '저장되지 않은 기록 $pendingCount개',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () async {
                final store = widget.completionStore ?? completionRepository;
                if (store is! CompletionEditingStore) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => UnsavedRecordsPage(store: store),
                  ),
                );
                if (mounted) await loadRecords();
              },
            ),
        ],
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
                  TextField(
                    key: const ValueKey('history-search'),
                    controller: searchController,
                    onChanged: (value) => setState(() => searchQuery = value),
                    decoration: InputDecoration(
                      labelText: '기록 검색',
                      hintText: '이름 · 은혜 내용 · 날짜(2026.11.05)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '검색어 지우기',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                setState(() => searchQuery = '');
                              },
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                  if (!isLoading)
                    Text('현재 조건에 맞는 기록 ${visibleRecords.length}개'),
                ],
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : visibleRecords.isEmpty
                  ? records.isEmpty
                        ? const _EmptyHistoryView()
                        : const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                '조건에 맞는 기록이 없습니다.\n검색어나 장 선택을 변경해 주세요.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: visibleRecords.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final record = visibleRecords[index];
                        final bool hasGrace = record.graceReflection
                            .trim()
                            .isNotEmpty;
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => showRecordDetail(record),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
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
