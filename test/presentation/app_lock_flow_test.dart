import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<void> _settle(WidgetTester tester) => settle(tester);

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.widgetWithText(TextButton, d));
  }
  await tapVisible(tester, find.text('Continue'));
  await _settle(tester);
}

void main() {
  testWidgets('first run requires acknowledging the disclaimer', (
    tester,
  ) async {
    usePhoneSize(tester);
    final app = TestApp(onboarded: false);
    addTearDown(app.db.close);
    await tester.pumpWidget(app.build());
    await _settle(tester);

    final start = find.widgetWithText(FilledButton, 'Get started');
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    await tapVisible(tester, find.byType(Checkbox));
    await tester.pump();
    await tapVisible(tester, start);
    await _settle(tester);
    expect(find.text('Journal'), findsWidgets);
    expect(app.storage.data['onboarded_v1'], 'true');
  });

  testWidgets('set a PIN, lock, then unlock with it', (tester) async {
    usePhoneSize(tester);
    final app = TestApp();
    addTearDown(app.db.close);
    await tester.pumpWidget(app.build());
    await _settle(tester);

    await tester.tap(find.text('Settings'));
    await _settle(tester);
    await tapVisible(tester, find.text('App lock'));
    await _settle(tester);

    expect(find.text('Choose a PIN'), findsOneWidget);
    await _enterPin(tester, '2468');
    expect(find.text('Confirm your PIN'), findsOneWidget);
    await _enterPin(tester, '2468');
    expect(find.text('App lock is on'), findsOneWidget); // snackbar
    expect(app.storage.data['lock_pin_hash'], isNotNull);

    await tapVisible(tester, find.text('Lock now'));
    await _settle(tester);
    expect(find.text('Mindfull is locked'), findsOneWidget);

    await _enterPin(tester, '1111');
    expect(find.textContaining('Wrong PIN'), findsOneWidget);

    await _enterPin(tester, '2468');
    expect(find.text('Mindfull is locked'), findsNothing);
  });

  testWidgets('cold start with lock enabled shows lock screen', (tester) async {
    usePhoneSize(tester);
    final app = TestApp();
    addTearDown(app.db.close);
    app.storage.data['lock_pin_hash'] = 'placeholder';
    await tester.pumpWidget(app.build());
    await _settle(tester);
    expect(find.text('Mindfull is locked'), findsOneWidget);
  });

  testWidgets('app switcher shows a privacy shield', (tester) async {
    usePhoneSize(tester);
    final app = TestApp();
    addTearDown(app.db.close);
    await tester.pumpWidget(app.build());
    await _settle(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const ValueKey('privacy-shield')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const ValueKey('privacy-shield')), findsNothing);
  });
}
