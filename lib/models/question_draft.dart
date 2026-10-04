part of '../main.dart';

class QuestionDraft {
  const QuestionDraft({
    required this.courseNumber,
    required this.courseTitle,
    required this.participationMode,
    required this.myDisplayName,
    required this.partnerDisplayName,
    required this.firstAskerIsMe,
    required this.currentQuestionIndex,
    required this.savedAt,
  });

  final int courseNumber;
  final String courseTitle;
  final ParticipationMode participationMode;
  final String myDisplayName;
  final String partnerDisplayName;
  final bool firstAskerIsMe;
  final int currentQuestionIndex;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'courseNumber': courseNumber,
        'courseTitle': courseTitle,
        'participationMode': participationMode.name,
        'myDisplayName': myDisplayName,
        'partnerDisplayName': partnerDisplayName,
        'firstAskerIsMe': firstAskerIsMe,
        'currentQuestionIndex': currentQuestionIndex,
        'savedAt': savedAt.toIso8601String(),
      };

  factory QuestionDraft.fromJson(Map<String, dynamic> json) {
    return QuestionDraft(
      courseNumber: json['courseNumber'] as int,
      courseTitle: json['courseTitle'] as String,
      participationMode: json['participationMode'] == 'together'
          ? ParticipationMode.together
          : ParticipationMode.solo,
      myDisplayName: json['myDisplayName'] as String,
      partnerDisplayName: json['partnerDisplayName'] as String? ?? '',
      firstAskerIsMe: json['firstAskerIsMe'] as bool? ?? true,
      currentQuestionIndex: json['currentQuestionIndex'] as int? ?? 0,
      savedAt: DateTime.parse(json['savedAt'] as String),
    );
  }
}

