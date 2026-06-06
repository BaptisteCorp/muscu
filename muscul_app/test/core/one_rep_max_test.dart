import 'package:flutter_test/flutter_test.dart';
import 'package:reps/core/utils/one_rep_max.dart';

void main() {
  group('estimateOneRepMax (Epley)', () {
    test('returns the weight itself for a single rep', () {
      expect(estimateOneRepMax(100, 1), 100);
    });

    test('applies the Epley formula for multi-rep sets', () {
      // 60 × (1 + 8/30) = 76.0
      expect(estimateOneRepMax(60, 8), closeTo(76.0, 1e-9));
      // 100 × (1 + 5/30) = 116.666...
      expect(estimateOneRepMax(100, 5), closeTo(116.6667, 1e-3));
    });

    test('more reps at the same weight estimates a higher 1RM', () {
      expect(
        estimateOneRepMax(80, 10)! > estimateOneRepMax(80, 5)!,
        isTrue,
      );
    });

    test('returns null when there is no sensible estimate', () {
      expect(estimateOneRepMax(0, 8), isNull); // bodyweight, no added load
      expect(estimateOneRepMax(-20, 8), isNull);
      expect(estimateOneRepMax(60, 0), isNull);
    });
  });
}
