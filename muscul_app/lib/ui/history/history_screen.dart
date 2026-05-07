import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/models/session.dart';
import '../../domain/models/workout_template.dart';

const _uuid = Uuid();

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncHistory = ref.watch(sessionHistoryProvider);
    final asyncTemplates = ref.watch(allTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: asyncHistory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (list) {
          final ended = list.where((s) => s.endedAt != null).toList();
          final templatesById = <String, WorkoutTemplate>{
            for (final t in asyncTemplates.valueOrNull ?? const [])
              t.id: t,
          };
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeatmapSection(
                sessions: ended,
                templatesById: templatesById,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => _addPastSession(context, ref),
                  icon: const Icon(Icons.history_edu),
                  label: const Text('Ajouter une séance passée'),
                ),
              ),
              const SizedBox(height: 24),
              Text('Séances terminées',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (ended.isEmpty)
                const Card(
                  child: ListTile(title: Text('Aucune séance terminée')),
                )
              else
                for (final s in ended) _HistoryTile(session: s),
            ],
          );
        },
      ),
    );
  }
}

class _HeatmapSection extends StatefulWidget {
  final List<WorkoutSession> sessions;
  final Map<String, WorkoutTemplate> templatesById;
  const _HeatmapSection({
    required this.sessions,
    required this.templatesById,
  });

  @override
  State<_HeatmapSection> createState() => _HeatmapSectionState();
}

class _HeatmapSectionState extends State<_HeatmapSection> {
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchor = DateTime(now.year, now.month, 1);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _anchor = DateTime(_anchor.year, _anchor.month + delta, 1);
    });
  }

  /// Sessions per day of the displayed month.
  Map<int, List<WorkoutSession>> _byDay(int year, int month) {
    final m = <int, List<WorkoutSession>>{};
    for (final s in widget.sessions) {
      final d = s.endedAt!;
      if (d.year == year && d.month == month) {
        m.putIfAbsent(d.day, () => []).add(s);
      }
    }
    return m;
  }

  String _shortNameFor(WorkoutSession s) {
    final tid = s.templateId;
    if (tid == null) return 'Free';
    final t = widget.templatesById[tid];
    return t?.name ?? '?';
  }

  void _showDaySheet(BuildContext context, List<WorkoutSession> sessions) {
    if (sessions.isEmpty) return;
    final dt = sessions.first.endedAt!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _dayHeader(dt),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final s in sessions)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.fitness_center),
                    title: Text(_shortNameFor(s)),
                    subtitle: Text(
                      'Démarrée à ${_timeOnly(s.startedAt)} • '
                      '${s.endedAt!.difference(s.startedAt).inMinutes} min',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) =>
                            _SessionSummarySheet(sessionId: s.id),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final year = _anchor.year;
    final month = _anchor.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Monday = 1 .. Sunday = 7. We want Monday first.
    final firstWeekday = DateTime(year, month, 1).weekday;
    final leading = firstWeekday - 1; // empty cells before day 1
    final byDay = _byDay(year, month);
    final today = DateTime.now();
    final isCurrentMonth = year == today.year && month == today.month;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Text(
                    _monthLabel(year, month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final l in const ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
                  Expanded(
                    child: Center(
                      child: Text(l,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  )),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Grid of weeks
            for (var weekStart = -leading;
                weekStart < daysInMonth;
                weekStart += 7)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: _HeatCell(
                          day: weekStart + i + 1 > 0 &&
                                  weekStart + i + 1 <= daysInMonth
                              ? weekStart + i + 1
                              : null,
                          sessions:
                              byDay[weekStart + i + 1] ?? const [],
                          isToday: isCurrentMonth &&
                              today.day == weekStart + i + 1,
                          shortName: _shortNameFor,
                          onTap: (sessions) =>
                              _showDaySheet(context, sessions),
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

class _HeatCell extends StatelessWidget {
  final int? day;
  final List<WorkoutSession> sessions;
  final bool isToday;
  final String Function(WorkoutSession) shortName;
  final ValueChanged<List<WorkoutSession>> onTap;
  const _HeatCell({
    required this.day,
    required this.sessions,
    required this.isToday,
    required this.shortName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (day == null) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox.shrink());
    }
    final cs = Theme.of(context).colorScheme;
    final count = sessions.length;
    final hasSession = count > 0;
    final bg = hasSession
        ? cs.primary
        : cs.surfaceContainerHighest.withOpacity(0.4);
    final fg = hasSession ? cs.onPrimary : cs.onSurfaceVariant;
    final label = hasSession
        ? (count == 1
            ? shortName(sessions.first)
            : '${shortName(sessions.first)} +${count - 1}')
        : null;
    return AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: hasSession ? () => onTap(sessions) : null,
          child: Tooltip(
            message: count > 0
                ? sessions.map(shortName).join(', ')
                : 'Aucune séance le $day',
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(4),
                border: isToday
                    ? Border.all(color: cs.primary, width: 1.5)
                    : null,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 10,
                      color: fg,
                      fontWeight: count > 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  if (label != null)
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: fg,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  final WorkoutSession session;
  const _HistoryTile({required this.session});

  Future<bool> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Supprimer cette séance ?'),
        content: const Text(
            'Tous les exos et séries seront retirés de l\'historique. '
            'La suppression est synchronisée avec le cloud.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _doDelete(WidgetRef ref) async {
    await ref.read(sessionRepositoryProvider).softDeleteSession(session.id);
    unawaited(ref.read(syncServiceProvider).sync());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dt = session.endedAt ?? session.startedAt;
    final duration = session.endedAt != null
        ? session.endedAt!.difference(session.startedAt)
        : Duration.zero;
    return Dismissible(
      key: ValueKey('hist_${session.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      // Confirm in the dialog, then let Dismissible animate. The actual
      // soft-delete happens in onDismissed so the stream-driven list
      // rebuild and the Dismissible animation don't fight each other.
      confirmDismiss: (_) => _confirm(context),
      onDismissed: (_) => _doDelete(ref),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.history),
          title: Text(_dateLabel(dt)),
          subtitle: Text('Durée: ${duration.inMinutes} min'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Supprimer',
              onPressed: () async {
                if (await _confirm(context)) {
                  await _doDelete(ref);
                }
              },
            ),
            const Icon(Icons.chevron_right),
          ]),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => _SessionSummarySheet(sessionId: session.id),
          ),
        ),
      ),
    );
  }
}

