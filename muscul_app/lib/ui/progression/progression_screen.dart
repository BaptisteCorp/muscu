import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/session_repository.dart';
import '../../domain/models/bodyweight_entry.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/session.dart';
import '../../domain/progression/e1rm.dart';

class ProgressionScreen extends ConsumerStatefulWidget {
  const ProgressionScreen({super.key});
  @override
  ConsumerState<ProgressionScreen> createState() => _ProgressionScreenState();
}

class _ProgressionScreenState extends ConsumerState<ProgressionScreen> {
  Exercise? _selected;
  bool _trainedOnly = true;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Progression'),
          bottom: const TabBar(
            tabAlignment: TabAlignment.fill,
            labelPadding: EdgeInsets.symmetric(horizontal: 4),
            labelStyle: TextStyle(fontSize: 13),
            tabs: [
              Tab(text: 'Exos'),
              Tab(text: 'Séances'),
              Tab(text: 'Volume'),
              Tab(text: 'Poids'),
            ],
          ),
        ),
        body: TabBarView(children: [
          _buildExercisesTab(),
          const _SessionsProgressionTab(),
          const _VolumeProgressionTab(),
          const _BodyweightTab(),
        ]),
      ),
    );
  }

  Widget _buildExercisesTab() {
    final asyncExercises = ref.watch(allExercisesProvider);
    final asyncTrained = ref.watch(trainedExerciseIdsProvider);

    return asyncExercises.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) {
          final trainedIds = asyncTrained.valueOrNull ?? const <String>[];
          // Reorder: trained ones first (in recency order), the rest after.
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

          // Pick a sensible default: prefer a trained exercise if one exists.
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
                          onChanged: (v) =>
                              setState(() => _trainedOnly = v),
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
  const _ExercisePicker(
      {required this.selected,
      required this.exercises,
      required this.trainedIds,
      required this.onChanged});
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
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }
        // history is most-recent first; reverse for chronological chart.
        final chrono = history.reversed.toList();

        // Per-session summary metrics, in chronological order.
        final perSession = <_ExoSessionStats>[];
        for (var i = 0; i < chrono.length; i++) {
          final s = chrono[i];
          final working = s.sets.where((set) => !set.isWarmup).toList();
          if (working.isEmpty) continue;
          final bestE1rm = working
              .map((set) => estimate1RM(
                  weightKg: set.weightKg, reps: set.reps, rpe: set.rpe))
              .reduce((a, b) => a > b ? a : b);
          final heaviest = working
              .reduce((a, b) => a.weightKg >= b.weightKg ? a : b);
          final volume = working.fold<double>(
              0, (acc, set) => acc + set.reps * set.weightKg);
          final dt = s.sets.first.completedAt;
          perSession.add(_ExoSessionStats(
            index: i,
            date: dt,
            sets: working.length,
            volume: volume,
            bestE1rm: bestE1rm,
            heaviestWeight: heaviest.weightKg,
            heaviestWeightReps: heaviest.reps,
            avgLoad: volume /
                working.fold<int>(0, (acc, set) => acc + set.reps),
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
                    label: '1RM estimé',
                    value: '${prs.e1rm.toStringAsFixed(1)} kg',
                    sub: prs.e1rmDate == null
                        ? null
                        : 'le ${_dateOnly(prs.e1rmDate!)}',
                  ),
                  const SizedBox(width: 8),
                  _PrCard(
                    label: 'Meilleur poids',
                    value: '${_fmtN(prs.bestWeight)} kg',
                    sub: prs.bestWeightReps > 0
                        ? '× ${prs.bestWeightReps} reps'
                            '${prs.bestWeightDate == null ? '' : ' • ${_dateOnly(prs.bestWeightDate!)}'}'
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _PrCard(
                    label: 'Top reps',
                    value: '${prs.bestRepsCount} reps',
                    sub: prs.bestRepsCount > 0
                        ? '@ ${_fmtN(prs.bestRepsWeight)} kg'
                            '${prs.bestRepsDate == null ? '' : ' • ${_dateOnly(prs.bestRepsDate!)}'}'
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _PrCard(
                    label: 'Volume max',
                    value: '${prs.volume.toStringAsFixed(0)} kg',
                    sub: prs.volumeDate == null
                        ? null
                        : 'le ${_dateOnly(prs.volumeDate!)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Force : 1RM estimé + meilleur poids',
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Vif = e1RM (intensité réelle), pâle = poids le plus lourd '
              'utilisé dans la séance.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: perSession.length < 2
                  ? const Center(
                      child: Text('Au moins 2 séances nécessaires'))
                  : LineChart(
                      LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (final p in perSession)
                                FlSpot(p.index.toDouble(),
                                    p.heaviestWeight),
                            ],
                            isCurved: true,
                            preventCurveOverShooting: true,
                            barWidth: 2,
                            color: cs.outlineVariant,
                            dotData: const FlDotData(show: false),
                          ),
                          LineChartBarData(
                            spots: [
                              for (final p in perSession)
                                FlSpot(p.index.toDouble(), p.bestE1rm),
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
            for (final p in perSession.reversed.take(20))
              _ExoSessionRow(p),
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
  final double bestE1rm;
  final double heaviestWeight;
  final int heaviestWeightReps;
  final double avgLoad;
  const _ExoSessionStats({
    required this.index,
    required this.date,
    required this.sets,
    required this.volume,
    required this.bestE1rm,
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
        '${stats.heaviestWeightReps} × ${_fmtN(stats.heaviestWeight)} kg '
        '(top set)',
        style: const TextStyle(
            fontFeatures: [FontFeature.tabularFigures()]),
      ),
      subtitle: Text(
        '${_dateOnly(stats.date)} • ${stats.sets} séries • '
        'volume ${stats.volume.toStringAsFixed(0)} kg • '
        'e1RM ${stats.bestE1rm.toStringAsFixed(1)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _Pr {
  final double e1rm;
  final DateTime? e1rmDate;
  final double volume;
  final DateTime? volumeDate;
  final int bestWeightReps;
  final double bestWeight;
  final DateTime? bestWeightDate;
  final int bestRepsCount;
  final double bestRepsWeight;
  final DateTime? bestRepsDate;
  _Pr({
    required this.e1rm,
    required this.e1rmDate,
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
  double bestE = 0;
  DateTime? bestEDate;
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
      final e =
          estimate1RM(weightKg: set.weightKg, reps: set.reps, rpe: set.rpe);
      if (e > bestE) {
        bestE = e;
        bestEDate = set.completedAt;
      }
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
    e1rm: bestE,
    e1rmDate: bestEDate,
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

String _fmtN(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

class _SessionsProgressionTab extends ConsumerWidget {
  const _SessionsProgressionTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTemplates = ref.watch(allTemplatesProvider);
    final asyncHistory = ref.watch(sessionHistoryProvider);

    return asyncTemplates.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (templates) => asyncHistory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (history) {
          final ended = history.where((s) => s.endedAt != null).toList();
          if (ended.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Aucune séance terminée pour le moment.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Group sessions by templateId (null = freestyle)
          final byTemplate = <String?, List<WorkoutSession>>{};
          for (final s in ended) {
            byTemplate.putIfAbsent(s.templateId, () => []).add(s);
          }
          // Build ordered template stats: known templates first (alpha), then freestyle.
          final sortedTemplates = [...templates]
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          final stats = <_TemplateStats>[];
          for (final t in sortedTemplates) {
            final list = byTemplate[t.id] ?? const [];
            stats.add(_TemplateStats(
              templateName: t.name,
              templateId: t.id,
              sessions: list,
            ));
          }
          if (byTemplate.containsKey(null)) {
            stats.add(_TemplateStats(
              templateName: 'Séances freestyle',
              templateId: null,
              sessions: byTemplate[null]!,
            ));
          }

          // Total stats
          final totalSessions = ended.length;
          final totalDuration = ended.fold<Duration>(
            Duration.zero,
            (acc, s) => acc + s.endedAt!.difference(s.startedAt),
          );
          final lastEverDate = ended
              .map((s) => s.endedAt!)
              .reduce((a, b) => a.isAfter(b) ? a : b);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Vue globale',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _MiniStatChip(
                    icon: Icons.calendar_month,
                    label: '$totalSessions séances'),
                _MiniStatChip(
                    icon: Icons.timer_outlined,
                    label: '${totalDuration.inMinutes} min total'),
                _MiniStatChip(
                    icon: Icons.event_available,
                    label: 'Dernière : ${_dateOnly(lastEverDate)}'),
              ]),
              const SizedBox(height: 24),
              Text('Par template',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final s in stats)
                if (s.sessions.isNotEmpty) _TemplateStatsCard(stats: s),
            ],
          );
        },
      ),
    );
  }
}

class _TemplateStats {
  final String templateName;
  final String? templateId;
  final List<WorkoutSession> sessions;
  const _TemplateStats({
    required this.templateName,
    required this.templateId,
    required this.sessions,
  });
}

class _TemplateStatsCard extends StatelessWidget {
  final _TemplateStats stats;
  const _TemplateStatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final sessions = stats.sessions;
    final last = sessions
        .map((s) => s.endedAt!)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final totalDuration = sessions.fold<Duration>(
      Duration.zero,
      (acc, s) => acc + s.endedAt!.difference(s.startedAt),
    );
    final avgMin = sessions.isEmpty
        ? 0
        : (totalDuration.inMinutes / sessions.length).round();

    // Daily frequency: sessions / span in weeks
    final firstDate = sessions
        .map((s) => s.endedAt!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final spanDays = last.difference(firstDate).inDays;
    final perWeek = spanDays < 7
        ? sessions.length.toDouble()
        : sessions.length / (spanDays / 7);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stats.templateName,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _MiniStatChip(
                  icon: Icons.fitness_center,
                  label:
                      '${sessions.length} séance${sessions.length > 1 ? 's' : ''}'),
              _MiniStatChip(
                  icon: Icons.event,
                  label: 'Dernière : ${_dateOnly(last)}'),
              _MiniStatChip(
                  icon: Icons.timer_outlined,
                  label: 'Moy. ${avgMin}min'),
              if (sessions.length >= 2)
                _MiniStatChip(
                    icon: Icons.trending_up,
                    label: '${perWeek.toStringAsFixed(1)}/sem'),
            ]),
          ],
        ),
      ),
    );
  }
}

