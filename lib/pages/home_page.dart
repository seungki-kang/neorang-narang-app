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
  GraceDraft? graceDraft;
  CompletionRecord? conflictingCompletion;
  bool isLoadingProgress = true;
  bool hasStorageError = false;
  int loadGeneration = 0;
  int recoveryCount = 0;
  final participantPreferences = ParticipantPreferencesRepository();
  ParticipantPreferences quickParticipants = const ParticipantPreferences();
  bool participantsLoading = true;
  bool participantsFailed = false;
  bool quickStarting = false;

  @override
  void initState() {
    super.initState();
    loadProgress();
    loadParticipants();
  }

  Future<void> loadParticipants() async {
    if (!mounted) {
      return;
    }
    setState(() {
      participantsLoading = true;
      participantsFailed = false;
    });
    try {
      final value = await participantPreferences.load();
      if (!mounted) {
        return;
      }
      setState(() {
        quickParticipants = value;
        participantsLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        participantsLoading = false;
        participantsFailed = true;
        quickParticipants = const ParticipantPreferences();
      });
    }
  }

  Future<void> quickStart({required bool together}) async {
    if (quickStarting || participantsLoading || participantsFailed ||
        isLoadingProgress || hasStorageError || questionDraft != null ||
        graceDraft != null) {
      return;
    }
    setState(() => quickStarting = true);
    try {
      // Re-read names and drafts: the visible home may be older than storage.
      final people = await participantPreferences.load();
      if (!mounted || people.myName.trim().isEmpty) {
        return;
      }
      final pendingQuestion = await questionDraftRepository.load();
      final pendingGrace = await graceDraftRepository.load();
      if (!mounted) {
        return;
      }
      if (pendingQuestion != null || pendingGrace != null) {
        await loadProgress();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('진행 중인 기록을 먼저 이어서 마무리해 주세요.')),
        );
        return;
      }
      if (together) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const ParticipantSetupPage(
              initialMode: ParticipationMode.together,
              quickTogether: true,
            ),
          ),
        );
        return;
      }
      await participantPreferences.remember(
        people.myName, null,
      );
      if (!mounted) {
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CourseSelectionPage(
            participationMode: ParticipationMode.solo,
            myName: people.myName,
            myHonorific: '',
            partnerName: '',
            partnerHonorific: '',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('빠른 시작을 준비하지 못했습니다. 기존 기록은 유지됩니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => quickStarting = false);
        await loadParticipants();
        if (mounted) {
          await loadProgress();
        }
      }
    }
  }

  Widget buildQuickStart() {
    if (participantsLoading) {
      return const SizedBox.shrink();
    }
    if (participantsFailed) {
      return Column(
        children: [
          const Text('빠른 시작에 사용할 이름을 불러오지 못했습니다.'),
          TextButton(onPressed: loadParticipants, child: const Text('이름 다시 불러오기')),
        ],
      );
    }
    if (quickParticipants.myName.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      key: const ValueKey('home-quick-start'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('빠른 시작', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('내 이름: ${quickParticipants.myName}'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: quickStarting ? null : () => quickStart(together: false),
              icon: const Icon(Icons.person),
              label: const Text('혼자 하기'),
            ),
            OutlinedButton.icon(
              onPressed: quickStarting ? null : () => quickStart(together: true),
              icon: const Icon(Icons.people),
              label: const Text('함께 하기'),
            ),
            const Text('이름 변경은 아래 문답 시작하기에서'),
            if (quickStarting) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Future<void> loadProgress() async {
    if (!mounted) return;
    final generation = ++loadGeneration;
    setState(() {
      isLoadingProgress = true;
      hasStorageError = false;
    });
    try {
      final store = completionRepository;
      final pending = store is CompletionEditingStore
          ? await CompletionActions(store).pending()
          : <PendingCompletion>[];
      final records = await completionRepository.loadAll();

      final savedDraft = await questionDraftRepository.load();

      var savedGrace = await graceDraftRepository.load();

      CompletionRecord? conflict;
      final completedGrace = savedGrace;
      if (completedGrace != null &&
          records.any((record) => record.id == completedGrace.id)) {
        if (!records.any(
          (record) => completedGrace.matchesCompletion(record),
        )) {
          conflict = records.firstWhere(
            (record) => record.id == completedGrace.id,
          );
        }
      }

      final remainingQuestion = savedGrace == null
          ? await questionDraftRepository.load()
          : savedDraft;
      if (!mounted || generation != loadGeneration) return;
      setState(() {
        recoveryCount = pending.length;
        chapter1Progress = ChapterProgress(
          records.where((r) => r.courseNumber == 1).length,
        );
        chapter2Progress = ChapterProgress(
          records.where((r) => r.courseNumber == 2).length,
        );
        questionDraft = savedGrace == null ? remainingQuestion : null;
        graceDraft = savedGrace;
        conflictingCompletion = conflict;
        isLoadingProgress = false;
      });
    } catch (_) {
      AppLogger.error(AppLogEvent.storageReadFailed);
      if (!mounted || generation != loadGeneration) return;
      setState(() {
        hasStorageError = true;
        isLoadingProgress = false;
        questionDraft = null;
        graceDraft = null;
        conflictingCompletion = null;
      });
    }
  }

  Future<void> resumeGrace() async {
    final draft = graceDraft;
    if (draft == null) return;
    final conflict = conflictingCompletion;
    if (conflict != null) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => GraceConflictPage(draft: draft, saved: conflict),
        ),
      );
      if (mounted) await loadProgress();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => draft.awaitingSignature
            ? CompletionSignaturePage(
                courseNumber: draft.courseNumber,
                courseTitle: draft.courseTitle,
                participationMode: draft.participationMode,
                myName: draft.myName,
                partnerName: draft.partnerName,
                graceReflection: draft.reflection,
                graceReflectionPending: false,
                graceDraft: draft,
              )
            : GraceReflectionPage(
                courseNumber: draft.courseNumber,
                courseTitle: draft.courseTitle,
                participationMode: draft.participationMode,
                myName: draft.myName,
                partnerName: draft.partnerName,
                initialDraft: draft,
              ),
      ),
    );
    if (mounted) await loadProgress();
  }

  Future<void> openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const CompletionHistoryPage()),
    );
    if (mounted) await loadProgress();
  }

  Future<void> openQuestions() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UsageGuidePage()),
    );
    if (mounted) await loadParticipants();
    if (mounted) await loadProgress();
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
    if (mounted) await loadProgress();
  }

  Future<void> discardDraft() async {
    final bool? shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('진행 중인 문답 삭제'),
        content: const Text('저장된 진행 내용을 삭제하고 처음부터 시작하시겠습니까?'),
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
          // Synthetic sync PoC: debug builds only; never shown in store releases.
          if (kDebugMode &&
              !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android)
            IconButton(
              tooltip: '합성 자료 연동 시험',
              icon: const Icon(Icons.cloud_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const MobilePocPage()),
              ),
            ),
          if (!isLoadingProgress && !hasStorageError && recoveryCount > 0)
            IconButton(
              tooltip: '저장되지 않은 기록 $recoveryCount개',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const UnsavedRecordsPage(),
                  ),
                );
                if (mounted) await loadProgress();
              },
            ),
          IconButton(
            tooltip: '나의 문답 기록',
            icon: const Icon(Icons.history),
            onPressed: openHistory,
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
              else if (hasStorageError)
                StorageFailureView(onRetry: loadProgress)
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
              if (!isLoadingProgress && !hasStorageError && recoveryCount > 0)
                Text('저장되지 않은 기록 $recoveryCount개'),
              if (graceDraft != null) ...[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Text(
                          conflictingCompletion != null
                              ? '은혜 기록 두 내용을 확인해 주세요'
                              : '마무리하지 않은 은혜 기록',
                        ),
                        Text(
                          '${graceDraft!.courseNumber}장 ${graceDraft!.courseTitle}',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: resumeGrace,
                          icon: const Icon(Icons.edit),
                          label: Text(
                            conflictingCompletion != null
                                ? '두 기록 비교하고 복구하기'
                                : graceDraft!.awaitingSignature
                                ? '서명 이어서 마무리하기'
                                : '은혜 기록 이어쓰기',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (questionDraft != null && graceDraft == null) ...[
                const SizedBox(height: 20),
                _ContinueQuestionCard(
                  draft: questionDraft!,
                  onContinue: resumeQuestions,
                  onRestart: discardDraft,
                ),
              ],
              if (!isLoadingProgress && !hasStorageError &&
                  questionDraft == null && graceDraft == null)
                buildQuickStart(),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      isLoadingProgress || hasStorageError || graceDraft != null || quickStarting
                      ? null
                      : openQuestions,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('문답 시작하기'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: openHistory,
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
