// Sanity check: the test harness boots and the in-memory DB has seeded
// exercises. If this test breaks, every other UI test will also break,
// and you should look here first.

import 'package:flutter_test/flutter_test.dart';

import '_harness.dart';

void main() {
  testWidgets('harness boots to home stub', (tester) async {
    final h = await buildHarness();
    addTearDown(h.dispose);
    await pumpHarness(tester, h);
    expect(find.text('test-home'), findsOneWidget);
  });

  testWidgets('harness DB seeds default exercises', (tester) async {
    final h = await buildHarness();
    addTearDown(h.dispose);
    final rows = await h.db.select(h.db.exercises).get();
    expect(rows.length, greaterThanOrEqualTo(28));
  });
}
