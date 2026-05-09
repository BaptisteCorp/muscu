import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/session.dart';

/// Onglet "Séances" : vue globale (nb total, durée totale) + détail par
/// template (séances, fréquence, durée moyenne, dernière date).
class SessionsProgressionTab extends ConsumerWidget {
  const SessionsProgressionTab({super.key});

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

          final byTemplate = <String?, List<WorkoutSession>>{};
          for (final s in ended) {
            byTemplate.putIfAbsent(s.templateId, () => []).add(s);
          }
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
                    label: 'Dernière : ${fmtDate(lastEverDate)}'),
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
                  label: 'Dernière : ${fmtDate(last)}'),
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
