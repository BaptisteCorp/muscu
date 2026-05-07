import '../models/enums.dart';
import '../models/exercise.dart';
import '../models/progression_target.dart';
import '../models/session.dart';
import '../models/user_settings.dart';
import 'strategies/double_progression.dart';
import 'strategies/rpe_autoregulated.dart';

/// Pure progression engine. No I/O — easy to unit-test.
///
/// [history] is most-recent first. Each [SessionExerciseWithSets] is one past
/// occurrence of the exercise across the user's history (limit imposed by the
/// caller, e.g. 30 last sessions).
class ProgressionEngine {
  static const _double = DoubleProgressionStrategy();
  static const _rpe = RpeAutoregulatedStrategy();

  static ProgressionTarget computeNextTarget({
    required Exercise exercise,
    required int plannedSets,
    required List<SessionExerciseWithSets> history,
    required UserSettings settings,
  }) {
    return switch (exercise.progressionStrategy) {
      ProgressionStrategyKind.doubleProgression => _double.compute(
          exercise: exercise,
          plannedSets: plannedSets,
          history: history,
          settings: settings,
        ),
      ProgressionStrategyKind.rpeAutoregulated => _rpe.compute(
          exercise: exercise,
          plannedSets: plannedSets,
          history: history,
          settings: settings,
        ),
    };
  }
}
