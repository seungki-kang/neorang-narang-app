import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Static checks on store release configuration. Release/profile builds use
// only the main manifest; PoC-only entries must stay in the debug manifest.
String _read(String path) => File(path).readAsStringSync();

void main() {
  group('store release configuration', () {
    test('main manifest has the store label and no PoC entries', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:label="너랑나랑"'));
      expect(manifest, isNot(contains('jesuslife-poc')));
      expect(manifest, isNot(contains('android.permission.INTERNET')));
    });

    test('debug manifest keeps the PoC return URI and INTERNET', () {
      final manifest = _read('android/app/src/debug/AndroidManifest.xml');
      expect(manifest, contains('android.permission.INTERNET'));
      expect(manifest, contains('android:name=".MainActivity"'));
      expect(manifest, contains('android:scheme="jesuslife-poc"'));
      expect(manifest, contains('android:host="auth"'));
      expect(manifest, contains('android:path="/complete/android"'));
    });

    test('iOS display name is the store name', () {
      final plist = _read('ios/Runner/Info.plist');
      expect(
        RegExp(r'<key>CFBundleDisplayName</key>\s*<string>너랑나랑</string>')
            .hasMatch(plist),
        isTrue,
      );
    });
  });
}
