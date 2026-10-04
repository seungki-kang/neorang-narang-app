part of '../main.dart';

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

