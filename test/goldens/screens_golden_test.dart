@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/data/repositories/drift_journal_repo.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';

import '../helpers.dart';

// Renders the main screens with the real fonts and sample data, so design
// changes show up as image diffs. Update with:
//   flutter test test/goldens --update-goldens

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final a in assets) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  await load('Literata', [
    'assets/fonts/literata-500-normal.ttf',
    'assets/fonts/literata-600-normal.ttf',
    'assets/fonts/literata-400-italic.ttf',
  ]);
  await load('PlusJakartaSans', [
    'assets/fonts/plus-jakarta-sans-400-normal.ttf',
    'assets/fonts/plus-jakarta-sans-500-normal.ttf',
    'assets/fonts/plus-jakarta-sans-600-normal.ttf',
    'assets/fonts/plus-jakarta-sans-700-normal.ttf',
    'assets/fonts/plus-jakarta-sans-400-italic.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final bytes = icons.readAsBytesSync();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

List<JournalEntry> _sample() {
  final now = DateTime.now();
  DateTime at(int daysAgo, int h, [int m = 0]) =>
      DateTime(now.year, now.month, now.day - daysAgo, h, m);
  return [
    JournalEntry(
      id: '1',
      createdAt: at(0, 9, 15),
      mood: 4,
      sleepHours: 7.5,
      note:
          'Morning walk in the woods helped clear the remaining fog. Energy is returning slowly.',
      symptoms: const ['Neck tension'],
      medications: const ['Magnesium 400mg'],
    ),
    JournalEntry(
      id: '2',
      createdAt: at(1, 20, 40),
      mood: 2,
      sleepHours: 5,
      fromVoice: true,
      note:
          'Aura started around 10am at the screen. Rested in a dark room for 3 hours; medication relieved the sharp pain.',
      symptoms: const ['Migraine', 'Light sensitivity', 'Nausea'],
      medications: const ['Sumatriptan 50mg'],
    ),
    JournalEntry(
      id: '3',
      createdAt: at(3, 18),
      mood: 5,
      sleepHours: 8,
      note: 'Felt vibrant all afternoon. Zero headache symptoms.',
    ),
    JournalEntry(
      id: '4',
      createdAt: at(5, 8),
      mood: 1,
      sleepHours: 4.5,
      symptoms: const ['Migraine'],
      medications: const ['Sumatriptan 50mg'],
    ),
    JournalEntry(
      id: '5',
      createdAt: at(8, 21),
      mood: 3,
      sleepHours: 6.5,
      symptoms: const ['Migraine', 'Fatigue'],
    ),
    JournalEntry(
      id: '6',
      createdAt: at(11, 7),
      mood: 2,
      sleepHours: 5.5,
      symptoms: const ['Migraine'],
    ),
    JournalEntry(id: '7', createdAt: at(14, 19), mood: 4, sleepHours: 8),
  ];
}

Future<void> _pumpApp(
  WidgetTester tester,
  TestApp app, {
  bool nature = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  if (nature) app.storage.data['pref_nature_backgrounds'] = 'true';
  await tester.runAsync(() async {
    final repo = DriftJournalRepo(app.db);
    for (final e in _sample()) {
      await repo.saveEntry(e);
    }
  });
  await tester.pumpWidget(app.build(natureBackgrounds: nature));
  await settle(tester);
  // Decode asset images for real.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _snap(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('screens/$name.png'),
  );
}

void main() {
  setUpAll(_loadFonts);

  for (final (label, nature, brightness) in [
    ('plain', false, Brightness.light),
    ('nature', true, Brightness.light),
    ('dark', false, Brightness.dark),
  ]) {
    testWidgets('journal · $label', (tester) async {
      final app = TestApp();
      addTearDown(app.db.close);
      await _pumpApp(tester, app, nature: nature, brightness: brightness);
      await _snap(tester, 'journal_$label');
    });

    testWidgets('new entry · $label', (tester) async {
      final app = TestApp();
      addTearDown(app.db.close);
      await _pumpApp(tester, app, nature: nature, brightness: brightness);
      await tester.tap(find.text('Log Entry'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Mood Good'));
      await tester.tap(find.text('+ Migraine'));
      await tester.pumpAndSettle();
      await _snap(tester, 'entry_$label');
    });

    testWidgets('ask · $label', (tester) async {
      final app = TestApp();
      addTearDown(app.db.close);
      await _pumpApp(tester, app, nature: nature, brightness: brightness);
      await tester.tap(find.text('Ask'));
      await settle(tester);
      await _snap(tester, 'ask_$label');
    });

    testWidgets('settings · $label', (tester) async {
      final app = TestApp();
      addTearDown(app.db.close);
      await _pumpApp(tester, app, nature: nature, brightness: brightness);
      await tester.tap(find.text('Settings'));
      await settle(tester);
      await _snap(tester, 'settings_$label');
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -1500));
      await tester.pumpAndSettle();
      await _snap(tester, 'settings_${label}_lower');
    });
  }

  testWidgets('lock screen', (tester) async {
    final app = TestApp();
    addTearDown(app.db.close);
    app.storage.data['lock_pin_hash'] = 'x';
    await _pumpApp(tester, app);
    await _snap(tester, 'lock');
  });

  testWidgets('welcome', (tester) async {
    final app = TestApp(onboarded: false);
    addTearDown(app.db.close);
    await _pumpApp(tester, app);
    await _snap(tester, 'welcome');
  });
}
