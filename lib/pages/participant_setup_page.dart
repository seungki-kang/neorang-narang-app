part of '../main.dart';

class ParticipantSetupPage extends StatefulWidget {
  const ParticipantSetupPage({super.key});

  @override
  State<ParticipantSetupPage> createState() =>
      _ParticipantSetupPageState();
}

class _ParticipantSetupPageState extends State<ParticipantSetupPage> {
  final ParticipantPreferencesRepository preferencesRepository =
      ParticipantPreferencesRepository();
  List<String> recentPartners = [];
  bool loading = true;
  bool saving = false;
  bool loadFailed = false;

  @override
  void initState() {
    super.initState();
    loadPreferences();
  }

  Future<void> loadPreferences() async {
    setState(() { loading = true; loadFailed = false; });
    try {
      final value = await preferencesRepository.load();
      if (!mounted) return;
      setState(() {
        myNameController.text = value.myName;
        recentPartners = value.recentPartners;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { loading = false; loadFailed = true; });
    }
  }

  Future<void> removePartner(String name) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final value = await preferencesRepository.removePartner(name);
      if (!mounted) return;
      setState(() {
        recentPartners = value.recentPartners;
        if (partnerNameController.text.trim() == name) {
          partnerNameController.clear();
        }
      });
    } catch (_) {
      if (mounted) showMessage('이름을 목록에서 지우지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

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

  Future<void> continueToCourses() async {
    if (loading || saving || loadFailed) return;
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

    setState(() => saving = true);
    try {
      final value = await preferencesRepository.remember(
        myName, selectedMode == ParticipationMode.together ? partnerName : null,
      );
      if (!mounted) return;
      setState(() => recentPartners = value.recentPartners);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CourseSelectionPage(
            participationMode: selectedMode,
            myName: myName,
            myHonorific: '',
            partnerName: selectedMode == ParticipationMode.together ? partnerName : '',
            partnerHonorific: '',
          ),
        ),
      );
    } catch (_) {
      if (mounted) showMessage('참여자 정보를 저장하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget buildNameField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      enabled: !loading && !saving && !loadFailed,
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
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : loadFailed
              ? StorageFailureView(onRetry: loadPreferences)
              : SingleChildScrollView(
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
              onSelectionChanged: saving ? null : (selectedValues) {
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
            const SizedBox(height: 8),
            const Text('과정을 선택하면 내 이름을 이 기기에 기억합니다.\n'
                '다음에는 자동으로 채워지며, 언제든 수정할 수 있습니다.',
                textAlign: TextAlign.center),
            if (isTogether) ...[
              const SizedBox(height: 24),
              buildNameField(
                controller: partnerNameController,
                label: '상대방 이름',
              ),
              if (recentPartners.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('최근 함께한 사람 · 이름을 눌러 선택하세요'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: recentPartners.map((name) => InputChip(
                    label: Text(name),
                    onPressed: saving ? null : () {
                      setState(() => partnerNameController.text = name);
                    },
                    onDeleted: saving ? null : () => removePartner(name),
                    deleteButtonTooltipMessage: '최근 목록에서 지우기',
                  )).toList(),
                ),
              ],
              const SizedBox(height: 8),
              const Text('최근 5명까지 이 기기에 기억합니다.\n'
                  '목록에서 지워도 기존 문답 기록은 유지됩니다.',
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: saving ? null : continueToCourses,
                icon: const Icon(Icons.arrow_forward),
                label: Text(saving ? '처리 중…' : '과정 선택으로'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

