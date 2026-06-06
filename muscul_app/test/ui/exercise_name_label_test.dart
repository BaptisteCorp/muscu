import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reps/core/widgets/exercise_name_label.dart';
import 'package:reps/domain/models/enums.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('shows the name with the equipment label as a suffix',
      (tester) async {
    await pump(
      tester,
      const ExerciseNameLabel(
        name: 'Extension poulie haute',
        equipment: Equipment.rope,
      ),
    );

    // Both the name and the discreet equipment suffix are rendered in the
    // same (rich) text widget.
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.textSpan!.toPlainText(), contains('Extension poulie haute'));
    expect(text.textSpan!.toPlainText(), contains('Corde'));
  });

  testWidgets('renders for every equipment without throwing', (tester) async {
    for (final eq in Equipment.values) {
      await pump(
        tester,
        ExerciseNameLabel(name: 'Exo', equipment: eq),
      );
      expect(find.byType(ExerciseNameLabel), findsOneWidget);
    }
  });
}
