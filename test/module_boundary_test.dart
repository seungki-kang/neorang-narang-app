import 'package:flutter_test/flutter_test.dart';
import 'package:neorang_narang_app/main.dart' as app;
import 'package:neorang_narang_app/models/chapter_progress.dart' as progress;
import 'package:neorang_narang_app/models/participation_mode.dart' as mode;
import 'package:neorang_narang_app/models/question_item.dart' as question;
import 'package:neorang_narang_app/utils/name_utils.dart' as names;
import 'package:neorang_narang_app/utils/text_utils.dart' as text;

void main() {
  test('direct module and main exports retain the same public types', () {
    expect(identical(app.ParticipationMode.solo, mode.ParticipationMode.solo), isTrue);
    const progress.ChapterProgress direct = app.ChapterProgress(50);
    const question.QuestionItem item = app.QuestionItem(
      id: 'module-boundary', questionTemplate: '질문', answerLines: ['답'],
    );
    expect(direct.season, 2);
    expect(item.id, 'module-boundary');
    expect(identical(app.makeAddress, names.makeAddress), isTrue);
    expect(identical(app.withTopicParticle, text.withTopicParticle), isTrue);
    expect(identical(app.formatSignedAt, text.formatSignedAt), isTrue);
  });
}
