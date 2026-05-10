import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/sync/sync_service.dart';
import '../../../domain/models/bodyweight_entry.dart';

/// Onglet "Poids" : courbe poids du corps (saisies brutes + moyenne 7j),
/// historique récent, FAB "Ajouter".
class BodyweightTab extends ConsumerWidget {
  const BodyweightTab({super.key});

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
                          color: Theme.of(context).colorScheme.outlineVariant),
                      const SizedBox(width: 4),
                      Text('saisies brutes',
                          style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(width: 12),
                      Container(
                          width: 12,
                          height: 3,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('moyenne 7 jours',
                          style: Theme.of(context).textTheme.labelSmall),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  barWidth: 1,
                  color: cs.outlineVariant,
                  dotData: FlDotData(
                    show: spots.length <= 60,
                    getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                      radius: 2,
                      color: cs.outlineVariant,
                      strokeWidth: 0,
                    ),
                  ),
                ),
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
                      final d =
                          firstDate.add(Duration(days: value.toInt()));
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
                content: Text('Le poids du ${entry.date} sera retiré.'),
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
      onDismissed: (_) async {
        await ref.read(bodyweightRepositoryProvider).delete(entry.date);
        try {
          await ref
              .read(syncServiceProvider)
              .pushBodyweight(entry.date, delete: true);
        } catch (_) {/* later sync will retry */}
      },
      child: Card(
        child: ListTile(
          dense: true,
          title: Text('${entry.weightKg.toStringAsFixed(1)} kg'),
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

/// Bottom sheet d'ajout / d'édition d'une saisie de poids du corps.
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
  final noteCtrl = TextEditingController(text: existing?.note ?? '');
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
                  existing == null ? 'Logger mon poids' : 'Modifier la saisie',
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
                        const SnackBar(content: Text('Poids invalide')),
                      );
                      return;
                    }
                    final dateStr = BodyweightEntry.formatDate(date);
                    await repo.upsert(BodyweightEntry(
                      date: dateStr,
                      weightKg: v,
                      note: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                      updatedAt: DateTime.now(),
                    ));
                    try {
                      await ref
                          .read(syncServiceProvider)
                          .pushBodyweight(dateStr);
                    } catch (_) {/* later sync will retry */}
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
