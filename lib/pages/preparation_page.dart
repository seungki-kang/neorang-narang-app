part of '../main.dart';

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

