import '../../domain/models/progression_target.dart';
import '../../domain/models/session.dart';
import '../../domain/models/workout_template.dart';
import 'pending_set.dart';

/// Calcule les valeurs par défaut (reps/poids) pré-remplies pour la série à la
/// position [pos] d'un exercice en cours de séance.
///
/// Fonction pure (sans I/O ni état widget) pour être testable et garantir que
/// la prescription du moteur de surcharge progressive l'emporte sur un plan
/// figé. Priorité :
///   1. une série déjà validée dans CETTE séance → on reprend ses reps/poids
///      (l'utilisateur n'a qu'à saisir une fois s'il dévie du plan) ;
///   2. s'il y a un historique d'entraînement → c'est le [target] du moteur
///      qui prescrit. Indispensable : le template ratché reste figé sur ce qui
///      a été fait (ex. 3×12@45) et ne sait pas exprimer le reset de reps +
///      montée de charge (3×12@45 réussi → 3×8@47.5). On suit donc le moteur ;
///   3. sinon (toute première séance, aucun historique) → on amorce depuis le
///      template s'il existe (reps/poids de départ voulus) ;
///   4. sinon (freestyle) → le [target].
PendingSet computeSetDefault({
  required int pos,
  required List<SetEntry> sessionSets,
  required bool hasHistory,
  required List<TemplateExerciseSet> plan,
  required ProgressionTarget target,
}) {
  final validatedThisSession =
      sessionSets.where((s) => !s.isWarmup).toList(growable: false);
  if (validatedThisSession.isNotEmpty) {
    final last = validatedThisSession.last;
    return PendingSet(reps: last.reps, weight: last.weightKg, rpe: null);
  }
  if (hasHistory) {
    return PendingSet(
      reps: target.targetReps,
      weight: target.targetWeightKg,
      rpe: null,
    );
  }
  if (plan.isNotEmpty) {
    final planSet = pos < plan.length ? plan[pos] : plan.last;
    return PendingSet(
      reps: planSet.plannedReps,
      weight: planSet.plannedWeightKg ?? target.targetWeightKg,
      rpe: null,
    );
  }
  return PendingSet(
    reps: target.targetReps,
    weight: target.targetWeightKg,
    rpe: null,
  );
}
