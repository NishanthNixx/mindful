import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/presentation/shared/appearance.dart';

void main() {
  test('stored theme values parse, unknown falls back to system', () {
    expect(ThemeModeNotifier.parse('dark'), ThemeMode.dark);
    expect(ThemeModeNotifier.parse('light'), ThemeMode.light);
    expect(ThemeModeNotifier.parse('system'), ThemeMode.system);
    expect(ThemeModeNotifier.parse(null), ThemeMode.system);
    expect(ThemeModeNotifier.parse('sepia'), ThemeMode.system);
  });
}
