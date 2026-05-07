// Golden-path integration test stub.
//
// To run on a connected Android device:
//   flutter test integration_test/golden_path_test.dart
//
// This test verifies the end-to-end happy path:
//   1. Create a custom exercise
//   2. Create a template containing it
//   3. Start a session, validate 3 sets
//   4. Finish the session
//   5. Re-start a session — the engine suggests an updated target

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muscul_app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Golden path stub — app boots to Home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MusculApp()));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Accueil'), findsOneWidget);
  });
}
