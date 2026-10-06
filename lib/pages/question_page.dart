part of '../main.dart';

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

    // 문답 화면이 열려 있는 동안 화면이 꺼지지 않도록 합니다.
    WakelockPlus.enable();

    currentQuestionIndex = widget.initialQuestionIndex;
    myDisplayName = makeAddress(widget.myName, widget.myHonorific);
    partnerDisplayName =
        makeAddress(widget.partnerName, widget.partnerHonorific);

    questions = widget.courseNumber == 1
        ? List<QuestionItem>.of(chapter1Questions)
        : List<QuestionItem>.of(chapter2Questions);

    if (currentQuestionIndex < 0 ||
        currentQuestionIndex >= questions.length) {
      currentQuestionIndex = 0;
    }

    saveDraft();
  }

  @override
  void dispose() {
    // 문답 화면을 나가면 화면 꺼짐 방지를 해제합니다.
    WakelockPlus.disable();
    super.dispose();
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
