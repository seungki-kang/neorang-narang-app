part of '../main.dart';

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

