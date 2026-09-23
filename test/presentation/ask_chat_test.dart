import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindfull/domain/ai/model_spec.dart';

import '../helpers.dart';

/// A few frames without waiting for animations to end (the reply spinner
/// never does while streaming).
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  late TestApp app;

  setUp(() => app = TestApp());
  tearDown(() => app.db.close());

  Future<void> installModel() async {
    File(
      '${app.modelsDir.path}/${ModelCatalog.gemma4E2b.fileName}',
    ).writeAsBytesSync([1, 2, 3]);
    app.storage.data['model_installed_id'] = ModelCatalog.gemma4E2b.id;
  }

  Future<void> openAsk(WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app.build());
    await settle(tester);
    await tester.tap(find.text('Ask'));
    await settle(tester);
  }

  testWidgets('opening Ask loads the installed model, then streams a reply', (
    tester,
  ) async {
    await installModel();
    await openAsk(tester);

    expect(app.engine.loaded, ModelCatalog.gemma4E2b);
    expect(find.text('Chat privately with Gemma 4 E2B'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'How can I sleep better?');
    await tester.tap(find.byTooltip('Send'));
    await pumpFrames(tester);

    final session = app.engine.sessions.single;
    expect(session.prompts, ['How can I sleep better?']);
    expect(session.systemInstruction, contains('not a doctor'));
    expect(find.text('How can I sleep better?'), findsOneWidget);
    expect(find.text('Starting…'), findsOneWidget);

    session
      ..emit('Try a regular ')
      ..emit('bedtime.');
    await tester.pump();
    expect(
      find.textContaining('Try a regular bedtime.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Stop generating'), findsOneWidget);

    await session.finish();
    await settle(tester);
    expect(find.text('Stop generating'), findsNothing);
    expect(find.textContaining('to first token'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('Stop cancels generation on the engine', (tester) async {
    await installModel();
    await openAsk(tester);
    await tester.enterText(find.byType(TextField), 'Tell me a long story');
    await tester.tap(find.byTooltip('Send'));
    await pumpFrames(tester);
    final session = app.engine.sessions.single..emit('Once upon');
    await tester.pump();

    await tester.tap(find.byTooltip('Stop'));
    await settle(tester);
    expect(session.stops, 1);
    expect(find.textContaining('Stopped'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('new chat starts a fresh session', (tester) async {
    await installModel();
    await openAsk(tester);
    await tester.enterText(find.byType(TextField), 'Hi');
    await tester.tap(find.byTooltip('Send'));
    await pumpFrames(tester);
    final first = app.engine.sessions.single..emit('Hello!');
    await first.finish();
    await settle(tester);

    await tester.tap(find.byTooltip('New chat'));
    await settle(tester);
    expect(first.closed, isTrue);
    expect(find.text('Chat privately with Gemma 4 E2B'), findsOneWidget);
  });

  testWidgets(
    'without a model, Ask links to the model manager with a recommendation',
    (tester) async {
      await openAsk(tester);
      expect(find.text("On-device AI isn't set up yet"), findsOneWidget);
      await tapVisible(tester, find.text('Set up on-device AI'));
      await settle(tester);

      expect(find.text('On-device AI'), findsWidgets);
      expect(find.text('Gemma 4 E2B'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Download 2.4 GB'), findsOneWidget);
      expect(find.textContaining('Test Phone'), findsOneWidget);
      // Qwen is offered as the alternative on a 12 GB phone.
      expect(find.textContaining('Qwen3 0.6B'), findsOneWidget);
    },
  );

  testWidgets('a low-memory phone sees AI switched off, journal unaffected', (
    tester,
  ) async {
    app.device.totalRamBytes = 2 * 1024 * 1024 * 1024;
    await openAsk(tester);
    expect(find.text('On-device AI is off on this phone'), findsOneWidget);
    expect(find.text('Set up on-device AI'), findsNothing);
  });
}
