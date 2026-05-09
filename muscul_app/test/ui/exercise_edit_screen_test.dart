// GUI tests for ExerciseEditScreen.
//
// Same shape as the template tests: focuses on persistence — the "I edited
// the value, navigated away, came back, and the change was lost" class of
// bugs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscul_app/data/db/database.dart';
import 'package:muscul_app/data/repositories/exercise_repository.dart';
import 'package:muscul_app/domain/models/enums.dart';
import 'package:muscul_app/domain/models/exercise.dart';

import '_harness.dart';
import 'template_edit_screen_test.dart' show pushAndSettle, systemBack;

Future<String> seedCustomExercise(AppDatabase db) async {
  final repo = LocalExerciseRepository(db);
  const id = 'custom-1';
  final ex = Exercise(
    id: id,
    name: 'Mon développé',
    category: ExerciseCategory.push,
    primaryMuscle: MuscleGroup.chest,
    secondaryMuscles: const [MuscleGroup.triceps],
    equipment: Equipment.barbell,
    isCustom: true,
    progressionPriority: ProgressionPriority.repsFirst,
    targetRepRangeMin: 6,
    targetRepRangeMax: 10,
    startingWeightKg: 50,
    defaultIncrementKg: 2.5,
    defaultRestSeconds: 120,
    updatedAt: DateTime(2026, 4, 30),
  );
  await repo.upsert(ex);
  return id;
}

Future<Exercise> readById(AppDatabase db, String id) async {
  final ex = await LocalExerciseRepository(db).getById(id);
  return ex!;
}

/// Finds the TextField bearing the given labelText. More robust than
/// matching the controller value, which depends on whether the load has
/// finished and whether the user has typed anything yet.
Finder fieldByLabel(String label) =>
    find.widgetWithText(TextField, label);

