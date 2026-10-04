import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

enum ParticipationMode { solo, together }

class QuestionDraft {
  const QuestionDraft({
    required this.courseNumber,
    required this.courseTitle,
    required this.participationMode,
    required this.myDisplayName,
    required this.partnerDisplayName,
    required this.firstAskerIsMe,
    required this.currentQuestionIndex,
    required this.savedAt,
  });

  final int courseNumber;
  final String courseTitle;
  final ParticipationMode participationMode;
  final String myDisplayName;
  final String partnerDisplayName;
  final bool firstAskerIsMe;
  final int currentQuestionIndex;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'courseNumber': courseNumber,
        'courseTitle': courseTitle,
        'participationMode': participationMode.name,
        'myDisplayName': myDisplayName,
        'partnerDisplayName': partnerDisplayName,
        'firstAskerIsMe': firstAskerIsMe,
        'currentQuestionIndex': currentQuestionIndex,
        'savedAt': savedAt.toIso8601String(),
      };

  factory QuestionDraft.fromJson(Map<String, dynamic> json) {
    return QuestionDraft(
      courseNumber: json['courseNumber'] as int,
      courseTitle: json['courseTitle'] as String,
      participationMode: json['participationMode'] == 'together'
          ? ParticipationMode.together
          : ParticipationMode.solo,
      myDisplayName: json['myDisplayName'] as String,
      partnerDisplayName: json['partnerDisplayName'] as String? ?? '',
      firstAskerIsMe: json['firstAskerIsMe'] as bool? ?? true,
      currentQuestionIndex: json['currentQuestionIndex'] as int? ?? 0,
      savedAt: DateTime.parse(json['savedAt'] as String),
    );
  }
}

class QuestionDraftRepository {
  static const String _storageKey = 'neorang_narang_question_draft_v1';

  Future<QuestionDraft?> load() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final String? stored = preferences.getString(_storageKey);
    if (stored == null || stored.isEmpty) return null;

    try {
      return QuestionDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(stored) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(QuestionDraft draft) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(draft.toJson()));
  }

  Future<void> clear() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }
}

class CompletionRecord {
  const CompletionRecord({
    required this.id,
    required this.courseNumber,
    required this.courseTitle,
    required this.participationMode,
    required this.myName,
    required this.partnerName,
    required this.completedAt,
    required this.mySignedAt,
    required this.partnerSignedAt,
    required this.graceReflection,
    required this.graceReflectionPending,
  });

  final String id;
  final int courseNumber;
  final String courseTitle;
  final ParticipationMode participationMode;
  final String myName;
  final String partnerName;
  final DateTime completedAt;
  final DateTime mySignedAt;
  final DateTime? partnerSignedAt;
  final String graceReflection;
  final bool graceReflectionPending;

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseNumber': courseNumber,
        'courseTitle': courseTitle,
        'participationMode': participationMode.name,
        'myName': myName,
        'partnerName': partnerName,
        'completedAt': completedAt.toIso8601String(),
        'mySignedAt': mySignedAt.toIso8601String(),
        'partnerSignedAt': partnerSignedAt?.toIso8601String(),
        'graceReflection': graceReflection,
        'graceReflectionPending': graceReflectionPending,
      };

  CompletionRecord withGraceReflection(String reflection) {
    return CompletionRecord(
      id: id,
      courseNumber: courseNumber,
      courseTitle: courseTitle,
      participationMode: participationMode,
      myName: myName,
      partnerName: partnerName,
      completedAt: completedAt,
      mySignedAt: mySignedAt,
      partnerSignedAt: partnerSignedAt,
      graceReflection: reflection,
      graceReflectionPending: false,
    );
  }

  factory CompletionRecord.fromJson(Map<String, dynamic> json) {
    return CompletionRecord(
      id: json['id'] as String,
      courseNumber: json['courseNumber'] as int,
      courseTitle: json['courseTitle'] as String,
      participationMode: json['participationMode'] == 'together'
          ? ParticipationMode.together
          : ParticipationMode.solo,
      myName: json['myName'] as String,
      partnerName: json['partnerName'] as String,
      completedAt: DateTime.parse(json['completedAt'] as String),
      mySignedAt: DateTime.parse(json['mySignedAt'] as String),
      partnerSignedAt: json['partnerSignedAt'] == null
          ? null
          : DateTime.parse(json['partnerSignedAt'] as String),
      graceReflection: json['graceReflection'] as String? ?? '',
      graceReflectionPending:
          json['graceReflectionPending'] as bool? ?? false,
    );
  }
}

class CompletionRepository {
  static const String _storageKey = 'neorang_narang_completion_records_v1';

  Future<List<CompletionRecord>> loadAll() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final String? stored = preferences.getString(_storageKey);
    if (stored == null || stored.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map(
            (item) => CompletionRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(CompletionRecord record) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final List<CompletionRecord> records = await loadAll();
    if (records.any((item) => item.id == record.id)) return;
    records.add(record);
    await preferences.setString(
      _storageKey,
      jsonEncode(records.map((item) => item.toJson()).toList()),
    );
  }

  Future<int> countForCourse(int courseNumber) async {
    final List<CompletionRecord> records = await loadAll();
    return records
        .where((record) => record.courseNumber == courseNumber)
        .length;
  }

  Future<List<CompletionRecord>> pendingGraceRecords() async {
    final List<CompletionRecord> records = await loadAll();
    return records
        .where((record) => record.graceReflectionPending)
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  }

  Future<void> saveGraceReflection(String recordId, String reflection) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final List<CompletionRecord> records = await loadAll();
    final List<CompletionRecord> updated = records
        .map(
          (record) => record.id == recordId
              ? record.withGraceReflection(reflection)
              : record,
        )
        .toList();
    await preferences.setString(
      _storageKey,
      jsonEncode(updated.map((item) => item.toJson()).toList()),
    );
  }
}

