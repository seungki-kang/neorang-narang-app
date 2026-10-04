part of '../main.dart';

class ChapterProgress {
  const ChapterProgress(this.completedCount);

  final int completedCount;
  int get stars => completedCount ~/ 50;
  int get season => stars + 1;
  int get countInSeason => completedCount % 50;
}
