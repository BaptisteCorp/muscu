import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/session.dart';

/// Onglet "Exos" : sélection d'un exercice + courbes (force, volume, top set)
/// + historique condensé.
class ExerciseProgressionTab extends ConsumerStatefulWidget {
  const ExerciseProgressionTab({super.key});

  @override
  ConsumerState<ExerciseProgressionTab> createState() =>
      _ExerciseProgressionTabState();
}

class _ExerciseProgressionTabState
    extends ConsumerState<ExerciseProgressionTab> {
  Exercise? _selected;
  bool _trainedOnly = true;

  @override
  Widget build(BuildContext context) {
    final asyncExercises = ref.watch(allExercisesProvider);
    final asyncTrained = ref.watch(trainedExerciseIdsProvider);

    return asyncExercises.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) {
          final trainedIds = asyncTrained.valueOrNull ?? const <String>[];
          final byId = {for (final e in list) e.id: e};
          final trainedExercises = [
            for (final id in trainedIds)
              if (byId[id] != null) byId[id]!,
          ];
          final restExercises = [
            for (final e in list)
              if (!trainedIds.contains(e.id)) e,
          ];
          final ordered = _trainedOnly && trainedExercises.isNotEmpty
              ? trainedExercises
              : [...trainedExercises, ...restExercises];

          final selected = _selected ??
              (trainedExercises.isNotEmpty
                  ? trainedExercises.first
                  : (list.isNotEmpty ? list.first : null));

          if (list.isEmpty) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text("Aucun exercice dans le catalogue."),
            ));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (trainedExercises.isEmpty)
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Aucune série validée pour le moment.\n\n'
                      "Lors d'une séance, appuyez sur VALIDER pour enregistrer chaque série. "
                      "Les séries simplement passées (skip) ne sont pas enregistrées et n'apparaîtront pas ici.",
                    ),
                  ),
                ),
              if (trainedExercises.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${trainedExercises.length} exo'
                        '${trainedExercises.length > 1 ? 's' : ''} entraîné'
                        '${trainedExercises.length > 1 ? 's' : ''}'),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Entraînés uniquement'),
                        Switch(
                          value: _trainedOnly,
                          onChanged: (v) => setState(() => _trainedOnly = v),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (selected != null)
                _ExercisePicker(
                  selected: selected,
                  exercises: ordered,
                  trainedIds: trainedIds.toSet(),
                  onChanged: (ex) => setState(() => _selected = ex),
                ),
              const SizedBox(height: 16),
              if (selected != null)
                _ExerciseProgressionView(exercise: selected),
            ],
          );
        });
  }
}