void main() {
  group('ExerciseEditScreen — edit existing custom exercise', () {
    testWidgets(
      'editing rep range + system back auto-saves',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        final id = await seedCustomExercise(h.db);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/$id');

        await tester.enterText(fieldByLabel('Reps min'), '8');
        await tester.enterText(fieldByLabel('Reps max'), '12');
        await tester.pumpAndSettle();

        await systemBack(tester);

        final after = await readById(h.db, id);
        expect(after.targetRepRangeMin, 8);
        expect(after.targetRepRangeMax, 12);
      },
    );

    testWidgets(
      'editing starting weight + check icon persists',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        final id = await seedCustomExercise(h.db);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/$id');

        await tester.enterText(fieldByLabel('Poids départ (kg)'), '60');
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        final after = await readById(h.db, id);
        expect(after.startingWeightKg, 60);
      },
    );

    testWidgets(
      'editing rest seconds + system back persists',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        final id = await seedCustomExercise(h.db);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/$id');

        await tester.enterText(fieldByLabel('Repos par défaut (s)'), '90');
        await tester.pumpAndSettle();

        await systemBack(tester);

        final after = await readById(h.db, id);
        expect(after.defaultRestSeconds, 90);
      },
    );

    testWidgets(
      'toggling progressive overload + back persists',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        final id = await seedCustomExercise(h.db);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/$id');

        // The first Switch on the screen is the "Au poids du corps"
        // toggle, the second is "Surcharge progressive activée".
        await tester.tap(find.byType(Switch).at(1));
        await tester.pumpAndSettle();

        await systemBack(tester);

        final after = await readById(h.db, id);
        expect(after.progressiveOverloadEnabled, isFalse);
      },
    );

    testWidgets(
      'editing notes + system back persists',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        final id = await seedCustomExercise(h.db);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/$id');

        await tester.enterText(fieldByLabel('Notes'), 'Coude rentré');
        await tester.pumpAndSettle();

        await systemBack(tester);

        final after = await readById(h.db, id);
        expect(after.notes, 'Coude rentré');
      },
    );
  });

  group('ExerciseEditScreen — validation', () {
    testWidgets(
      'invalid rep max (≤ min) + check icon shows snackbar, does not pop',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        final id = await seedCustomExercise(h.db);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/$id');

        await tester.enterText(fieldByLabel('Reps max'), '6');
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        expect(
          find.text('Corrige les champs en rouge avant d\'enregistrer'),
          findsOneWidget,
        );
        // Still on the edit screen.
        expect(find.text('Exercice'), findsOneWidget);
      },
    );

    testWidgets(
      'leaving with invalid form shows discard dialog',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        final id = await seedCustomExercise(h.db);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/$id');

        // Make rep max ≤ rep min → form invalid.
        await tester.enterText(fieldByLabel('Reps max'), '5');
        await tester.pumpAndSettle();

        await systemBack(tester);

        expect(find.text('Annuler les modifications ?'), findsOneWidget);

        // Continue editing.
        await tester.tap(find.widgetWithText(TextButton, 'Continuer'));
        await tester.pumpAndSettle();

        // Fix the value.
        await tester.enterText(fieldByLabel('Reps max'), '12');
        await tester.pumpAndSettle();

        await systemBack(tester);

        // Now valid → auto-saves (no dialog this time).
        final after = await readById(h.db, id);
        expect(after.targetRepRangeMax, 12);
      },
    );
  });

  group('ExerciseEditScreen — create new', () {
    testWidgets(
      'creating an exercise with name + check icon persists',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/new');

        await tester.enterText(fieldByLabel('Nom'), 'Mon nouvel exo');
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        final all = await LocalExerciseRepository(h.db).getAll();
        expect(all.any((e) => e.name == 'Mon nouvel exo'), isTrue);
      },
    );

    testWidgets(
      'creating an exercise then system back also persists',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/new');

        await tester.enterText(fieldByLabel('Nom'), 'Auto-saved exo');
        await tester.pumpAndSettle();

        await systemBack(tester);

        final all = await LocalExerciseRepository(h.db).getAll();
        expect(all.any((e) => e.name == 'Auto-saved exo'), isTrue);
      },
    );

    testWidgets(
      'starting fresh and leaving without typing → no exercise created '
      'and no dialog',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        await pumpHarness(tester, h);

        final beforeCount = (await h.db.select(h.db.exercises).get()).length;
        await pushAndSettle(tester, h, '/exercise/new');

        await systemBack(tester);
        // Drain any post-pop animations (e.g. transition).
        await tester.pumpAndSettle();

        final afterCount = (await h.db.select(h.db.exercises).get()).length;
        expect(afterCount, beforeCount);
      },
    );
  });

  group('ExerciseEditScreen — delete', () {
    testWidgets(
      'deleting a custom exercise soft-deletes it',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        final id = await seedCustomExercise(h.db);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/$id');

        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
        await tester.pumpAndSettle();

        final after = await readById(h.db, id);
        expect(after.deletedAt, isNotNull);
      },
    );
  });

  group('ExerciseEditScreen — default (seeded) exercises', () {
    testWidgets(
      'identity-readonly banner shown for default exercise',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        final seeded = (await h.db.select(h.db.exercises).get())
            .firstWhere((e) => !e.isCustom);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/${seeded.id}');

        expect(find.text('Exercice par défaut'), findsOneWidget);
      },
    );

    testWidgets(
      'rest seconds is editable on a default exercise',
      (tester) async {
        final h = await buildHarness();
        addTearDown(h.dispose);
        final seeded = (await h.db.select(h.db.exercises).get())
            .firstWhere((e) => !e.isCustom);
        await pumpHarness(tester, h);
        await pushAndSettle(tester, h, '/exercise/${seeded.id}');

        await tester.enterText(fieldByLabel('Repos par défaut (s)'), '75');
        await tester.pumpAndSettle();
        await systemBack(tester);

        final after = await readById(h.db, seeded.id);
        expect(after.defaultRestSeconds, 75);
      },
    );
  });
}
