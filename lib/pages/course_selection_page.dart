part of '../main.dart';

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

