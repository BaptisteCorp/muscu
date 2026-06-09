import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/one_rep_max.dart';
import '../../../core/widgets/exercise_name_label.dart';
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

  @override
  Widget build(BuildContext context) {
    final asyncExercises = ref.watch(allExercisesProvider);
    final asyncTrained = ref.watch(trainedExerciseIdsProvider);
    final usageCounts = ref.watch(exerciseUsageCountsProvider).valueOrNull ??
        const <String, int>{};

    return asyncExercises.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) {
          final trainedIds = asyncTrained.valueOrNull ?? const <String>[];
          final byId = {for (final e in list) e.id: e};
          // Seuls les exos déjà entraînés sont proposés (les autres n'ont rien
          // à afficher), triés du plus fait au moins fait.
          final ordered = [
            for (final id in trainedIds)
              if (byId[id] != null) byId[id]!,
          ]..sort((a, b) {
              final ca = usageCounts[a.id] ?? 0;
              final cb = usageCounts[b.id] ?? 0;
              if (cb != ca) return cb.compareTo(ca);
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          final trainedExercises = ordered;

          final selected = _selected ??
              (ordered.isNotEmpty ? ordered.first : null);

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
                Text('${trainedExercises.length} exo'
                    '${trainedExercises.length > 1 ? 's' : ''} entraîné'
                    '${trainedExercises.length > 1 ? 's' : ''}'),
                const SizedBox(height: 8),
              ],
              if (selected != null)
                _ExercisePicker(
                  selected: selected,
                  exercises: ordered,
                  usageCounts: usageCounts,
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

/// Tappable "form field" showing the current exercise. Tapping opens a
/// searchable bottom sheet (list sorted most-trained first) — far more
/// instinctive than a native dropdown menu for a long catalogue.
class _ExercisePicker extends StatelessWidget {
  final Exercise selected;
  final List<Exercise> exercises;
  final Map<String, int> usageCounts;
  final ValueChanged<Exercise> onChanged;
  const _ExercisePicker({
    required this.selected,
    required this.exercises,
    required this.usageCounts,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExerciseSearchSheet(
        exercises: exercises,
        usageCounts: usageCounts,
        selectedId: selected.id,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(AppTokens.radiusM),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EXERCICE',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  ExerciseNameLabel(
                    name: selected.name,
                    equipment: selected.equipment,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.unfold_more_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to pick an exercise: a search box on top, then the trained
/// exercises (most-done first) with their usage count and a check on the
/// current one. Pops the chosen [Exercise].
class _ExerciseSearchSheet extends StatefulWidget {
  final List<Exercise> exercises;
  final Map<String, int> usageCounts;
  final String selectedId;
  const _ExerciseSearchSheet({
    required this.exercises,
    required this.usageCounts,
    required this.selectedId,
  });

  @override
  State<_ExerciseSearchSheet> createState() => _ExerciseSearchSheetState();
}

class _ExerciseSearchSheetState extends State<_ExerciseSearchSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.exercises
        : widget.exercises
            .where((e) => e.name.toLowerCase().contains(q))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Padding(
        padding: EdgeInsets.fromLTRB(
            12, 10, 12, MediaQuery.of(context).viewInsets.bottom + 8),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher un exercice...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Aucun exercice',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        final count = widget.usageCounts[e.id] ?? 0;
                        final isSel = e.id == widget.selectedId;
                        return ListTile(
                          selected: isSel,
                          title: ExerciseNameLabel(
                            name: e.name,
                            equipment: e.equipment,
                          ),
                          subtitle: Text(
                            count > 0
                                ? 'fait $count fois'
                                : muscleLabel(e.primaryMuscle),
                          ),
                          trailing: isSel
                              ? Icon(Icons.check_rounded, color: cs.primary)
                              : null,
                          onTap: () => Navigator.pop(context, e),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
            // One card, one row per record: the label gets the full width so
            // nothing truncates ("Meilleur poids", "1RM estimé"…). The 1RM row
            // only shows for loaded exercises (bodyweight-only sets give no
            // sensible estimate).
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(AppTokens.radiusL),
                border: Border.all(color: cs.outlineVariant),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  _PrRow(
                    icon: Icons.fitness_center_rounded,
                    accent: cs.primary,
                    label: 'Meilleur poids',
                    value: '${fmtKg(prs.bestWeight)} kg',
                    sub: prs.bestWeightReps > 0
                        ? '× ${prs.bestWeightReps} reps'
                            '${prs.bestWeightDate == null ? '' : ' • ${fmtDate(prs.bestWeightDate!)}'}'
                        : null,
                  ),
                  if (prs.bestOneRepMax > 0) ...[
                    Divider(height: 1, color: cs.outlineVariant),
                    _PrRow(
                      icon: Icons.bolt_rounded,
                      accent: cs.tertiary,
                      label: '1RM estimé',
                      value: '${fmtKg(prs.bestOneRepMax)} kg',
                      sub: '${prs.bestOneRepMaxReps} × '
                          '${fmtKg(prs.bestOneRepMaxWeight)} kg',
                    ),
                  ],
                  Divider(height: 1, color: cs.outlineVariant),
                  _PrRow(
                    icon: Icons.bar_chart_rounded,
                    accent: cs.secondary,
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
            _ChartSection(
              title: 'Force — poids le plus lourd',
              ready: perSession.length >= 2,
              child: perSession.length < 2
                  ? null
                  : _TrendChart(
                      values: [for (final p in perSession) p.heaviestWeight],
                      color: cs.primary,
                      axisFormatter: fmtKg,
                      tooltipFormatter: (v) => '${fmtKg(v)} kg',
                      startLabel: fmtDate(perSession.first.date),
                      endLabel: fmtDate(perSession.last.date),
                    ),
            ),
            const SizedBox(height: 24),
            _ChartSection(
              title: 'Volume par séance',
              ready: perSession.length >= 2,
              child: perSession.length < 2
                  ? null
                  : _TrendChart(
                      values: [for (final p in perSession) p.volume],
                      color: cs.secondary,
                      axisFormatter: _compactNumber,
                      tooltipFormatter: (v) => '${v.toStringAsFixed(0)} kg',
                      startLabel: fmtDate(perSession.first.date),
                      endLabel: fmtDate(perSession.last.date),
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

/// One personal-record line: a coloured icon, the full label + an optional
/// detail line on the left, and the big value on the right. Stacked in a
/// single card so labels never have to compete for horizontal space.
class _PrRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String? sub;
  const _PrRow({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(AppTokens.radiusM),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      sub!,
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
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title + framed chart card (or a placeholder when there isn't
/// enough data yet). Keeps the two trend charts visually consistent.
class _ChartSection extends StatelessWidget {
  final String title;
  final bool ready;
  final Widget? child;
  const _ChartSection({
    required this.title,
    required this.ready,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (ready && child != null)
          child!
        else
          Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(AppTokens.radiusL),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              'Au moins 2 séances nécessaires',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// Polished area + line chart used for the per-session trends. Framed in a
/// card, smooth curve with a fading gradient fill, muted left-axis labels,
/// a touch tooltip, and the date range under the plot for legibility.
class _TrendChart extends StatelessWidget {
  final List<double> values;
  final Color color;

  /// Formats the left-axis ticks (compact).
  final String Function(double) axisFormatter;

  /// Formats the value shown in the touch tooltip (full + unit).
  final String Function(double) tooltipFormatter;
  final String? startLabel;
  final String? endLabel;
  const _TrendChart({
    required this.values,
    required this.color,
    required this.axisFormatter,
    required this.tooltipFormatter,
    this.startLabel,
    this.endLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs();
    final pad = range < 1e-9
        ? (maxV.abs() < 1e-9 ? 1.0 : maxV.abs() * 0.1)
        : range * 0.18;
    // Don't dip below zero when every value is positive (weights, volume).
    final minY = (minV >= 0) ? (minV - pad).clamp(0.0, minV) : minV - pad;
    final maxY = maxV + pad;
    final interval = ((maxY - minY) / 4).clamp(1.0, double.infinity);
    final spots = [
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i]),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(6, 16, 14, 10),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (values.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => cs.inverseSurface,
                    getTooltipItems: (touched) => [
                      for (final t in touched)
                        LineTooltipItem(
                          tooltipFormatter(t.y),
                          TextStyle(
                            color: cs.onInverseSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    barWidth: 3,
                    color: color,
                    dotData: FlDotData(
                      show: values.length <= 12,
                      getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                        radius: 3.5,
                        color: color,
                        strokeWidth: 2,
                        strokeColor: cs.surfaceContainer,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          color.withOpacity(0.28),
                          color.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: interval,
                      getTitlesWidget: (v, meta) {
                        if (v <= meta.min || v >= meta.max) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            axisFormatter(v),
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: cs.outlineVariant.withOpacity(0.5),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
          if (startLabel != null && endLabel != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    startLabel!,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    endLabel!,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact number for chart axes: 1 234 → "1.2k", 950 → "950".
String _compactNumber(double v) {
  if (v.abs() >= 1000) {
    final k = v / 1000;
    return '${k.toStringAsFixed(k == k.truncateToDouble() ? 0 : 1)}k';
  }
  return v.toStringAsFixed(0);
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
  // Meilleur 1RM estimé (Epley) sur toutes les séries de travail, + la série
  // qui l'a produit.
  final double bestOneRepMax;
  final int bestOneRepMaxReps;
  final double bestOneRepMaxWeight;
  final DateTime? bestOneRepMaxDate;
  _Pr({
    required this.volume,
    required this.volumeDate,
    required this.bestWeightReps,
    required this.bestWeight,
    required this.bestWeightDate,
    required this.bestRepsCount,
    required this.bestRepsWeight,
    required this.bestRepsDate,
    required this.bestOneRepMax,
    required this.bestOneRepMaxReps,
    required this.bestOneRepMaxWeight,
    required this.bestOneRepMaxDate,
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
  double bestOrm = 0;
  int bestOrmReps = 0;
  double bestOrmW = 0;
  DateTime? bestOrmDate;
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
      final orm = estimateOneRepMax(set.weightKg, set.reps);
      if (orm != null && orm > bestOrm) {
        bestOrm = orm;
        bestOrmReps = set.reps;
        bestOrmW = set.weightKg;
        bestOrmDate = set.completedAt;
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
    bestOneRepMax: bestOrm,
    bestOneRepMaxReps: bestOrmReps,
    bestOneRepMaxWeight: bestOrmW,
    bestOneRepMaxDate: bestOrmDate,
  );
}
