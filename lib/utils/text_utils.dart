part of '../main.dart';

String withTopicParticle(String text) {
  if (text.isEmpty) return text;
  final int code = text.runes.last;
  final bool hasFinalConsonant =
      code >= 0xAC00 && code <= 0xD7A3 && (code - 0xAC00) % 28 != 0;
  return '$text${hasFinalConsonant ? '은' : '는'}';
}

String formatSignedAt(DateTime dateTime) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${dateTime.year}.${twoDigits(dateTime.month)}.${twoDigits(dateTime.day)} '
      '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
}

