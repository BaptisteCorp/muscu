// Widget-test harness for the app's screens.
//
// Spins up an in-memory Drift DB seeded with the default exercises, wires
// the relevant Riverpod providers, and pumps the screen under a real
// GoRouter so `context.pop()` works exactly as in production.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:muscul_app/core/providers.dart';
import 'package:muscul_app/data/db/database.dart';
import 'package:muscul_app/ui/library/exercises/exercise_edit_screen.dart';
import 'package:muscul_app/ui/library/templates/template_edit_screen.dart';

class TestHarness {
  TestHarness._(this.db, this.router, this.widget);

  final AppDatabase db;
  final GoRouter router;
  final Widget widget;

  Future<void> dispose() async {
    await db.close();
  }
}

/// Builds a minimal app with a real GoRouter so screens can call
/// `context.pop()`. Routes:
///   - `/`            : a home stub with a button to navigate elsewhere
///   - `/template/new`: TemplateEditScreen()
///   - `/template/:id`: TemplateEditScreen(templateId)
///   - `/exercise/new`: ExerciseEditScreen()
///   - `/exercise/:id`: ExerciseEditScreen(exerciseId)
Future<TestHarness> buildHarness({
  String initialLocation = '/',
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  // Touch the DB so onCreate runs (seeds 28+ default exercises).
  await db.select(db.exercises).get();

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const _HomeStub(),
      ),
      GoRoute(
        path: '/template/new',
        builder: (_, __) => const TemplateEditScreen(),
      ),
      GoRoute(
        path: '/template/:id',
        builder: (_, s) =>
            TemplateEditScreen(templateId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/exercise/new',
        builder: (_, __) => const ExerciseEditScreen(),
      ),
      GoRoute(
        path: '/exercise/:id',
        builder: (_, s) =>
            ExerciseEditScreen(exerciseId: s.pathParameters['id']),
      ),
    ],
  );

  final widget = ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      // Avoid scrollbar overlay drama in tests.
      debugShowCheckedModeBanner: false,
    ),
  );

  return TestHarness._(db, router, widget);
}

class _HomeStub extends StatelessWidget {
  const _HomeStub();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('test-home')));
  }
}

/// Convenience: pump the harness widget and let async Riverpod
/// streams settle.
///
/// Sets a tall test viewport so long ListView-based forms (the edit
/// screens) mount every child eagerly. Otherwise SliverChildListDelegate
/// lazy-builds and TextFields below the fold are not in the element tree.
Future<void> pumpHarness(WidgetTester tester, TestHarness h) async {
  await tester.binding.setSurfaceSize(const Size(800, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(h.widget);
  await tester.pumpAndSettle();
}
