part of '../main.dart';

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

