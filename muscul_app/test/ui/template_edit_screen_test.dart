// GUI tests for TemplateEditScreen.
//
// Focus of this file: regression coverage for the bug where edits to a
// template (e.g. weight) were not persisted when the user navigated away
// without explicitly tapping the top-bar check icon. We also test the
// happy paths so the auto-save fix doesn't accidentally double-save or
// drop fields.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscul_app/data/db/database.dart';
import 'package:muscul_app/data/repositories/template_repository.dart';
import 'package:muscul_app/domain/models/workout_template.dart';

import '_harness.dart';

/// Seeds a template `T1` named "Push A" with the *first seeded* exercise,
/// 3 sets x 8 reps @ 60kg, rest 90s. Returns the generated IDs.
Future<({String templateId, String teId, String exerciseId})> seedTemplate(
    AppDatabase db, {
  String name = 'Push A',
  double weightKg = 60,
  int reps = 8,
  int sets = 3,
  int rest = 90,
}) async {
  final exercises = await db.select(db.exercises).get();
  final exercise = exercises.first;
  final repo = LocalTemplateRepository(db);

  const templateId = 'tpl-1';
  const teId = 'te-1';
  final now = DateTime.now();

  await repo.upsertTemplate(WorkoutTemplate(
    id: templateId,
    name: name,
    createdAt: now,
    updatedAt: now,
  ));
  await repo.setTemplateExercises(templateId, [
    TemplateExerciseWithSets(
      exercise: WorkoutTemplateExercise(
        id: teId,
        templateId: templateId,
        exerciseId: exercise.id,
        orderIndex: 0,
        targetSets: sets,
        restSeconds: rest,
      ),
      sets: [
        for (var i = 0; i < sets; i++)
          TemplateExerciseSet(
            id: 'set-$i',
            templateExerciseId: teId,
            setIndex: i,
            plannedReps: reps,
            plannedWeightKg: weightKg,
          ),
      ],
    ),
  ]);
  return (templateId: templateId, teId: teId, exerciseId: exercise.id);
}

/// Pumps the harness then pushes the given location so back navigation
/// has somewhere to pop to.
///
/// The edit screens display a CircularProgressIndicator while loading,
/// whose ticker schedules frames forever — `pumpAndSettle` would time
/// out. We pump in steps until the indicator is gone, then settle.
Future<void> pushAndSettle(
    WidgetTester tester, TestHarness h, String location) async {
  h.router.push(location);
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}

/// Simulates the Android system back gesture. Goes through
/// Navigator.maybePop, which is the only path that triggers PopScope.
/// `router.pop()` and `Navigator.pop()` both bypass PopScope.
Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Reads back the (only) template's first set weight from the DB.
Future<double?> readFirstWeight(AppDatabase db, String templateId) async {
  final repo = LocalTemplateRepository(db);
  final detail = await repo.getWithExercises(templateId);
  return detail?.exercises.first.sets.first.plannedWeightKg;
}

Future<int?> readFirstReps(AppDatabase db, String templateId) async {
  final repo = LocalTemplateRepository(db);
  final detail = await repo.getWithExercises(templateId);
  return detail?.exercises.first.sets.first.plannedReps;
}

Future<int> readExerciseCount(AppDatabase db, String templateId) async {
  final repo = LocalTemplateRepository(db);
  final detail = await repo.getWithExercises(templateId);
  return detail?.exercises.length ?? 0;
}

/// Opens the plan-editor sheet for the (single) exercise in the loaded
/// template. Tap-target: the pencil edit icon trailing the tile.
Future<void> openPlanEditor(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Modifier le plan'));
  await tester.pumpAndSettle();
}

/// Locates the weight TextField for a given set row inside the open plan
/// editor sheet. The editor lays out rows as "Série N | reps | kg".
Finder weightFieldForRow(int rowIndex) {
  // Each `_PlanSetRow` has two TextFields; the second is the kg field.
  // We address them by ancestry on the labelText "kg".
  return find
      .ancestor(
        of: find.text('kg'),
        matching: find.byType(TextField),
      )
      .at(rowIndex);
}