class _ExercisePicker extends StatelessWidget {
  final Exercise selected;
  final List<Exercise> exercises;
  final Set<String> trainedIds;
  final ValueChanged<Exercise> onChanged;
  const _ExercisePicker({
    required this.selected,
    required this.exercises,
    required this.trainedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final value =
        exercises.any((e) => e.id == selected.id) ? selected.id : null;
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Exercice',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final e in exercises)
          DropdownMenuItem(
            value: e.id,
            child: Row(
              children: [
                if (trainedIds.contains(e.id))
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.check_circle,
                        size: 16, color: Colors.green),
                  ),
                Expanded(
                  child: Text(e.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (id) {
        final ex = exercises.firstWhere((e) => e.id == id);
        onChanged(ex);
      },
    );
  }
}

class _ExerciseProgressionView extends ConsumerWidget {
  final Exercise exercise;
  const _ExerciseProgressionView({required this.exercise});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncHistory = ref.watch(exerciseHistoryProvider(exercise.id));

    return asyncHistory.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Erreur: $e'),
      data: (history) {
        final hasAnyValidatedSet =
            history.any((s) => s.sets.any((set) => !set.isWarmup));
        if (!hasAnyValidatedSet) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const Icon(Icons.info_outline, size: 32),
                const SizedBox(height: 8),
                Text(
                  history.isEmpty
                      ? 'Aucun historique pour cet exercice.'
                      : 'Cet exercice apparaît dans ${history.length} séance'
                          '${history.length > 1 ? 's' : ''}, '
                          'mais aucune série n\'a été validée.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Appuyez sur VALIDER pendant la séance pour enregistrer une série.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }
        final chrono = history.reversed.toList();

        final perSession = <_ExoSessionStats>[];
        for (var i = 0; i < chrono.length; i++) {
          final s = chrono[i];
          final working = s.sets.where((set) => !set.isWarmup).toList();
          if (working.isEmpty) continue;
          final heaviest =
              working.reduce((a, b) => a.weightKg >= b.weightKg ? a : b);
          final volume = working.fold<double>(
              0, (acc, set) => acc + set.reps * set.weightKg);
          final dt = s.sets.first.completedAt;
          perSession.add(_ExoSessionStats(
            index: i,
            date: dt,
            sets: working.length,
            volume: volume,
            heaviestWeight: heaviest.weightKg,
            heaviestWeightReps: heaviest.reps,
            avgLoad:
                volume / working.fold<int>(0, (acc, set) => acc + set.reps),
          ));
        }

        final prs = _detailedPRs(history);
        final cs = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Records perso',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PrCard(
                    label: 'Meilleur poids',
                    value: '${fmtKg(prs.bestWeight)} kg',
                    sub: prs.bestWeightReps > 0
                        ? '× ${prs.bestWeightReps} reps'
                            '${prs.bestWeightDate == null ? '' : ' • ${fmtDate(prs.bestWeightDate!)}'}'
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _PrCard(
                    label: 'Top reps',
                    value: '${prs.bestRepsCount} reps',
                    sub: prs.bestRepsCount > 0
                        ? '@ ${fmtKg(prs.bestRepsWeight)} kg'
                            '${prs.bestRepsDate == null ? '' : ' • ${fmtDate(prs.bestRepsDate!)}'}'
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _PrCard(
                    label: 'Volume max',
                    value: '${prs.volume.toStringAsFixed(0)} kg',
                    sub: prs.volumeDate == null
                        ? null
                        : 'le ${fmtDate(prs.volumeDate!)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Force : poids le plus lourd par séance',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: perSession.length < 2
                  ? const Center(child: Text('Au moins 2 séances nécessaires'))
                  : LineChart(
                      LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (final p in perSession)
                                FlSpot(p.index.toDouble(), p.heaviestWeight),
                            ],
                            isCurved: true,
                            preventCurveOverShooting: true,
                            barWidth: 3,
                            color: cs.primary,
                            dotData: FlDotData(
                              show: perSession.length <= 30,
                              getDotPainter: (s, _, __, ___) =>
                                  FlDotCirclePainter(
                                radius: 3,
                                color: cs.primary,
                                strokeWidth: 0,
                              ),
                            ),
                          ),
                        ],
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(),
                          topTitles: AxisTitles(),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                            ),
                          ),
                        ),
                        gridData: const FlGridData(
                          drawVerticalLine: false,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            Text('Volume par séance',
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Σ(reps × kg) sur les séries non-échauffement.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: perSession.isEmpty
                  ? const Center(child: Text('—'))
                  : BarChart(
                      BarChartData(
                        barGroups: [
                          for (final p in perSession)
                            BarChartGroupData(
                              x: p.index,
                              barRods: [
                                BarChartRodData(
                                  toY: p.volume,
                                  color: cs.primary,
                                  width: 10,
                                ),
                              ],
                            ),
                        ],
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(),
                          topTitles: AxisTitles(),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        gridData: const FlGridData(
                          drawVerticalLine: false,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            Text('Top set par séance',
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              "La meilleure série de chaque séance : poids × reps.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: perSession.length < 2
                  ? const Center(child: Text('—'))
                  : LineChart(
                      LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (final p in perSession)
                                FlSpot(p.index.toDouble(),
                                    p.heaviestWeightReps.toDouble()),
                            ],
                            isCurved: true,
                            preventCurveOverShooting: true,
                            barWidth: 3,
                            color: cs.tertiary,
                            dotData: FlDotData(
                              show: perSession.length <= 30,
                              getDotPainter: (s, _, __, ___) =>
                                  FlDotCirclePainter(
                                radius: 3,
                                color: cs.tertiary,
                                strokeWidth: 0,
                              ),
                            ),
                          ),
                        ],
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(),
                          topTitles: AxisTitles(),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            Text('Historique', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final p in perSession.reversed.take(20)) _ExoSessionRow(p),
          ],
        );
      },
    );
  }
}

class _PrCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  const _PrCard({required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 200,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
          border: Border.all(color: cs.outlineVariant),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 12,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: -0.3,
              ),
            ),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExoSessionStats {
  final int index;
  final DateTime date;
  final int sets;
  final double volume;
  final double heaviestWeight;
  final int heaviestWeightReps;
  final double avgLoad;
  const _ExoSessionStats({
    required this.index,
    required this.date,
    required this.sets,
    required this.volume,
    required this.heaviestWeight,
    required this.heaviestWeightReps,
    required this.avgLoad,
  });
}

class _ExoSessionRow extends StatelessWidget {
  final _ExoSessionStats stats;
  const _ExoSessionRow(this.stats);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        '${stats.heaviestWeightReps} × ${fmtKg(stats.heaviestWeight)} kg '
        '(top set)',
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
      subtitle: Text(
        '${fmtDate(stats.date)} • ${stats.sets} séries • '
        'volume ${stats.volume.toStringAsFixed(0)} kg',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _Pr {
  final double volume;
  final DateTime? volumeDate;
  final int bestWeightReps;
  final double bestWeight;
  final DateTime? bestWeightDate;
  final int bestRepsCount;
  final double bestRepsWeight;
  final DateTime? bestRepsDate;
  _Pr({
    required this.volume,
    required this.volumeDate,
    required this.bestWeightReps,
    required this.bestWeight,
    required this.bestWeightDate,
    required this.bestRepsCount,
    required this.bestRepsWeight,
    required this.bestRepsDate,
  });
}

_Pr _detailedPRs(List<SessionExerciseWithSets> history) {
  double bestV = 0;
  DateTime? bestVDate;
  int bestWReps = 0;
  double bestW = 0;
  DateTime? bestWDate;
  int bestReps = 0;
  double bestRepsW = 0;
  DateTime? bestRepsDate;
  for (final s in history) {
    final working = s.sets.where((set) => !set.isWarmup).toList();
    if (working.isEmpty) continue;
    final dt = working.first.completedAt;
    final volume =
        working.fold<double>(0, (acc, s) => acc + s.reps * s.weightKg);
    if (volume > bestV) {
      bestV = volume;
      bestVDate = dt;
    }
    for (final set in working) {
      if (set.weightKg > bestW) {
        bestW = set.weightKg;
        bestWReps = set.reps;
        bestWDate = set.completedAt;
      }
      if (set.reps > bestReps) {
        bestReps = set.reps;
        bestRepsW = set.weightKg;
        bestRepsDate = set.completedAt;
      }
    }
  }
  return _Pr(
    volume: bestV,
    volumeDate: bestVDate,
    bestWeight: bestW,
    bestWeightReps: bestWReps,
    bestWeightDate: bestWDate,
    bestRepsCount: bestReps,
    bestRepsWeight: bestRepsW,
    bestRepsDate: bestRepsDate,
  );
}