final CompletionRepository completionRepository = CompletionRepository();
final QuestionDraftRepository questionDraftRepository =
    QuestionDraftRepository();

class ChapterProgress {
  const ChapterProgress(this.completedCount);

  final int completedCount;
  int get stars => completedCount ~/ 50;
  int get season => stars + 1;
  int get countInSeason => completedCount % 50;
}

String makeAddress(String name, String honorific) {
  if (honorific.isEmpty) {
    return name;
  }
  return honorific == '이름+님' ? '$name님' : honorific;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '너랑나랑',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ChapterProgress chapter1Progress = const ChapterProgress(0);
  ChapterProgress chapter2Progress = const ChapterProgress(0);
  QuestionDraft? questionDraft;
  bool isLoadingProgress = true;

  @override
  void initState() {
    super.initState();
    loadProgress();
  }

  Future<void> loadProgress() async {
    final List<int> counts = await Future.wait<int>([
      completionRepository.countForCourse(1),
      completionRepository.countForCourse(2),
    ]);
    final QuestionDraft? savedDraft = await questionDraftRepository.load();
    if (!mounted) return;
    setState(() {
      chapter1Progress = ChapterProgress(counts[0]);
      chapter2Progress = ChapterProgress(counts[1]);
      questionDraft = savedDraft;
      isLoadingProgress = false;
    });
  }

  Future<void> openQuestions() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UsageGuidePage()),
    );
    await loadProgress();
  }

  Future<void> resumeQuestions() async {
    final QuestionDraft? draft = questionDraft;
    if (draft == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuestionPage(
          courseNumber: draft.courseNumber,
          courseTitle: draft.courseTitle,
          participationMode: draft.participationMode,
          myName: draft.myDisplayName,
          myHonorific: '',
          partnerName: draft.partnerDisplayName,
          partnerHonorific: '',
          firstAskerIsMe: draft.firstAskerIsMe,
          initialQuestionIndex: draft.currentQuestionIndex,
        ),
      ),
    );
    await loadProgress();
  }

  Future<void> discardDraft() async {
    final bool? shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('진행 중인 문답 삭제'),
        content: const Text(
          '저장된 진행 내용을 삭제하고 처음부터 시작하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제하고 새로 시작'),
          ),
        ],
      ),
    );

    if (shouldDiscard != true) return;
    await questionDraftRepository.clear();
    if (!mounted) return;
    setState(() => questionDraft = null);
    await openQuestions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('너랑나랑'),
        backgroundColor: Colors.deepPurple.shade200,
        actions: [
          IconButton(
            tooltip: '나의 문답 기록',
            icon: const Icon(Icons.history),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CompletionHistoryPage(),
                ),
              );
              await loadProgress();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Image.asset(
                  'assets/images/jesuslife_one_logo.jpg',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.auto_awesome,
                    size: 72,
                    color: Colors.deepPurple,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '너랑나랑',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '너랑나랑 문답을 시작해 보세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              if (isLoadingProgress)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                )
              else ...[
                ProgressCard(
                  chapter: '1장',
                  title: '다 끝났다',
                  progress: chapter1Progress,
                ),
                const SizedBox(height: 12),
                ProgressCard(
                  chapter: '2장',
                  title: '다 이루었다',
                  progress: chapter2Progress,
                ),
              ],
              if (questionDraft != null) ...[
                const SizedBox(height: 20),
                _ContinueQuestionCard(
                  draft: questionDraft!,
                  onContinue: resumeQuestions,
                  onRestart: discardDraft,
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                onPressed: openQuestions,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('문답 시작하기'),
              ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const CompletionHistoryPage(),
                      ),
                    );
                    await loadProgress();
                  },
                  icon: const Icon(Icons.menu_book),
                  label: const Text('나의 문답 기록'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueQuestionCard extends StatelessWidget {
  const _ContinueQuestionCard({
    required this.draft,
    required this.onContinue,
    required this.onRestart,
  });

  final QuestionDraft draft;
  final VoidCallback onContinue;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final String participantText =
        draft.participationMode == ParticipationMode.together
            ? '${draft.myDisplayName} · ${draft.partnerDisplayName}'
            : draft.myDisplayName;

    return Card(
      color: Colors.deepPurple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.bookmark, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text(
                  '진행 중인 문답',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${draft.courseNumber}장 ${draft.courseTitle}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(participantText),
            const SizedBox(height: 4),
            Text(
              '${draft.currentQuestionIndex + 1}/45 문항부터 이어서 진행합니다.',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.play_arrow),
              label: const Text('이어서 하기'),
            ),
            TextButton(
              onPressed: onRestart,
              child: const Text('진행 내용 삭제하고 처음부터 시작'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProgressCard extends StatelessWidget {
  const ProgressCard({
    super.key,
    required this.chapter,
    required this.title,
    required this.progress,
  });

  final String chapter;
  final String title;
  final ChapterProgress progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$chapter  $title',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  progress.stars == 0 ? '☆ 0' : '★ ${progress.stars}',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress.countInSeason / 50,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 8),
            Text(
              '시즌 ${progress.season}  |  ${progress.countInSeason}/50',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.deepPurple,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
                          separatorBuilder: (_, __) =>
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

class UsageGuidePage extends StatelessWidget {
  const UsageGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('사용설명서'),
        backgroundColor: Colors.deepPurple.shade200,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '너랑나랑 사용설명서',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  '《너랑나랑》은 혼자 또는 두 사람이 묻고 답하며 '
                  '십자가의 진리를 선포하고 선언하는 문답입니다.\n\n'
                  '두 사람이 함께할 때는 한 문항씩 번갈아 묻고 답합니다. '
                  '1번은 먼저 시작하는 사람이 묻고 상대방이 답하며, '
                  '2번은 상대방이 묻고 먼저 시작한 사람이 답합니다.\n\n'
                  '화면에 나타난 질문을 천천히 읽고 십자가의 능력을 경험하세요.\n\n'
                  '상대방의 답을 마음으로 함께 고백하면서 성령의 능력을 경험하세요.\n\n'
                  '혼자 할 때는 질문을 읽고 자신의 마음으로 답해 보세요. '
                  '가능하면 질문과 답을 소리 내어 말해 보세요.',
                  style: TextStyle(fontSize: 16, height: 1.55),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ParticipantSetupPage(),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward),
              label: const Text('문답 방법 선택하기'),
            ),
          ],
        ),
      ),
    );
  }
}

