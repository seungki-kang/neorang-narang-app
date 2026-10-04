part of '../main.dart';

class CompletionRecord {
  const CompletionRecord({
    required this.id,
    required this.courseNumber,
    required this.courseTitle,
    required this.participationMode,
    required this.myName,
    required this.partnerName,
    required this.completedAt,
    required this.mySignedAt,
    required this.partnerSignedAt,
    required this.graceReflection,
    required this.graceReflectionPending,
  });

  final String id;
  final int courseNumber;
  final String courseTitle;
  final ParticipationMode participationMode;
  final String myName;
  final String partnerName;
  final DateTime completedAt;
  final DateTime mySignedAt;
  final DateTime? partnerSignedAt;
  final String graceReflection;
  final bool graceReflectionPending;

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseNumber': courseNumber,
        'courseTitle': courseTitle,
        'participationMode': participationMode.name,
        'myName': myName,
        'partnerName': partnerName,
        'completedAt': completedAt.toIso8601String(),
        'mySignedAt': mySignedAt.toIso8601String(),
        'partnerSignedAt': partnerSignedAt?.toIso8601String(),
        'graceReflection': graceReflection,
        'graceReflectionPending': graceReflectionPending,
      };

  CompletionRecord withGraceReflection(String reflection) {
    return CompletionRecord(
      id: id,
      courseNumber: courseNumber,
      courseTitle: courseTitle,
      participationMode: participationMode,
      myName: myName,
      partnerName: partnerName,
      completedAt: completedAt,
      mySignedAt: mySignedAt,
      partnerSignedAt: partnerSignedAt,
      graceReflection: reflection,
      graceReflectionPending: false,
    );
  }

  factory CompletionRecord.fromJson(Map<String, dynamic> json) {
    return CompletionRecord(
      id: json['id'] as String,
      courseNumber: json['courseNumber'] as int,
      courseTitle: json['courseTitle'] as String,
      participationMode: json['participationMode'] == 'together'
          ? ParticipationMode.together
          : ParticipationMode.solo,
      myName: json['myName'] as String,
      partnerName: json['partnerName'] as String,
      completedAt: DateTime.parse(json['completedAt'] as String),
      mySignedAt: DateTime.parse(json['mySignedAt'] as String),
      partnerSignedAt: json['partnerSignedAt'] == null
          ? null
          : DateTime.parse(json['partnerSignedAt'] as String),
      graceReflection: json['graceReflection'] as String? ?? '',
      graceReflectionPending:
          json['graceReflectionPending'] as bool? ?? false,
    );
  }
}