class _SessionSummarySheet extends ConsumerWidget {
  final String sessionId;
  const _SessionSummarySheet({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDetail = ref.watch(sessionDetailProvider(sessionId));
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      expand: false,
      builder: (_, scrollCtrl) => asyncDetail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Séance introuvable'));
          }
          final dt = detail.session.endedAt ?? detail.session.startedAt;
          final duration = detail.session.endedAt != null
              ? detail.session.endedAt!.difference(detail.session.startedAt)
              : Duration.zero;
          var totalVolume = 0.0;
          var totalSets = 0;
          for (final ex in detail.exercises) {
            for (final s in ex.sets) {
              if (s.isWarmup) continue;
              totalVolume += s.reps * s.weightKg;
              totalSets++;
            }
          }
          return ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Séance du ${_dateLabel(dt)}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _StatChip(
                    icon: Icons.timer_outlined,
                    label: '${duration.inMinutes} min'),
                _StatChip(
                    icon: Icons.fitness_center,
                    label: '${detail.exercises.length} exos'),
                _StatChip(icon: Icons.list_alt, label: '$totalSets séries'),
                _StatChip(
                    icon: Icons.scale,
                    label: '${totalVolume.toStringAsFixed(0)} kg total'),
              ]),
              if ((detail.session.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notes, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(detail.session.notes!)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (detail.exercises.isEmpty)
                const Text('Aucun exercice dans cette séance.')
              else
                for (final ex in detail.exercises)
                  _ExerciseSummaryCard(item: ex),
            ],
          );
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class _ExerciseSummaryCard extends ConsumerWidget {
  final SessionExerciseWithSets item;
  const _ExerciseSummaryCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exAsync =
        ref.watch(exerciseByIdProvider(item.sessionExercise.exerciseId));
    final working = item.sets.where((s) => !s.isWarmup).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            exAsync.when(
              data: (ex) => Text(
                ex?.name ?? '?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              loading: () => const Text('...'),
              error: (e, _) => Text('Erreur: $e'),
            ),
            const SizedBox(height: 4),
            if (working.isEmpty)
              Text(
                'Aucune série validée',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
              )
            else
              for (var i = 0; i < working.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    'Série ${i + 1} : ${working[i].reps} × '
                    '${_fmtKg(working[i].weightKg)}kg'
                    '${working[i].rpe != null ? '   RPE ${working[i].rpe}' : ''}',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _fmtKg(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}

String _dateLabel(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

String _timeOnly(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _dayHeader(DateTime d) {
  const weekdays = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche'
  ];
  return '${weekdays[d.weekday - 1]} ${d.day} ${_monthName(d.month)} ${d.year}';
}

String _monthName(int month) {
  const names = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  return names[month - 1];
}

String _monthLabel(int year, int month) {
  return '${_monthName(month)} $year';
}

/// Manual past-session entry: pick date+time, template (or freestyle),
/// duration. Creates a session whose `startedAt`/`endedAt` reflect the
/// chosen moment, then drops the user into the active session screen so
/// they can fill in the sets normally.
Future<void> _addPastSession(BuildContext context, WidgetRef ref) async {
  final templates = await ref.read(allTemplatesProvider.future);
  if (!context.mounted) return;
  final result = await showModalBottomSheet<_PastEntry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PastSessionSheet(templates: templates),
  );
  if (result == null) return;

  final repo = ref.read(sessionRepositoryProvider);
  final id = _uuid.v4();
  final session = WorkoutSession(
    id: id,
    templateId: result.templateId,
    startedAt: result.startedAt,
    endedAt: result.startedAt
        .add(Duration(minutes: result.durationMinutes)),
    updatedAt: DateTime.now(),
  );
  await repo.upsertSession(session);
  // Materialize the template's exercises (with rest carried over) so the
  // user can fill in sets.
  if (result.templateId != null) {
    final tpl = await ref
        .read(templateRepositoryProvider)
        .getWithExercises(result.templateId!);
    if (tpl != null) {
      for (var i = 0; i < tpl.exercises.length; i++) {
        final tew = tpl.exercises[i];
        await repo.upsertSessionExercise(SessionExercise(
          id: _uuid.v4(),
          sessionId: id,
          exerciseId: tew.exercise.exerciseId,
          orderIndex: i,
          restSeconds: tew.exercise.restSeconds,
        ));
      }
    }
  }
  unawaited(ref.read(syncServiceProvider).sync());
  if (context.mounted) {
    context.push('/session/$id');
  }
}

class _PastEntry {
  final DateTime startedAt;
  final int durationMinutes;
  final String? templateId;
  const _PastEntry({
    required this.startedAt,
    required this.durationMinutes,
    this.templateId,
  });
}

class _PastSessionSheet extends StatefulWidget {
  final List<WorkoutTemplate> templates;
  const _PastSessionSheet({required this.templates});
  @override
  State<_PastSessionSheet> createState() => _PastSessionSheetState();
}

class _PastSessionSheetState extends State<_PastSessionSheet> {
  late DateTime _date;
  int _durationMinutes = 60;
  String? _templateId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day - 1, 18);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (time == null) return;
    setState(() {
      _date = DateTime(
          picked.year, picked.month, picked.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ListView(
          controller: ctrl,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Ajouter une séance passée',
                style: Theme.of(context).textTheme.titleLarge),
            Text(
              'Saisis une séance que tu as faite mais pas encore loggée.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(_formatDate(_date)),
              trailing: TextButton(
                onPressed: _pickDate,
                child: const Text('Modifier'),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.timer_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: _durationMinutes.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Durée (min)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) {
                      setState(() => _durationMinutes = n);
                    }
                  },
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Template (optionnel)',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            DropdownButtonFormField<String?>(
              value: _templateId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('— Freestyle —'),
                ),
                for (final t in widget.templates)
                  DropdownMenuItem<String?>(
                    value: t.id,
                    child: Text(t.name),
                  ),
              ],
              onChanged: (v) => setState(() => _templateId = v),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                _PastEntry(
                  startedAt: _date,
                  durationMinutes: _durationMinutes,
                  templateId: _templateId,
                ),
              ),
              icon: const Icon(Icons.check),
              label: const Text('Continuer vers la saisie des séries'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  final weekday = const [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche'
  ][d.weekday - 1];
  return '$weekday ${d.day} ${_monthName(d.month)} '
      '${d.year} ${_timeOnly(d)}';
}
