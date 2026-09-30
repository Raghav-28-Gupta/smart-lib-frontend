// test/support/fixtures.dart
//
// Loads a real backend response captured by tool/capture_fixtures.dart.
// `flutter test` runs with the package root as the working directory, so
// the relative path resolves the same on every platform.
import 'dart:convert';
import 'dart:io';

/// Decoded JSON of `test/fixtures/<name>.json` -- a Map or a List,
/// depending on the endpoint.
dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());
