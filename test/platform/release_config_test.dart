// test/platform/release_config_test.dart
//
// Guards the platform files a release build depends on. These break silently:
// the app compiles and launches, and only then fails every request.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  group('Android', () {
    final main = read('android/app/src/main/AndroidManifest.xml');

    test('release builds may use the network', () {
      // Flutter's template declares INTERNET only in the debug and profile
      // manifests, so a release APK without it fails every request.
      expect(main, contains('android.permission.INTERNET'));
    });

    test('plain HTTP stays allowed in debug builds only', () {
      // Release talks to the HTTPS backend; cleartext there would be a hole.
      expect(main, isNot(contains('usesCleartextTraffic')));
      expect(read('android/app/src/debug/AndroidManifest.xml'), contains('android:usesCleartextTraffic="true"'));
    });

    test('the app is installed as SmartLib, not the template name', () {
      expect(main, contains('android:label="SmartLib"'));
      final gradle = read('android/app/build.gradle.kts');
      expect(gradle, isNot(contains('com.example')));
    });
  });

  test('the web app is titled SmartLib', () {
    expect(read('web/index.html'), contains('<title>SmartLib</title>'));
    expect(read('web/manifest.json'), contains('"name": "SmartLib"'));
  });

  test('the Windows app is titled SmartLib', () {
    expect(read('windows/runner/main.cpp'), contains('L"SmartLib"'));
    expect(read('windows/runner/Runner.rc'), isNot(contains('com.example')));
  });
}