void main() {
  group('TemplateEditScreen — edit existing template', () {
    testWidgets(
      'editing weight + tapping top-bar check icon persists',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        final ids = await seedTemplate(h.db);
        await pumpHarness(tester, h);

        await pushAndSettle(tester, h, '/template/${ids.templateId}');

        await openPlanEditor(tester);

        // Find kg fields (3 sets → 3 kg fields under the "same for all"
        // toggle, only the first is editable).
        final kgField = find
            .widgetWithText(TextField, '60')
            .first;
        expect(kgField, findsOneWidget);
        await tester.enterText(kgField, '72.5');
        await tester.pumpAndSettle();

        // Confirm the sheet ("Enregistrer") closes the bottom sheet.
        await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
        await tester.pumpAndSettle();

        // Tap the top-bar check icon → persists to DB.
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        expect(await readFirstWeight(h.db, ids.templateId), 72.5);
      },
    );

    // The bug the user reported: edits made through the bottom sheet are
    // discarded when the user backs out of the screen instead of tapping
    // the top-bar check icon.
    testWidgets(
      'editing weight + system back persists (auto-save on pop)',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        final ids = await seedTemplate(h.db);
        await pumpHarness(tester, h);

        await pushAndSettle(tester, h, '/template/${ids.templateId}');

        await openPlanEditor(tester);
        await tester.enterText(
            find.widgetWithText(TextField, '60').first, '85');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
        await tester.pumpAndSettle();

        // Simulate Android system back. PopScope intercepts; the screen
        // should auto-save before popping.
        await systemBack(tester);

        expect(await readFirstWeight(h.db, ids.templateId), 85);
      },
    );

    testWidgets(
      'editing reps + system back persists',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        final ids = await seedTemplate(h.db);
        await pumpHarness(tester, h);

        await pushAndSettle(tester, h, '/template/${ids.templateId}');

        await openPlanEditor(tester);
        // The first reps field shows "8" (default).
        await tester.enterText(
            find.widgetWithText(TextField, '8').first, '12');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
        await tester.pumpAndSettle();

        await systemBack(tester);

        expect(await readFirstReps(h.db, ids.templateId), 12);
      },
    );

    testWidgets(
      'renaming template + system back persists',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        final ids = await seedTemplate(h.db, name: 'Push A');
        await pumpHarness(tester, h);

        await pushAndSettle(tester, h, '/template/${ids.templateId}');

        await tester.enterText(
            find.widgetWithText(TextField, 'Push A'), 'Push B');
        await tester.pumpAndSettle();

        await systemBack(tester);

        final repo = LocalTemplateRepository(h.db);
        final t = await repo.getWithExercises(ids.templateId);
        expect(t?.template.name, 'Push B');
      },
    );

    testWidgets(
      'discarding edits via the cancel button does NOT persist',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        final ids = await seedTemplate(h.db);
        await pumpHarness(tester, h);

        await pushAndSettle(tester, h, '/template/${ids.templateId}');

        await openPlanEditor(tester);
        await tester.enterText(
            find.widgetWithText(TextField, '60').first, '99');
        await tester.pumpAndSettle();

        // Tap the bottom-sheet "Annuler" button — local state should NOT
        // be updated, so even auto-save on pop won't persist.
        await tester.tap(find.widgetWithText(OutlinedButton, 'Annuler'));
        await tester.pumpAndSettle();

        await systemBack(tester);

        expect(await readFirstWeight(h.db, ids.templateId), 60);
      },
    );

    testWidgets(
      'navigating back without any change does not bump updatedAt',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        final ids = await seedTemplate(h.db);
        final beforeUpdatedAt =
            (await LocalTemplateRepository(h.db)
                    .getWithExercises(ids.templateId))!
                .template
                .updatedAt;
        await pumpHarness(tester, h);

        await pushAndSettle(tester, h, '/template/${ids.templateId}');

        await systemBack(tester);

        final after = (await LocalTemplateRepository(h.db)
                .getWithExercises(ids.templateId))!
            .template
            .updatedAt;
        expect(after, beforeUpdatedAt);
      },
    );

    testWidgets(
      'deleting an exercise + back persists the smaller list',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        final ids = await seedTemplate(h.db);

        // Add a second exercise so we can delete one without hitting the
        // "no exercise" validation path.
        final exercises = await h.db.select(h.db.exercises).get();
        await LocalTemplateRepository(h.db).setTemplateExercises(
          ids.templateId,
          [
            TemplateExerciseWithSets(
              exercise: WorkoutTemplateExercise(
                id: 'te-1',
                templateId: ids.templateId,
                exerciseId: exercises[0].id,
                orderIndex: 0,
                targetSets: 3,
              ),
              sets: [
                TemplateExerciseSet(
                  id: 's-a-0',
                  templateExerciseId: 'te-1',
                  setIndex: 0,
                  plannedReps: 8,
                  plannedWeightKg: 60,
                ),
              ],
            ),
            TemplateExerciseWithSets(
              exercise: WorkoutTemplateExercise(
                id: 'te-2',
                templateId: ids.templateId,
                exerciseId: exercises[1].id,
                orderIndex: 1,
                targetSets: 3,
              ),
              sets: [
                TemplateExerciseSet(
                  id: 's-b-0',
                  templateExerciseId: 'te-2',
                  setIndex: 0,
                  plannedReps: 10,
                  plannedWeightKg: 30,
                ),
              ],
            ),
          ],
        );

        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/template/${ids.templateId}');

        // Tap the first row's delete icon (the trash icon next to the
        // first exercise tile, NOT the AppBar template-level delete).
        final rowDeletes = find.descendant(
          of: find.byType(Card),
          matching: find.byIcon(Icons.delete_outline),
        );
        expect(rowDeletes, findsNWidgets(2));
        await tester.tap(rowDeletes.first);
        await tester.pumpAndSettle();

        await systemBack(tester);

        expect(await readExerciseCount(h.db, ids.templateId), 1);
      },
    );
  });

  group('TemplateEditScreen — validation', () {
    testWidgets(
      'tapping check icon with empty name shows error & does NOT pop',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/template/new');

        // No name, no exercise. Tap the check icon.
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        expect(find.text('Donne un nom au template'), findsOneWidget);
        // Still on the editor screen (Scaffold + AppBar title still
        // visible).
        expect(find.text('Nouveau template'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping check with name but no exercise shows error',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/template/new');

        await tester.enterText(
            find.widgetWithText(TextField, 'Nom (ex: Push A)'), 'My push');
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        expect(find.text('Ajoute au moins un exercice'), findsOneWidget);
      },
    );

    testWidgets(
      'discard dialog shown when leaving an unsavable in-progress template',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/template/new');

        // Type a name but don't add any exercise → form invalid.
        await tester.enterText(
            find.widgetWithText(TextField, 'Nom (ex: Push A)'), 'Anything');
        await tester.pumpAndSettle();

        await systemBack(tester);

        // Discard dialog should appear.
        expect(find.text('Annuler les modifications ?'), findsOneWidget);

        // Tap "Continuer" — stays on the screen.
        await tester.tap(find.widgetWithText(TextButton, 'Continuer'));
        await tester.pumpAndSettle();
        expect(find.text('Nouveau template'), findsOneWidget);

        // Try again, this time confirm "Abandonner".
        await systemBack(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
        await tester.pumpAndSettle();

        // Now we should be back on the home stub.
        expect(find.text('test-home'), findsOneWidget);

        // And no template should have been created.
        final all = await h.db.select(h.db.workoutTemplates).get();
        expect(all.where((t) => t.deletedAt == null), isEmpty);
      },
    );
  });

  group('TemplateEditScreen — delete the template', () {
    testWidgets(
      'AppBar delete soft-deletes and pops',
      (tester) async {
        final h = await buildHarness(initialLocation: '/');
        addTearDown(h.dispose);
        final ids = await seedTemplate(h.db);
        await pumpHarness(tester, h);

        await pushAndSettle(tester, h, '/template/${ids.templateId}');

        // The AppBar's delete (vs each row's trash icon).
        await tester.tap(find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.delete_outline),
        ));
        await tester.pumpAndSettle();

        // Confirm dialog.
        await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
        await tester.pumpAndSettle();

        final repo = LocalTemplateRepository(h.db);
        final detail = await repo.getWithExercises(ids.templateId);
        expect(detail?.template.deletedAt, isNotNull);

        // Popped back home.
        expect(find.text('test-home'), findsOneWidget);
      },
    );
  });
}
