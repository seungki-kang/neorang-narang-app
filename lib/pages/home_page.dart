part of '../main.dart';

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

