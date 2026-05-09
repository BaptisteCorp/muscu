// Smoke test: confirm the app boots without throwing. The original
// `flutter create` boilerplate referenced a non-existent `MyApp` and
// could never compile.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('basic widget tree pumps', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
