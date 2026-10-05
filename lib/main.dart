import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path_util;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

part 'app.dart';
part 'models/participation_mode.dart';
part 'models/question_draft.dart';
part 'models/completion_record.dart';
part 'models/chapter_progress.dart';
part 'models/question_item.dart';
part 'repositories/question_draft_repository.dart';
part 'repositories/completion_repository.dart';
part 'repositories/storage_contracts.dart';
part 'repositories/repositories.dart';
part 'data/storage_schema.dart';
part 'database/app_database.dart';
part 'repositories/sqlite_question_draft_repository.dart';
part 'repositories/sqlite_completion_repository.dart';
part 'services/storage_initializer.dart';
part 'data/question_data.dart';
part 'utils/name_utils.dart';
part 'utils/text_utils.dart';
part 'pages/home_page.dart';
part 'pages/completion_history_page.dart';
part 'pages/usage_guide_page.dart';
part 'pages/participant_setup_page.dart';
part 'pages/course_selection_page.dart';
part 'pages/preparation_page.dart';
part 'pages/grace_reflection_page.dart';
part 'pages/pending_grace_page.dart';
part 'pages/completion_signature_page.dart';
part 'pages/question_page.dart';
part 'widgets/continue_question_card.dart';
part 'widgets/progress_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeStorage();
  runApp(const MyApp());
}
