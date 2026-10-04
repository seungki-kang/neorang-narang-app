part of '../main.dart';

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

