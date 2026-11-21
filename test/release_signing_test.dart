import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Static checks on Android release signing configuration. The real upload key
// and android/key.properties are never in the repository.
String _read(String path) => File(path).readAsStringSync();

void main() {
  group('android release signing', () {
    test('release build never falls back to the debug key', () {
      final gradle = _read('android/app/build.gradle.kts');
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
      expect(gradle, contains('rootProject.file("key.properties")'));
      expect(gradle, contains('signingConfigs.getByName("release")'));
      // Release tasks stop with a message when signing is not configured.
      expect(gradle, contains('gradle.taskGraph.whenReady'));
      expect(gradle, contains('throw GradleException('));
    });

    test('key material is git-ignored', () {
      final ignore = _read('android/.gitignore');
      for (final pattern in ['key.properties', '**/*.keystore', '**/*.jks']) {
        expect(ignore.split('\n').map((line) => line.trim()), contains(pattern));
      }
    });

    test('key.properties template lists every required entry', () {
      final template = _read('android/key.properties.example');
      for (final key in ['storeFile', 'storePassword', 'keyAlias', 'keyPassword']) {
        expect(template, matches(RegExp('^$key=', multiLine: true)));
      }
    });
  });
}
