import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mindfull/core/providers.dart';

/// Which soft nature photo sits behind a screen when nature backgrounds are on.
enum Scene {
  journal('assets/images/backgrounds/journal.jpg'),
  entry('assets/images/backgrounds/entry.jpg'),
  ask('assets/images/backgrounds/ask.jpg'),
  settings('assets/images/backgrounds/settings.jpg')
  ;

  const Scene(this.asset);

  final String asset;
}

/// Plain parchment by default; nature photo backgrounds are opt-in.
class NatureBackgroundsNotifier extends Notifier<bool> {
  NatureBackgroundsNotifier({bool initial = false}) : _initial = initial;

  static const storageKey = 'pref_nature_backgrounds';

  final bool _initial;

  @override
  bool build() => _initial;

  Future<void> set({required bool enabled}) async {
    state = enabled;
    await ref
        .read(secureStorageProvider)
        .write(key: storageKey, value: '$enabled');
  }
}

final natureBackgroundsProvider =
    NotifierProvider<NatureBackgroundsNotifier, bool>(
      NatureBackgroundsNotifier.new,
    );

/// System (follow the phone), or force light / dark for Mindfull only.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  ThemeModeNotifier({ThemeMode initial = ThemeMode.system})
    : _initial = initial;

  static const storageKey = 'pref_theme_mode';

  final ThemeMode _initial;

  /// Unknown or missing values fall back to following the system.
  static ThemeMode parse(String? raw) => ThemeMode.values.firstWhere(
    (m) => m.name == raw,
    orElse: () => ThemeMode.system,
  );

  @override
  ThemeMode build() => _initial;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref
        .read(secureStorageProvider)
        .write(key: storageKey, value: mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
