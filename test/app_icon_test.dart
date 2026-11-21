import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Static checks on launcher icon assets used by store builds.
const _iosIconDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _androidRes = 'android/app/src/main/res';
const _densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];

// PNG IHDR: width at 16, height at 20, color type at 25 (2 = RGB, 6 = RGBA).
({int width, int height, int colorType}) _pngInfo(String path) {
  final bytes = File(path).readAsBytesSync();
  int readInt(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  expect(bytes.sublist(1, 4), ascii.encode('PNG'), reason: path);
  return (width: readInt(16), height: readInt(20), colorType: bytes[25]);
}

void main() {
  group('launcher icons', () {
    test('iOS icons match Contents.json sizes and have no alpha channel', () {
      final contents = jsonDecode(
        File('$_iosIconDir/Contents.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final images = (contents['images'] as List).cast<Map<String, dynamic>>();
      expect(images, isNotEmpty);
      for (final image in images) {
        final points = double.parse((image['size'] as String).split('x').first);
        final scale = int.parse((image['scale'] as String).replaceAll('x', ''));
        final info = _pngInfo('$_iosIconDir/${image['filename']}');
        final expected = (points * scale).round();
        expect(info.width, expected, reason: '${image['filename']}');
        expect(info.height, expected, reason: '${image['filename']}');
        expect(info.colorType, 2, reason: '${image['filename']} must be RGB');
      }
    });

    test('Android adaptive icon is declared with all layers', () {
      final adaptive = File(
        '$_androidRes/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(adaptive, contains('@color/ic_launcher_background'));
      expect(adaptive, contains('@mipmap/ic_launcher_foreground'));
      expect(adaptive, contains('@mipmap/ic_launcher_monochrome'));
      expect(
        File('$_androidRes/values/ic_launcher_background.xml')
            .readAsStringSync(),
        contains('name="ic_launcher_background"'),
      );
    });

    test('Android icon PNGs exist for every density with expected sizes', () {
      const legacyDp = 48;
      const adaptiveDp = 108;
      const factors = [1.0, 1.5, 2.0, 3.0, 4.0];
      for (var i = 0; i < _densities.length; i++) {
        final dir = '$_androidRes/mipmap-${_densities[i]}';
        final legacy = _pngInfo('$dir/ic_launcher.png');
        expect(legacy.width, (legacyDp * factors[i]).round(), reason: dir);
        for (final layer in ['ic_launcher_foreground', 'ic_launcher_monochrome']) {
          final info = _pngInfo('$dir/$layer.png');
          expect(info.width, (adaptiveDp * factors[i]).round(),
              reason: '$dir/$layer');
          expect(info.colorType, 6, reason: '$dir/$layer needs transparency');
        }
      }
    });
  });
}
