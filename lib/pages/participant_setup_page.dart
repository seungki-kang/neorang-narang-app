part of '../main.dart';

class ParticipantSetupPage extends StatefulWidget {
  const ParticipantSetupPage({super.key});

  @override
  State<ParticipantSetupPage> createState() =>
      _ParticipantSetupPageState();
}

class _ParticipantSetupPageState extends State<ParticipantSetupPage> {
  ParticipationMode selectedMode = ParticipationMode.solo;

  final TextEditingController myNameController = TextEditingController();
  final TextEditingController partnerNameController = TextEditingController();

  @override
  void dispose() {
    myNameController.dispose();
    partnerNameController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void continueToCourses() {
    final String myName = myNameController.text.trim();
    final String partnerName = partnerNameController.text.trim();

    if (myName.isEmpty) {
      showMessage('나의 이름을 입력해 주세요.');
      return;
    }

    if (selectedMode == ParticipationMode.together && partnerName.isEmpty) {
      showMessage('상대방 이름을 입력해 주세요.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CourseSelectionPage(
          participationMode: selectedMode,
          myName: myName,
          myHonorific: '',
          partnerName: partnerName,
          partnerHonorific: '',
        ),
      ),
    );
  }

  Widget buildNameField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: label == '나의 이름'
            ? '예: 강승기 또는 강승기 목사님'
            : '예: 김애숙 또는 김애숙 목사님',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.person),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTogether = selectedMode == ParticipationMode.together;

    return Scaffold(
      appBar: AppBar(
        title: const Text('참여자 설정'),
        backgroundColor: Colors.deepPurple.shade200,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              '어떻게 문답하시겠습니까?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            SegmentedButton<ParticipationMode>(
              segments: const [
                ButtonSegment(
                  value: ParticipationMode.solo,
                  icon: Icon(Icons.person),
                  label: Text('혼자 하기'),
                ),
                ButtonSegment(
                  value: ParticipationMode.together,
                  icon: Icon(Icons.people),
                  label: Text('함께 하기'),
                ),
              ],
              selected: {selectedMode},
              onSelectionChanged: (selectedValues) {
                setState(() {
                  selectedMode = selectedValues.first;
                });
              },
            ),
            const SizedBox(height: 30),
            buildNameField(
              controller: myNameController,
              label: '나의 이름',
            ),
            if (isTogether) ...[
              const SizedBox(height: 24),
              buildNameField(
                controller: partnerNameController,
                label: '상대방 이름',
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: continueToCourses,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('과정 선택으로'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

