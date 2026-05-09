import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/repositories/session_repository.dart';

/// Onglet "Volume" : volume + sets par muscle (semaine en cours vs précédente)
/// avec sparkline de tendance sur 8 semaines.
class VolumeProgressionTab extends ConsumerWidget {
  const VolumeProgressionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysSinceMonday = today.weekday - 1;
    final thisMonday = today.subtract(Duration(days: daysSinceMonday));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    final tomorrow = today.add(const Duration(days: 1));

    final asyncThisVol = ref.watch(volumeByMuscleProvider(VolumeRange(
      from: thisMonday,
      to: tomorrow,
    )));
    final asyncThisSets = ref.watch(setsByMuscleProvider(VolumeRange(
      from: thisMonday,
      to: tomorrow,
    )));
    final asyncLastVol = ref.watch(volumeByMuscleProvider(VolumeRange(
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            if (pct != null) _DeltaBadge(deltaPct: pct),
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
                  muscleLabelByName(muscle),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (stale)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('⚠️ rien depuis 7j',
                      style:
                          TextStyle(fontSize: 11, color: Colors.orange)),
                ),
              if (!stale && undertrained)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('< 10 sets/sem',
                      style:
                          TextStyle(fontSize: 11, color: Colors.orange)),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

/// Sparkline minimaliste basée sur une liste de doubles. Ni axe ni légende,
/// juste une courbe pour illustrer la tendance.
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