class _MiniStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniStatChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

String _dateOnly(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

class _VolumeProgressionTab extends ConsumerWidget {
  const _VolumeProgressionTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysSinceMonday = today.weekday - 1;
    final thisMonday = today.subtract(Duration(days: daysSinceMonday));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    final tomorrow = today.add(const Duration(days: 1));

    final asyncThisVol =
        ref.watch(volumeByMuscleProvider(VolumeRange(
      from: thisMonday,
      to: tomorrow,
    )));
    final asyncThisSets = ref.watch(setsByMuscleProvider(VolumeRange(
      from: thisMonday,
      to: tomorrow,
    )));
    final asyncLastVol =
        ref.watch(volumeByMuscleProvider(VolumeRange(
      from: lastMonday,
      to: thisMonday,
    )));
    final asyncLastSets = ref.watch(setsByMuscleProvider(VolumeRange(
      from: lastMonday,
      to: thisMonday,
    )));
    final asyncTrend = ref.watch(muscleWeeklyTrendProvider(8));

    return asyncThisVol.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (currentVol) {
        final lastVol = asyncLastVol.valueOrNull ?? const {};
        final currentSets = asyncThisSets.valueOrNull ?? const {};
        final lastSets = asyncLastSets.valueOrNull ?? const {};
        final trend = asyncTrend.valueOrNull ?? const {};
        // Union of muscle keys (across vols/sets/trend), sorted by current
        // sets desc (sets is a more intuitive primary metric than kg).
        final muscles = <String>{
          ...currentVol.keys,
          ...lastVol.keys,
          ...currentSets.keys,
          ...trend.keys,
        }.toList()
          ..sort((a, b) =>
              (currentSets[b] ?? 0).compareTo(currentSets[a] ?? 0));
        if (muscles.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Aucune série validée sur les 14 derniers jours.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final totalThisVol =
            currentVol.values.fold<double>(0, (a, b) => a + b);
        final totalLastVol =
            lastVol.values.fold<double>(0, (a, b) => a + b);
        final totalThisSets =
            currentSets.values.fold<int>(0, (a, b) => a + b);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Volume par groupe musculaire',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              "Semaine en cours (lundi → aujourd'hui) vs la précédente. "
              "10+ séries/sem par muscle = recommandation hypertrophie.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            _TotalsRow(
              thisWeek: totalThisVol,
              lastWeek: totalLastVol,
              thisSets: totalThisSets,
            ),
            const SizedBox(height: 16),
            for (final m in muscles)
              _MuscleVolumeRow(
                muscle: m,
                thisVolume: currentVol[m] ?? 0,
                lastVolume: lastVol[m] ?? 0,
                thisSets: currentSets[m] ?? 0,
                lastSetsCount: lastSets[m] ?? 0,
                trend: trend[m] ?? const [],
              ),
            const SizedBox(height: 12),
            Text(
              "Volume = Σ(reps × kg) sans warm-up. "
              "Sets/sem = nombre de séries effectives. "
              "Sparkline = 8 dernières semaines.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final double thisWeek;
  final double lastWeek;
  final int thisSets;
  const _TotalsRow({
    required this.thisWeek,
    required this.lastWeek,
    required this.thisSets,
  });

  @override
  Widget build(BuildContext context) {
    final delta = thisWeek - lastWeek;
    final pct = lastWeek == 0 ? null : (delta / lastWeek) * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cette semaine',
                      style: Theme.of(context).textTheme.labelMedium),
                  Text(
                    '${thisWeek.toStringAsFixed(0)} kg',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text('$thisSets séries',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Semaine précédente',
                      style: Theme.of(context).textTheme.labelMedium),
                  Text(
                    '${lastWeek.toStringAsFixed(0)} kg',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            if (pct != null)
              _DeltaBadge(deltaPct: pct),
          ],
        ),
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final double deltaPct;
  const _DeltaBadge({required this.deltaPct});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final positive = deltaPct >= 0;
    final color = positive ? Colors.green : cs.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.trending_up : Icons.trending_down,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 2),
          Text(
            '${positive ? '+' : ''}${deltaPct.toStringAsFixed(0)}%',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _MuscleVolumeRow extends StatelessWidget {
  final String muscle;
  final double thisVolume;
  final double lastVolume;
  final int thisSets;
  final int lastSetsCount;
  final List<MuscleWeekStat> trend;
  const _MuscleVolumeRow({
    required this.muscle,
    required this.thisVolume,
    required this.lastVolume,
    required this.thisSets,
    required this.lastSetsCount,
    required this.trend,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stale = thisSets == 0 && lastSetsCount > 0;
    // Schoenfeld 2017 ballpark: ≥10 hard sets/week per muscle for hypertrophy.
    final undertrained = thisSets > 0 && thisSets < 10;
    final delta = thisVolume - lastVolume;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: stale
              ? Colors.orange
              : (undertrained
                  ? Colors.amber.withOpacity(0.7)
                  : cs.outlineVariant),
          width: stale ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _muscleLabel(muscle),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (stale)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('⚠️ rien depuis 7j',
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange)),
                ),
              if (!stale && undertrained)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('< 10 sets/sem',
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$thisSets sets',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (trend.length >= 2)
            SizedBox(
              height: 36,
              child: _MiniSparkline(
                values: [for (final w in trend) w.sets.toDouble()],
                color: cs.primary,
              ),
            ),
          if (trend.length >= 2) const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${thisVolume.toStringAsFixed(0)} kg',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 6),
              Text(
                '(prec. ${lastVolume.toStringAsFixed(0)} kg, '
                '$lastSetsCount sets)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              if (lastVolume > 0)
                Text(
                  '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)} kg',
                  style: TextStyle(
                    color: delta >= 0 ? Colors.green : cs.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tiny sparkline based on a list of doubles. No axis, just a curve.
class _MiniSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  const _MiniSparkline({required this.values, required this.color});
  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<double>(0, (a, b) => a > b ? a : b);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxV == 0 ? 1 : maxV * 1.15,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i]),
            ],
            isCurved: true,
            preventCurveOverShooting: true,
            barWidth: 2,
            color: color,
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.15),
            ),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

String _muscleLabel(String enumName) {
  // map enum names to french labels
  const map = {
    'chest': 'Pectoraux',
    'upperBack': 'Dos (haut)',
    'lats': 'Grands dorsaux',
    'lowerBack': 'Lombaires',
    'shoulders': 'Épaules',
    'rearDelts': 'Deltoïdes postérieurs',
    'biceps': 'Biceps',
    'triceps': 'Triceps',
    'forearms': 'Avant-bras',
    'quads': 'Quadriceps',
    'hamstrings': 'Ischio-jambiers',
    'glutes': 'Fessiers',
    'calves': 'Mollets',
    'abs': 'Abdos',
    'obliques': 'Obliques',
    'cardio': 'Cardio',
  };
  return map[enumName] ?? enumName;
}

class _BodyweightTab extends ConsumerWidget {
  const _BodyweightTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEntries = ref.watch(bodyweightEntriesProvider);
    return asyncEntries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (entries) {
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _BodyweightHeader(entries: entries),
                const SizedBox(height: 16),
                _BodyweightChart(entries: entries),
                if (entries.length >= 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Container(
                          width: 12,
                          height: 2,
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant),
                      const SizedBox(width: 4),
                      Text('saisies brutes',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall),
                      const SizedBox(width: 12),
                      Container(
                          width: 12,
                          height: 3,
                          color:
                              Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('moyenne 7 jours',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall),
                    ]),
                  ),
                const SizedBox(height: 16),
                if (entries.isNotEmpty) ...[
                  Text('Historique',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final e in entries.reversed.take(60))
                    _BodyweightTile(entry: e),
                ],
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                heroTag: 'logBodyweight',
                onPressed: () => _logBodyweight(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BodyweightHeader extends StatelessWidget {
  final List<BodyweightEntry> entries;
  const _BodyweightHeader({required this.entries});
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "Aucun poids enregistré pour le moment.\n\n"
            "Appuie sur Ajouter pour logger ton poids du jour. "
            "Idéalement, fais-le toujours au même moment "
            "(ex: au réveil après les WC).",
          ),
        ),
      );
    }
    final latest = entries.last;
    final latestDate = BodyweightEntry.parseDate(latest.date);
    final prev = entries.length >= 2 ? entries[entries.length - 2] : null;
    final delta = prev == null ? null : latest.weightKg - prev.weightKg;
    final daysAgo = DateTime.now().difference(latestDate).inDays;
    final ago = daysAgo == 0
        ? "aujourd'hui"
        : daysAgo == 1
            ? 'hier'
            : 'il y a $daysAgo jours';
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dernier poids',
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${latest.weightKg.toStringAsFixed(1)} kg',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Saisi $ago',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            if (delta != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Δ vs précédent',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    Text(
                      '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: delta == 0
                            ? cs.onSurfaceVariant
                            : (delta > 0 ? Colors.orange : Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BodyweightChart extends StatelessWidget {
  final List<BodyweightEntry> entries;
  const _BodyweightChart({required this.entries});
  @override
  Widget build(BuildContext context) {
    if (entries.length < 2) {
      return SizedBox(
        height: 220,
        child: Card(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                entries.isEmpty
                    ? 'Au moins 2 saisies pour afficher la courbe.'
                    : 'Encore une saisie pour voir la courbe se dessiner !',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final firstDate = BodyweightEntry.parseDate(entries.first.date);
    final spots = <FlSpot>[
      for (final e in entries)
        FlSpot(
          BodyweightEntry.parseDate(e.date)
              .difference(firstDate)
              .inDays
              .toDouble(),
          e.weightKg,
        ),
    ];
    // 7-day moving average — smooths out the daily fluctuations.
    final smoothSpots = <FlSpot>[];
    for (var i = 0; i < entries.length; i++) {
      final cutoff = BodyweightEntry.parseDate(entries[i].date)
          .subtract(const Duration(days: 6));
      var sum = 0.0;
      var count = 0;
      for (var j = i; j >= 0; j--) {
        final d = BodyweightEntry.parseDate(entries[j].date);
        if (d.isBefore(cutoff)) break;
        sum += entries[j].weightKg;
        count++;
      }
      smoothSpots.add(FlSpot(spots[i].x, sum / count));
    }
    final minY =
        entries.map((e) => e.weightKg).reduce((a, b) => a < b ? a : b) - 1;
    final maxY =
        entries.map((e) => e.weightKg).reduce((a, b) => a > b ? a : b) + 1;
    return SizedBox(
      height: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              lineBarsData: [
                // Raw daily readings (faded).
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  barWidth: 1,
                  color: cs.outlineVariant,
                  dotData: FlDotData(
                    show: spots.length <= 60,
                    getDotPainter: (spot, _, __, ___) =>
                        FlDotCirclePainter(
                      radius: 2,
                      color: cs.outlineVariant,
                      strokeWidth: 0,
                    ),
                  ),
                ),
                // 7-day moving average (vivid).
                LineChartBarData(
                  spots: smoothSpots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  barWidth: 3,
                  color: cs.primary,
                  belowBarData: BarAreaData(
                    show: true,
                    color: cs.primary.withOpacity(0.12),
                  ),
                  dotData: const FlDotData(show: false),
                ),
              ],
              gridData: const FlGridData(
                show: true,
                drawVerticalLine: false,
              ),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final d = firstDate
                          .add(Duration(days: value.toInt()));
                      // Keep labels sparse.
                      if (value == meta.min || value == meta.max) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${d.day}/${d.month}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (value, meta) => Text(
                      value.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyweightTile extends ConsumerWidget {
  final BodyweightEntry entry;
  const _BodyweightTile({required this.entry});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = BodyweightEntry.parseDate(entry.date);
    return Dismissible(
      key: ValueKey('bw_${entry.date}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Supprimer cette saisie ?'),
                content:
                    Text('Le poids du ${entry.date} sera retiré.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Annuler'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Supprimer'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => ref
          .read(bodyweightRepositoryProvider)
          .delete(entry.date),
      child: Card(
        child: ListTile(
          dense: true,
          title:
              Text('${entry.weightKg.toStringAsFixed(1)} kg'),
          subtitle: Text(
            '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}'
            '${entry.note != null && entry.note!.isNotEmpty ? ' • ${entry.note}' : ''}',
          ),
          onTap: () => _logBodyweight(context, ref, existing: entry),
        ),
      ),
    );
  }
}

Future<void> _logBodyweight(
  BuildContext context,
  WidgetRef ref, {
  BodyweightEntry? existing,
}) async {
  var date = existing != null
      ? BodyweightEntry.parseDate(existing.date)
      : DateTime.now();
  final weightCtrl = TextEditingController(
    text: existing?.weightKg.toStringAsFixed(1) ?? '',
  );
  final noteCtrl =
      TextEditingController(text: existing?.note ?? '');
  final repo = ref.read(bodyweightRepositoryProvider);

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (sheetCtx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null
                      ? 'Logger mon poids'
                      : 'Modifier la saisie',
                  style: Theme.of(sheetCtx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(
                    '${date.day.toString().padLeft(2, '0')}/'
                    '${date.month.toString().padLeft(2, '0')}/${date.year}',
                  ),
                  trailing: existing == null
                      ? TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: sheetCtx,
                              initialDate: date,
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 365 * 5)),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setSheetState(() => date = picked);
                            }
                          },
                          child: const Text('Changer'),
                        )
                      : null,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: weightCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Poids',
                    suffixText: 'kg',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final v = double.tryParse(
                        weightCtrl.text.replaceAll(',', '.'));
                    if (v == null || v <= 0) {
                      ScaffoldMessenger.of(sheetCtx).showSnackBar(
                        const SnackBar(
                            content: Text('Poids invalide')),
                      );
                      return;
                    }
                    await repo.upsert(BodyweightEntry(
                      date: BodyweightEntry.formatDate(date),
                      weightKg: v,
                      note: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                      updatedAt: DateTime.now(),
                    ));
                    // Mirror the latest entry into UserSettings so bodyweight
                    // exercises always show an up-to-date total.
                    final all = await ref
                        .read(bodyweightRepositoryProvider)
                        .watchAll()
                        .first;
                    if (all.isNotEmpty) {
                      final latest = all.last;
                      final settings = await ref
                          .read(settingsRepositoryProvider)
                          .get();
                      if (settings.userBodyweightKg != latest.weightKg) {
                        await ref.read(settingsRepositoryProvider).save(
                              settings.copyWith(
                                  userBodyweightKg: latest.weightKg),
                            );
                      }
                    }
                    if (sheetCtx.mounted) {
                      Navigator.pop(sheetCtx, true);
                    }
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  weightCtrl.dispose();
  noteCtrl.dispose();
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Poids enregistré')),
    );
  }
}
