import 'package:flutter_test/flutter_test.dart';
import 'package:reps/domain/models/enums.dart';

void main() {
  group('Equipment', () {
    test('rope equipment exists and is labelled "Corde"', () {
      expect(Equipment.values.contains(Equipment.rope), isTrue);
      expect(Equipment.rope.label, 'Corde');
    });

    test('every equipment has a non-empty, distinct label', () {
      final labels = Equipment.values.map((e) => e.label).toList();
      expect(labels.every((l) => l.isNotEmpty), isTrue);
      expect(labels.toSet().length, labels.length);
    });

    test('rope name round-trips through enumByName', () {
      final parsed = enumByName(Equipment.values, 'rope',
          fallback: Equipment.other);
      expect(parsed, Equipment.rope);
    });
  });
}
