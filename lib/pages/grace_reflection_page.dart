part of '../main.dart';

class GraceReflectionPage extends StatefulWidget {
  const GraceReflectionPage({
    super.key,
    required this.courseNumber,
    required this.courseTitle,
    required this.participationMode,
    required this.myName,
    required this.partnerName,
    this.initialDraft,
  });

  final int courseNumber;
  final String courseTitle;
  final ParticipationMode participationMode;
  final String myName;
  final String partnerName;
  final GraceDraft? initialDraft;

  @override
  State<GraceReflectionPage> createState() => _GraceReflectionPageState();
}

class _GraceReflectionPageState extends State<GraceReflectionPage>
    with WidgetsBindingObserver {
  GraceDraft? draft;
  Timer? saveTimer;
  bool loadingDraft = true;
  bool loadFailed = false;
  bool transitioning = false;
  String saveStatus = '';
  int revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeDraft();
  }

  Future<void> initializeDraft() async {
    setState(() {
      loadingDraft = true;
      loadFailed = false;
    });
    try {
      final stored = await graceDraftRepository.load();
      final initial = widget.initialDraft;
      if (stored != null &&
          (stored.courseNumber != widget.courseNumber ||
              stored.myName != widget.myName ||
              stored.partnerName != widget.partnerName ||
              stored.participationMode != widget.participationMode ||
              (initial != null && initial.id != stored.id))) {
        throw StateError('another_grace_draft_exists');
      }
      final value =
          stored ??
          initial ??
          GraceDraft(
            id: 'grace-${DateTime.now().microsecondsSinceEpoch}',
            courseNumber: widget.courseNumber,
            courseTitle: widget.courseTitle,
            participationMode: widget.participationMode,
            myName: widget.myName,
            partnerName: widget.partnerName,
          );
      await graceDraftRepository.save(value);
      if (!mounted) return;
      setState(() {
        draft = value;
        reflectionController.text = value.reflection;
        loadingDraft = false;
        saveStatus = '임시저장 완료';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loadingDraft = false;
        loadFailed = true;
      });
    }
  }

  void reflectionChanged(String _) {
    revision++;
    draft = draft!.copy(reflection: reflectionController.text);
    setState(() => saveStatus = '저장 중…');
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 300), persistDraft);
  }

  Future<bool> persistDraft() async {
    saveTimer?.cancel();
    final value = draft;
    if (value == null) return false;
    final savedRevision = revision;
    try {
      await graceDraftRepository.save(value);
      if (mounted && savedRevision == revision) {
        setState(() => saveStatus = '임시저장 완료');
      }
      return true;
    } catch (_) {
      if (mounted) setState(() => saveStatus = '임시저장 실패 · 다시 저장해 주세요');
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !transitioning) persistDraft();
  }

  final TextEditingController reflectionController = TextEditingController();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    saveTimer?.cancel();
    if (!transitioning && draft != null) {
      // The operation catches failures; process termination may still interrupt it.
      persistDraft();
    }
    reflectionController.dispose();
    super.dispose();
  }

  Future<void> continueToSignature({required bool skipReflection}) async {
    if (transitioning || loadingDraft || loadFailed) return;
    final String reflection = reflectionController.text.trim();
    if (skipReflection && reflection.isNotEmpty) return;
    if (!skipReflection && reflection.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('하나님이 주신 은혜를 기록해 주세요.')));
      return;
    }

    setState(() => transitioning = true);
    saveTimer?.cancel();
    draft = draft!.copy(reflection: reflection, awaitingSignature: true);
    if (!await persistDraft()) {
      if (mounted) setState(() => transitioning = false);
      return;
    }
    if (!mounted) return;
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
          graceDraft: draft,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('은혜 기록'),
        backgroundColor: Colors.deepPurple.shade200,
      ),
      body: loadingDraft
          ? const Center(child: CircularProgressIndicator())
          : loadFailed
          ? StorageFailureView(onRetry: initializeDraft)
          : SafeArea(
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
                      onChanged: reflectionChanged,
                      enabled: !transitioning,
                      minLines: 5,
                      maxLines: 8,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '하나님이 주신 은혜를 기록해 주세요.',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(saveStatus, textAlign: TextAlign.center),
                    if (saveStatus.startsWith('임시저장 실패'))
                      TextButton(
                        onPressed: persistDraft,
                        child: const Text('다시 저장'),
                      ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: transitioning
                          ? null
                          : () => continueToSignature(skipReflection: false),
                      icon: const Icon(Icons.edit),
                      label: const Text('은혜 기록하고 서명하기'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed:
                          transitioning ||
                              reflectionController.text.trim().isNotEmpty
                          ? null
                          : () => continueToSignature(skipReflection: true),
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