class ParticipantSetupPage extends StatefulWidget {
  const ParticipantSetupPage({super.key});

  @override
  State<ParticipantSetupPage> createState() =>
      _ParticipantSetupPageState();
}

class _ParticipantSetupPageState extends State<ParticipantSetupPage> {
  ParticipationMode selectedMode = ParticipationMode.solo;

  final TextEditingController myNameController = TextEditingController();
  final TextEditingController partnerNameController = TextEditingController();

  @override
  void dispose() {
    myNameController.dispose();
    partnerNameController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void continueToCourses() {
    final String myName = myNameController.text.trim();
    final String partnerName = partnerNameController.text.trim();

    if (myName.isEmpty) {
      showMessage('나의 이름을 입력해 주세요.');
      return;
    }

    if (selectedMode == ParticipationMode.together && partnerName.isEmpty) {
      showMessage('상대방 이름을 입력해 주세요.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CourseSelectionPage(
          participationMode: selectedMode,
          myName: myName,
          myHonorific: '',
          partnerName: partnerName,
          partnerHonorific: '',
        ),
      ),
    );
  }

  Widget buildNameField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: label == '나의 이름'
            ? '예: 강승기 또는 강승기 목사님'
            : '예: 김애숙 또는 김애숙 목사님',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.person),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTogether = selectedMode == ParticipationMode.together;

    return Scaffold(
      appBar: AppBar(
        title: const Text('참여자 설정'),
        backgroundColor: Colors.deepPurple.shade200,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              '어떻게 문답하시겠습니까?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            SegmentedButton<ParticipationMode>(
              segments: const [
                ButtonSegment(
                  value: ParticipationMode.solo,
                  icon: Icon(Icons.person),
                  label: Text('혼자 하기'),
                ),
                ButtonSegment(
                  value: ParticipationMode.together,
                  icon: Icon(Icons.people),
                  label: Text('함께 하기'),
                ),
              ],
              selected: {selectedMode},
              onSelectionChanged: (selectedValues) {
                setState(() {
                  selectedMode = selectedValues.first;
                });
              },
            ),
            const SizedBox(height: 30),
            buildNameField(
              controller: myNameController,
              label: '나의 이름',
            ),
            if (isTogether) ...[
              const SizedBox(height: 24),
              buildNameField(
                controller: partnerNameController,
                label: '상대방 이름',
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: continueToCourses,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('과정 선택으로'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CourseSelectionPage extends StatelessWidget {
  const CourseSelectionPage({
    super.key,
    required this.participationMode,
    required this.myName,
    required this.myHonorific,
    required this.partnerName,
    required this.partnerHonorific,
  });

  final ParticipationMode participationMode;
  final String myName;
  final String myHonorific;
  final String partnerName;
  final String partnerHonorific;

  void openPreparation(
    BuildContext context, {
    required int courseNumber,
    required String courseTitle,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreparationPage(
          courseNumber: courseNumber,
          courseTitle: courseTitle,
          participationMode: participationMode,
          myName: myName,
          myHonorific: myHonorific,
          partnerName: partnerName,
          partnerHonorific: partnerHonorific,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTogether = participationMode == ParticipationMode.together;
    final String participantText =
        isTogether ? '참여자: $myName · $partnerName' : '참여자: $myName';

    return Scaffold(
      appBar: AppBar(
        title: const Text('과정 선택'),
        backgroundColor: Colors.deepPurple.shade200,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              participantText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isTogether
                  ? '두 분이 함께 진행할 과정을 선택해 주세요.'
                  : '혼자 진행할 과정을 선택해 주세요.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            CourseCard(
              chapter: '1장',
              title: '다 끝났다',
              description: '십자가에서 나의 무엇이 다 끝났습니까?',
              onPressed: () => openPreparation(
                context,
                courseNumber: 1,
                courseTitle: '다 끝났다',
              ),
            ),
            const SizedBox(height: 20),
            CourseCard(
              chapter: '2장',
              title: '다 이루었다',
              description: '십자가에서 예수님이 이루신 것을 문답합니다.',
              onPressed: () => openPreparation(
                context,
                courseNumber: 2,
                courseTitle: '다 이루었다',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CourseCard extends StatelessWidget {
  const CourseCard({
    super.key,
    required this.chapter,
    required this.title,
    required this.description,
    required this.onPressed,
  });

  final String chapter;
  final String title;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(chapter, style: const TextStyle(color: Colors.deepPurple)),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.play_arrow),
                label: Text('$chapter 시작하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PreparationPage extends StatefulWidget {
  const PreparationPage({
    super.key,
    required this.courseNumber,
    required this.courseTitle,
    required this.participationMode,
    required this.myName,
    required this.myHonorific,
    required this.partnerName,
    required this.partnerHonorific,
  });

  final int courseNumber;
  final String courseTitle;
  final ParticipationMode participationMode;
  final String myName;
  final String myHonorific;
  final String partnerName;
  final String partnerHonorific;

  @override
  State<PreparationPage> createState() => _PreparationPageState();
}

class _PreparationPageState extends State<PreparationPage> {
  bool firstAskerIsMe = true;

  void startQuestions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuestionPage(
          courseNumber: widget.courseNumber,
          courseTitle: widget.courseTitle,
          participationMode: widget.participationMode,
          myName: widget.myName,
          myHonorific: widget.myHonorific,
          partnerName: widget.partnerName,
          partnerHonorific: widget.partnerHonorific,
          firstAskerIsMe: firstAskerIsMe,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTogether =
        widget.participationMode == ParticipationMode.together;
    final String myAddress =
        makeAddress(widget.myName, widget.myHonorific);
    final String partnerAddress =
        makeAddress(widget.partnerName, widget.partnerHonorific);

    return Scaffold(
      appBar: AppBar(
        title: const Text('시작 기도'),
        backgroundColor: Colors.deepPurple.shade200,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.courseNumber}장 ${widget.courseTitle}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            if (isTogether) ...[
              const SizedBox(height: 24),
              const Text(
                '누가 먼저 물어보시겠습니까?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(myAddress)),
                  ButtonSegment(value: false, label: Text(partnerAddress)),
                ],
                selected: {firstAskerIsMe},
                onSelectionChanged: (values) {
                  setState(() => firstAskerIsMe = values.first);
                },
              ),
            ],
            const SizedBox(height: 28),
            const Text(
              '시작 기도',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  '하나님 아버지!\n'
                  '이 시간 성령께서 함께하시어\n'
                  '십자가에서 다 끝난 비밀을 깨닫게 해주시고\n'
                  '나 자신이 십자가에서 다 끝난 인생을\n'
                  '살게 해주세요.\n\n'
                  '부활의 은혜를 깨달아 예수생명으로 살고,\n'
                  '하나님 나라를 누리는 삶을 살도록\n'
                  '간절히 간구합니다.\n\n'
                  '성령님께서 이 시간 저희 나눔 속에 함께하시고\n'
                  '온전한 하나님 나라를 경험하게 도와주세요.\n'
                  '예수님 이름으로 기도합니다.\n'
                  '아멘.',
                  style: TextStyle(fontSize: 16, height: 1.55),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: startQuestions,
              icon: const Icon(Icons.favorite),
              label: const Text('아멘 · 문답 시작'),
            ),
          ],
        ),
      ),
    );
  }
}

class QuestionItem {
  const QuestionItem({
    required this.id,
    required this.questionTemplate,
    required this.answerLines,
  });

  final String id;
  final String questionTemplate;
  final List<String> answerLines;
}

QuestionItem _finishedQuestion(
  String id,
  String subject,
  String topicSubject,
) {
  final String innerTopic = topicSubject.startsWith('이 ')
      ? '내 안에 있는 ${topicSubject.substring(2)}'
      : '내 안에 있는 $topicSubject';
  return QuestionItem(
    id: 'nno.finished.$id',
    questionTemplate: '{answerer}의 무엇이 십자가에서 다 끝났습니까?',
    answerLines: [
      '내 안에 있는 $subject입니다.',
      '$topicSubject 100% 내 안에 있습니다.',
      '$innerTopic 십자가에서 다 끝났습니다.',
    ],
  );
}

final List<QuestionItem> chapter1Questions = [
  _finishedQuestion('shame', '수치심', '이 수치심은'),
  _finishedQuestion('fear', '두려움', '이 두려움은'),
  _finishedQuestion('guilt', '죄책감', '이 죄책감은'),
  _finishedQuestion('self_righteousness', '나의 의', '나의 의는'),
  _finishedQuestion('approval_desire', '인정받고 싶은 욕구', '인정받고 싶은 욕구는'),
  _finishedQuestion('past_wounds', '과거의 상처', '이 과거의 상처는'),
  _finishedQuestion('fear_of_death', '죽음의 공포', '이 죽음의 공포는'),
  _finishedQuestion('pride', '교만', '이 교만은'),
  _finishedQuestion('jealousy', '시기심', '이 시기심은'),
  _finishedQuestion('greed', '탐욕', '이 탐욕은'),
  _finishedQuestion('gluttony', '탐식', '이 탐식은'),
  _finishedQuestion('anger', '분노', '이 분노는'),
  _finishedQuestion('lust', '정욕', '이 정욕은'),
  _finishedQuestion('laziness', '나태함', '이 나태함은'),
  _finishedQuestion('falsehood', '거짓', '이 거짓은'),
  _finishedQuestion('evil_heart', '악한 마음', '이 악한 마음은'),
  _finishedQuestion('resentment', '억울함', '이 억울함은'),
  _finishedQuestion('stereotype', '고정관념', '이 고정관념은'),
  _finishedQuestion('comparison', '비교하는 마음', '이 비교하는 마음은'),
  _finishedQuestion('low_self_esteem', '낮은 자존감', '이 낮은 자존감은'),
  _finishedQuestion('inferiority', '열등감', '이 열등감은'),
  _finishedQuestion('depression', '우울함', '이 우울함은'),
  _finishedQuestion('stubbornness', '고집', '이 고집은'),
  _finishedQuestion('temper', '혈기', '이 혈기는'),
  _finishedQuestion('helplessness', '무기력함', '이 무기력함은'),
  _finishedQuestion('frustration', '좌절감', '이 좌절감은'),
  _finishedQuestion('despair', '절망', '이 절망은'),
  _finishedQuestion('pain', '아픔', '이 아픔은'),
  _finishedQuestion('hatred', '미움', '이 미움은'),
  _finishedQuestion('dissatisfaction', '불만', '이 불만은'),
  _finishedQuestion('oppression', '짓눌림', '이 짓눌림은'),
  _finishedQuestion('sorrow', '서러움', '이 서러움은'),
  _finishedQuestion('sadness', '슬픔', '이 슬픔은'),
  _finishedQuestion('obsession', '집착', '이 집착은'),
  _finishedQuestion('belief', '신념', '이 신념은'),
  _finishedQuestion('prejudice', '편견', '이 편견은'),
  _finishedQuestion('preconception', '선입견', '이 선입견은'),
  _finishedQuestion('idolatry', '우상숭배', '이 우상숭배는'),
  _finishedQuestion('physical_disease', '육체의 질병', '이 육체의 질병은'),
  _finishedQuestion('suffering', '고통', '이 고통은'),
  _finishedQuestion('death', '사망', '이 사망은'),
  _finishedQuestion('curse', '저주', '이 저주는'),
  _finishedQuestion('poverty', '가난', '이 가난은'),
  _finishedQuestion('old_self', '옛사람', '이 옛사람은'),
  const QuestionItem(
    id: 'nno.finished.everything',
    questionTemplate: '{answerer}의 무엇이 십자가에서 다 끝났습니까?',
    answerLines: ['나의 모든 것이 십자가에서 다 끝났습니다.'],
  ),
];

QuestionItem _accomplishedQuestion(
  String id,
  String followUp,
  String answer,
) {
  return QuestionItem(
    id: 'nno.accomplished.$id',
    questionTemplate:
        '십자가와 부활은 {answerer}의 모든 것을 다 이루었습니다.\n$followUp',
    answerLines: [answer],
  );
}

final List<QuestionItem> chapter2Questions = [
  _accomplishedQuestion('restored_relationship', '이제 {answerer_topic} 누구입니까?', '나는 하나님과의 관계가 완전하게 회복된 사람입니다.'),
  _accomplishedQuestion('freedom_in_truth', '이제 {answerer_topic} 어떤 상태입니까?', '나는 진리 안에서 자유합니다.'),
  _accomplishedQuestion('liberated', '이제 {answerer_topic} 누구입니까?', '나는 죄의 종, 마귀의 종으로부터 완전하게 해방된 사람입니다.'),
  _accomplishedQuestion('source_of_blessing', '이제 {answerer_topic} 누구입니까?', '나는 복의 근원입니다.'),
  _accomplishedQuestion('overflowing_cup', '이제 {answerer_topic} 어떤 상태입니까?', '나는 내 잔이 넘칩니다.'),
  _accomplishedQuestion('needs_supplied', '이제 {answerer_topic} 어떤 상태입니까?', '나의 모든 쓸 것을 주님께서 채우셨습니다.'),
  _accomplishedQuestion('spirit_intercedes', '{answerer_topic} 무엇을 깨달았습니까?', '성령께서 말할 수 없는 탄식으로 나를 위하여 친히 간구하십니다.'),
  _accomplishedQuestion('kingdom_within', '이제 {answerer_topic} 어떤 상태입니까?', '내 안에 하나님 나라가 다 이루어졌습니다.'),
  _accomplishedQuestion('new_life', '이제 {answerer_topic} 누구입니까?', '나는 부활과 연합된 완전한 새 생명입니다.'),
  _accomplishedQuestion('temple_of_spirit', '이제 {answerer_topic} 누구입니까?', '나는 성령의 전입니다.'),
  _accomplishedQuestion('body_of_christ', '이제 {answerer_topic} 누구입니까?', '나는 교회의 머리이신 예수 그리스도의 지체입니다.'),
  _accomplishedQuestion('glory_of_god', '이제 {answerer_topic} 누구입니까?', '나는 하나님의 영광입니다.'),
  _accomplishedQuestion('heir_of_life', '이제 {answerer_topic} 누구입니까?', '나는 생명의 상속자입니다.'),
  _accomplishedQuestion('kingdom_people', '이제 {answerer_topic} 누구입니까?', '나는 하나님 나라의 백성입니다.'),
  _accomplishedQuestion('child_of_god', '이제 {answerer_topic} 누구입니까?', '나는 하나님의 자녀입니다.'),
  _accomplishedQuestion('saved_person', '이제 {answerer_topic} 누구입니까?', '나는 구원받은 사람입니다.'),
  _accomplishedQuestion('born_again', '이제 {answerer_topic} 어떤 상태입니까?', '나는 물과 성령으로 거듭났습니다.'),
  _accomplishedQuestion('chosen_people', '이제 {answerer_topic} 누구입니까?', '나는 택함 받은 백성입니다.'),
  _accomplishedQuestion('royal_priest', '이제 {answerer_topic} 누구입니까?', '나는 왕 같은 제사장입니다.'),
  _accomplishedQuestion('fruit_of_spirit', '이제 {answerer_topic} 누구입니까?', '나는 성령의 9가지 열매가 다 맺힌 사람입니다.'),
  _accomplishedQuestion('love', '이제 {answerer_topic} 누구입니까?', '나는 하나님의 사랑입니다.'),
  _accomplishedQuestion('joy', '이제 {answerer_topic} 누구입니까?', '나는 기쁨(희락)입니다.'),
  _accomplishedQuestion('peace', '이제 {answerer_topic} 누구입니까?', '나는 화평입니다.'),
  _accomplishedQuestion('patience', '이제 {answerer_topic} 누구입니까?', '나는 인내입니다.'),
  _accomplishedQuestion('kindness', '이제 {answerer_topic} 누구입니까?', '나는 자비입니다.'),
  _accomplishedQuestion('goodness', '이제 {answerer_topic} 누구입니까?', '나는 양선입니다.'),
  _accomplishedQuestion('faithfulness', '이제 {answerer_topic} 누구입니까?', '나는 충성입니다.'),
  _accomplishedQuestion('gentleness', '이제 {answerer_topic} 누구입니까?', '나는 온유입니다.'),
  _accomplishedQuestion('self_control', '이제 {answerer_topic} 누구입니까?', '나는 절제입니다.'),
  _accomplishedQuestion('intimacy_with_spirit', '이제 {answerer_topic} 어떤 상태입니까?', '성령 하나님과 친밀합니다.'),
  _accomplishedQuestion('eternal_life', '이제 {answerer_topic} 누구입니까?', '나는 영생을 얻은 자입니다.'),
  _accomplishedQuestion('covenant_people', '이제 {answerer_topic} 누구입니까?', '나는 언약된 백성입니다.'),
  _accomplishedQuestion('thankful', '이제 {answerer_topic} 누구입니까?', '나는 범사에 감사하는 사람입니다.'),
  _accomplishedQuestion('gods_will', '이제 {answerer_topic} 누구입니까?', '나로 말미암아 하나님의 뜻이 이루어지는 사람입니다.'),
  _accomplishedQuestion('answered_prayer', '이제 {answerer_topic} 누구입니까?', '나는 기도하여 응답받는 사람입니다.'),
  _accomplishedQuestion('worshiper', '이제 {answerer_topic} 누구입니까?', '나는 예배자입니다.'),
  _accomplishedQuestion('reconciler', '이제 {answerer_topic} 누구입니까?', '나는 모든 것과 화해하는 화해자입니다.'),
  _accomplishedQuestion('forgiving', '이제 {answerer_topic} 어떤 상태입니까?', '나는 용서하는 사람입니다.'),
  _accomplishedQuestion('sees_old_self_with_love', '이제 {answerer_topic} 누구입니까?', '나는 다른 사람의 ‘옛사람’을 하나님의 사랑과 긍휼로 바라보는 사람입니다.'),
  _accomplishedQuestion('nonviolent', '이제 {answerer_topic} 누구입니까?', '나는 비폭력, 무저항하는 사람입니다.'),
  _accomplishedQuestion('jesus_life', '이제 {answerer_topic} 누구입니까?', '나는 예수생명입니다.'),
  _accomplishedQuestion('little_jesus', '이제 {answerer_topic} 누구입니까?', '나는 작은 예수입니다.'),
  _accomplishedQuestion('resurrection_witness', '이제 {answerer_topic} 누구입니까?', '나는 부활 증인입니다.'),
  _accomplishedQuestion('disciple', '이제 {answerer_topic} 누구입니까?', '나는 제자입니다.'),
  _accomplishedQuestion('confession', '이제 {answerer_topic} 무엇을 고백합니까?', '십자가와 부활은 나의 모든 것을 다 이루었습니다.'),
];

String withTopicParticle(String text) {
  if (text.isEmpty) return text;
  final int code = text.runes.last;
  final bool hasFinalConsonant =
      code >= 0xAC00 && code <= 0xD7A3 && (code - 0xAC00) % 28 != 0;
  return '$text${hasFinalConsonant ? '은' : '는'}';
}

String formatSignedAt(DateTime dateTime) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${dateTime.year}.${twoDigits(dateTime.month)}.${twoDigits(dateTime.day)} '
      '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
}

class GraceReflectionPage extends StatefulWidget {
  const GraceReflectionPage({
    super.key,
    required this.courseNumber,
    required this.courseTitle,
    required this.participationMode,
    required this.myName,
    required this.partnerName,
  });

  final int courseNumber;
  final String courseTitle;
  final ParticipationMode participationMode;
  final String myName;
  final String partnerName;

  @override
  State<GraceReflectionPage> createState() => _GraceReflectionPageState();
}

class _GraceReflectionPageState extends State<GraceReflectionPage> {
  final TextEditingController reflectionController = TextEditingController();

  @override
  void dispose() {
    reflectionController.dispose();
    super.dispose();
  }

  void continueToSignature({required bool skipReflection}) {
    final String reflection = reflectionController.text.trim();
    if (!skipReflection && reflection.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('하나님이 주신 은혜를 기록해 주세요.')),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CompletionSignaturePage(
          courseNumber: widget.courseNumber,
          courseTitle: widget.courseTitle,
          participationMode: widget.participationMode,
          myName: widget.myName,
          partnerName: widget.partnerName,
          graceReflection: reflection,
          graceReflectionPending: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('은혜 기록'),
        backgroundColor: Colors.deepPurple.shade200,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 48,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 16),
              const Text(
                '너랑나랑 하면서\n하나님이 주신 은혜가 무엇인가요?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.45,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '짧은 문장도 좋습니다. 지금 마음에 남은 은혜를 기록해 보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: reflectionController,
                minLines: 5,
                maxLines: 8,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '하나님이 주신 은혜를 기록해 주세요.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => continueToSignature(skipReflection: false),
                icon: const Icon(Icons.edit),
                label: const Text('은혜 기록하고 서명하기'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => continueToSignature(skipReflection: true),
                icon: const Icon(Icons.favorite_border),
                label: const Text('마음에 담고 마무리하기'),
              ),
              const SizedBox(height: 10),
              const Text(
                '기록하지 않아도 괜찮습니다. 받은 은혜를 마음에 담고 '
                '편안하게 마무리할 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
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

class CompletionSignaturePage extends StatefulWidget {
  const CompletionSignaturePage({
    super.key,
    required this.courseNumber,
    required this.courseTitle,
    required this.participationMode,
    required this.myName,
    required this.partnerName,
    required this.graceReflection,
    required this.graceReflectionPending,
  });

  final int courseNumber;
  final String courseTitle;
  final ParticipationMode participationMode;
  final String myName;
  final String partnerName;
  final String graceReflection;
  final bool graceReflectionPending;

  @override
  State<CompletionSignaturePage> createState() =>
      _CompletionSignaturePageState();
}

class _CompletionSignaturePageState extends State<CompletionSignaturePage> {
  DateTime? mySignedAt;
  DateTime? partnerSignedAt;
  bool isSaving = false;

  bool get isTogether =>
      widget.participationMode == ParticipationMode.together;

  bool get allSigned =>
      mySignedAt != null && (!isTogether || partnerSignedAt != null);

  Future<void> saveAndFinish() async {
    if (!allSigned || isSaving) return;
    setState(() => isSaving = true);

    final DateTime completedAt = DateTime.now();
    final CompletionRecord record = CompletionRecord(
      id: '${widget.courseNumber}-${completedAt.microsecondsSinceEpoch}',
      courseNumber: widget.courseNumber,
      courseTitle: widget.courseTitle,
      participationMode: widget.participationMode,
      myName: widget.myName,
      partnerName: widget.partnerName,
      completedAt: completedAt,
      mySignedAt: mySignedAt!,
      partnerSignedAt: partnerSignedAt,
      graceReflection: widget.graceReflection,
      graceReflectionPending: widget.graceReflectionPending,
    );

    await completionRepository.add(record);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget buildSignatureCard({
    required String name,
    required DateTime? signedAt,
    required VoidCallback onPressed,
  }) {
    final bool signed = signedAt != null;
    return Card(
      color: signed ? Colors.deepPurple.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              signed ? Icons.verified : Icons.draw_outlined,
              color: signed ? Colors.deepPurple : Colors.grey,
              size: 32,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    signed
                        ? '완료 확인 · ${formatSignedAt(signedAt)}'
                        : '본인이 직접 눌러 완료를 확인해 주세요.',
                    style: TextStyle(
                      color: signed ? Colors.deepPurple : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: onPressed,
              child: Text(signed ? '서명됨' : '서명하기'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('마무리 서명'),
        backgroundColor: Colors.deepPurple.shade200,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: SizedBox(
                  width: 90,
                  height: 90,
                  child: Image.asset(
                    'assets/images/jesuslife_one_logo.jpg',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.courseNumber}장 「${widget.courseTitle}」',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '문답을 마쳤습니다.\n각 참여자가 자신의 이름을 직접 눌러 확인해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 26),
              buildSignatureCard(
                name: widget.myName,
                signedAt: mySignedAt,
                onPressed: () => setState(() => mySignedAt = DateTime.now()),
              ),
              if (isTogether) ...[
                const SizedBox(height: 12),
                buildSignatureCard(
                  name: widget.partnerName,
                  signedAt: partnerSignedAt,
                  onPressed: () =>
                      setState(() => partnerSignedAt = DateTime.now()),
                ),
              ],
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: allSigned && !isSaving ? saveAndFinish : null,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(isSaving ? '기록 저장 중...' : '서명 완료하고 마무리'),
              ),
              const SizedBox(height: 10),
              const Text(
                '서명을 완료하면 장·회차·참여자·서명 시각이 이 기기에 저장되고 '
                '첫 화면의 시즌과 별 기록에 반영됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuestionPage extends StatefulWidget {
  const QuestionPage({
    super.key,
    required this.courseNumber,
    required this.courseTitle,
    required this.participationMode,
    required this.myName,
    required this.myHonorific,
    required this.partnerName,
    required this.partnerHonorific,
    required this.firstAskerIsMe,
    this.initialQuestionIndex = 0,
  });

  final int courseNumber;
  final String courseTitle;
  final ParticipationMode participationMode;
  final String myName;
  final String myHonorific;
  final String partnerName;
  final String partnerHonorific;
  final bool firstAskerIsMe;
  final int initialQuestionIndex;

  @override
  State<QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  int currentQuestionIndex = 0;
  bool movingForward = true;
  bool allowExit = false;
  late final List<QuestionItem> questions;
  late String myDisplayName;
  late String partnerDisplayName;

  @override
  void initState() {
    super.initState();
    currentQuestionIndex = widget.initialQuestionIndex;
    myDisplayName = makeAddress(widget.myName, widget.myHonorific);
    partnerDisplayName =
        makeAddress(widget.partnerName, widget.partnerHonorific);
    questions = widget.courseNumber == 1
        ? List<QuestionItem>.of(chapter1Questions)
        : List<QuestionItem>.of(chapter2Questions);
    if (currentQuestionIndex < 0 || currentQuestionIndex >= questions.length) {
      currentQuestionIndex = 0;
    }
    saveDraft();
  }

  Future<void> saveDraft() async {
    await questionDraftRepository.save(
      QuestionDraft(
        courseNumber: widget.courseNumber,
        courseTitle: widget.courseTitle,
        participationMode: widget.participationMode,
        myDisplayName: myDisplayName,
        partnerDisplayName: partnerDisplayName,
        firstAskerIsMe: widget.firstAskerIsMe,
        currentQuestionIndex: currentQuestionIndex,
        savedAt: DateTime.now(),
      ),
    );
  }

  Future<void> saveAndExit() async {
    await saveDraft();
    if (!mounted) return;
    setState(() => allowExit = true);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> askBeforeExit() async {
    final bool? shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('문답을 저장하고 나갈까요?'),
        content: Text(
          '현재 ${currentQuestionIndex + 1}/${questions.length} 문항이 저장됩니다.\n'
          '첫 화면에서 이어서 할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('계속 문답하기'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.save),
            label: const Text('저장하고 나가기'),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      await saveAndExit();
    }
  }

  Future<void> editDisplayNames() async {
    final myController = TextEditingController(text: myDisplayName);
    final partnerController = TextEditingController(text: partnerDisplayName);
    final bool isTogether =
        widget.participationMode == ParticipationMode.together;

    final Map<String, String>? result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('이름과 호칭 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: myController,
              decoration: const InputDecoration(
                labelText: '나의 이름',
                hintText: '예: 강승기 또는 강승기 목사님',
                border: OutlineInputBorder(),
              ),
            ),
            if (isTogether) ...[
              const SizedBox(height: 16),
              TextField(
                controller: partnerController,
                decoration: const InputDecoration(
                  labelText: '상대방 이름',
                  hintText: '예: 김애숙 또는 김애숙 목사님',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final String newMyName = myController.text.trim();
              final String newPartnerName = partnerController.text.trim();

              if (newMyName.isEmpty || (isTogether && newPartnerName.isEmpty)) {
                return;
              }

              Navigator.pop(dialogContext, {
                'myName': newMyName,
                'partnerName': newPartnerName,
              });
            },
            child: const Text('수정 적용'),
          ),
        ],
      ),
    );

    myController.dispose();
    partnerController.dispose();

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      myDisplayName = result['myName']!;
      if (isTogether) {
        partnerDisplayName = result['partnerName']!;
      }
    });
    await saveDraft();
  }

  Future<void> goPrevious() async {
    if (currentQuestionIndex > 0) {
      setState(() {
        movingForward = false;
        currentQuestionIndex--;
      });
      await saveDraft();
    }
  }

  Future<void> goNext() async {
    if (currentQuestionIndex < questions.length - 1) {
      setState(() {
        movingForward = true;
        currentQuestionIndex++;
      });
      await saveDraft();
    } else {
      showCompletionDialog();
    }
  }

  void openConsecutiveCourse({
    required int courseNumber,
    required bool switchFirstAsker,
  }) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => QuestionPage(
          courseNumber: courseNumber,
          courseTitle: courseNumber == 1 ? '다 끝났다' : '다 이루었다',
          participationMode: widget.participationMode,
          myName: myDisplayName,
          myHonorific: '',
          partnerName: partnerDisplayName,
          partnerHonorific: '',
          firstAskerIsMe: switchFirstAsker
              ? !widget.firstAskerIsMe
              : widget.firstAskerIsMe,
        ),
      ),
    );
  }

  Future<void> showCompletionDialog() async {
    final bool isTogether =
        widget.participationMode == ParticipationMode.together;

    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text('${widget.courseTitle} 문답 완료'),
          content: Text(
            widget.courseNumber == 1
                ? '1장 45개 문답을 모두 진행했습니다.\n다음 진행을 선택해 주세요.'
                : '2장 45개 문답을 모두 진행했습니다.\n다음 진행을 선택해 주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                questionDraftRepository.clear();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GraceReflectionPage(
                      courseNumber: widget.courseNumber,
                      courseTitle: widget.courseTitle,
                      participationMode: widget.participationMode,
                      myName: myDisplayName,
                      partnerName: partnerDisplayName,
                    ),
                  ),
                );
              },
              child: const Text('마무리'),
            ),
            if (isTogether)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  openConsecutiveCourse(
                    courseNumber: widget.courseNumber == 1 ? 1 : 2,
                    switchFirstAsker: true,
                  );
                },
                child: Text(
                  widget.courseNumber == 1 ? '1장 교대로' : '2장 교대로',
                ),
              ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                openConsecutiveCourse(
                  courseNumber: widget.courseNumber == 1 ? 2 : 1,
                  switchFirstAsker: widget.courseNumber == 2 && isTogether,
                );
              },
              child: Text(
                widget.courseNumber == 1
                    ? '2장 진행'
                    : isTogether
                        ? '1장부터 교대로'
                        : '1장 진행',
              ),
            ),
          ],
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTogether =
        widget.participationMode == ParticipationMode.together;
    final int questionNumber = currentQuestionIndex + 1;
    final bool isOddQuestion = questionNumber.isOdd;
    final bool myTurnToAsk = widget.firstAskerIsMe
        ? isOddQuestion
        : !isOddQuestion;

    final String myAddress = myDisplayName;
    final String partnerAddress = partnerDisplayName;
    final String asker = myTurnToAsk ? myAddress : partnerAddress;
    final String answerer = myTurnToAsk ? partnerAddress : myAddress;

    final QuestionItem currentQuestion = questions[currentQuestionIndex];
    String question = currentQuestion.questionTemplate;
    question = question.replaceAll(
      '{answerer}',
      isTogether ? answerer : '나',
    );
    question = question.replaceAll(
      '{answerer_topic}',
      withTopicParticle(isTogether ? answerer : '나'),
    );

    final bool isFirst = currentQuestionIndex == 0;
    final bool isLast = currentQuestionIndex == questions.length - 1;

    return PopScope(
      canPop: allowExit,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await askBeforeExit();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('${widget.courseNumber}장 ${widget.courseTitle}'),
        backgroundColor: Colors.deepPurple.shade200,
        actions: [
          IconButton(
            onPressed: askBeforeExit,
            tooltip: '저장하고 나가기',
            icon: const Icon(Icons.save_outlined),
          ),
          IconButton(
            onPressed: editDisplayNames,
            tooltip: '이름과 호칭 수정',
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: questionNumber / questions.length,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 10),
              Text(
                '$questionNumber / ${questions.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                isTogether
                    ? '묻는 사람: $asker'
                    : '질문을 천천히 읽으면서 선포해 보세요',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    reverseDuration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final Animation<Offset> slide = Tween<Offset>(
                        begin: Offset(movingForward ? 0.10 : -0.10, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: slide,
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      key: ValueKey(currentQuestion.id),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              question,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          isTogether
                              ? '답하는 사람: $answerer\n소리 내어 선포해 보세요'
                              : '소리 내어 선포해 보세요',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            height: 1.5,
                            color: Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 24,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.deepPurple.shade200,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.deepPurple.withValues(alpha: 0.10),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.record_voice_over,
                                color: Colors.deepPurple,
                                size: 30,
                              ),
                              const SizedBox(height: 14),
                              for (int index = 0;
                                  index < currentQuestion.answerLines.length;
                                  index++) ...[
                                Text(
                                  currentQuestion.answerLines[index],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    height: 1.6,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                if (index <
                                    currentQuestion.answerLines.length - 1)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Divider(
                                      height: 1,
                                      color: Colors.deepPurple.shade100,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isFirst ? null : goPrevious,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('이전'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: goNext,
                      icon: Icon(isLast ? Icons.check : Icons.arrow_forward),
                      label: Text(isLast ? '선포 완료 · 과정 마침' : '선포 완료 · 다음'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
