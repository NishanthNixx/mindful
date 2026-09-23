import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/data/repositories/drift_journal_repo.dart';
import 'package:mindfull/domain/entities/journal_entry.dart';

import '../helpers.dart';

final Finder notesField = find.widgetWithText(
  TextField,
  'How does your body feel right now? Triggers, food, stress, how the day went…',
);

void main() {
  late TestApp app;

  setUp(() => app = TestApp());
  tearDown(() => app.db.close());

  testWidgets('empty state, then create an entry and see it on the timeline', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app.build());
    await settle(tester);
    expect(find.text('Your journal is empty'), findsOneWidget);
    expect(find.bySemanticsLabel('Network: Off'), findsOneWidget);

    await tester.tap(find.text('Log Entry'));
    await settle(tester);

    // Save is refused without a mood.
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Pick a mood to save this entry.'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.text('Save')),
    ).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await tapVisible(tester, find.bySemanticsLabel('Mood Low'));
    await tapVisible(tester, find.text('+ Migraine'));

    await tapVisible(tester, find.text('Add custom').last);
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Sumatriptan 50mg'),
      'Sumatriptan',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await scrollTo(tester, find.text('Notes'));
    await tester.enterText(notesField, 'Aura in the morning');
    await tester.pump();
    await tapVisible(tester, find.text('Save Journal Entry'));
    await settle(tester);

    expect(find.textContaining('Today,'), findsOneWidget);
    expect(find.text('Entry saved'), findsOneWidget);
    expect(find.text('Aura in the morning'), findsOneWidget);
    expect(find.text('Sumatriptan'), findsOneWidget);

    final saved = await tester.runAsync(
      () => DriftJournalRepo(app.db).watchEntries().first,
    );
    expect(saved!.single.mood, 2);
    expect(saved.single.symptoms, ['Migraine']);
    expect(saved.single.medications, ['Sumatriptan']);
  });

  testWidgets('voice dictation appends to the note and marks the entry', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app.build());
    await settle(tester);
    await tester.tap(find.text('Log Entry'));
    await settle(tester);

    await tapVisible(tester, find.bySemanticsLabel('Mood Good'));
    await scrollTo(tester, find.byTooltip('Dictate (on-device)'));
    await tester.enterText(notesField, 'Started');
    await tapVisible(tester, find.byTooltip('Dictate (on-device)'));
    await tester.pump();
    expect(find.text('Listening on-device…'), findsOneWidget);
    app.speech.onResult!('felt better after lunch', isFinal: true);
    await tester.pump();
    expect(find.text('Started felt better after lunch'), findsOneWidget);

    await tapVisible(tester, find.text('Save Journal Entry'));
    await settle(tester);
    final saved = await tester.runAsync(
      () => DriftJournalRepo(app.db).watchEntries().first,
    );
    expect(saved!.single.fromVoice, isTrue);
  });

  testWidgets('tapping an entry opens it for editing and delete removes it', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.runAsync(
      () => DriftJournalRepo(app.db).saveEntry(
        JournalEntry(
          id: 'e1',
          createdAt: DateTime.now(),
          mood: 5,
          note: 'Great run',
        ),
      ),
    );
    await tester.pumpWidget(app.build());
    await settle(tester);

    await tapVisible(tester, find.text('Great run'));
    await settle(tester);
    expect(find.text('Edit Entry'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    expect(find.text('Your journal is empty'), findsOneWidget);
  });

  testWidgets('Ask tab shows a clear model-not-ready state', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app.build());
    await settle(tester);
    await tester.tap(find.text('Ask'));
    await settle(tester);
    expect(find.text("On-device AI isn't set up yet"), findsOneWidget);
  });

  testWidgets('nature backgrounds toggle from Settings', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app.build());
    await settle(tester);
    expect(
      find
          .byType(Image)
          .evaluate()
          .where((e) => '${(e.widget as Image).image}'.contains('backgrounds')),
      isEmpty,
    );

    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tapVisible(tester, find.text('Nature backgrounds'));
    await settle(tester);
    expect(app.storage.data['pref_nature_backgrounds'], 'true');
    expect(
      find
          .byType(Image)
          .evaluate()
          .where(
            (e) => '${(e.widget as Image).image}'.contains('settings.jpg'),
          ),
      isNotEmpty,
    );
  });

  testWidgets('theme can be forced to dark and is remembered', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app.build());
    await settle(tester);
    BuildContext ctx() => tester.element(find.byType(Scaffold).first);
    expect(Theme.of(ctx()).brightness, Brightness.light);

    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tapVisible(tester, find.text('Dark'));
    await settle(tester);

    expect(Theme.of(ctx()).brightness, Brightness.dark);
    expect(app.storage.data['pref_theme_mode'], 'dark');
    expect(
      find.text('Always dark — easier on the eyes at night'),
      findsOneWidget,
    );
  });
}
