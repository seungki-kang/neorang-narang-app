part of '../main.dart';

class QuestionItem {
  const QuestionItem({
    required this.id,
    required this.questionTemplate,
    required this.answerLines,
  });

  final String id;
  final String questionTemplate;
  final List<String> answerLines;
}

