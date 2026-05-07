import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/progression_target.dart';
import '../../domain/models/session.dart';
import '../../domain/models/user_settings.dart';
import '../../domain/models/workout_template.dart';
import '../../domain/progression/progression_engine.dart';
import 'quick_swap_sheet.dart';
import 'rest_timer.dart';
import 'set_row.dart';
import 'start_session_controller.dart';

const _uuid = Uuid();

class ActiveSessionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const ActiveSessionScreen({super.key, required this.sessionId});

  @override
  ConsumerState<ActiveSessionScreen> createState() =>
      _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends ConsumerState<ActiveSessionScreen> {
  final _restCtrl = RestTimerController();
  final _pageCtrl = PageController();
  // User adjustments per session-exercise per set position. Keyed
  // [exerciseSessionId][setIndex] → pending values. Cleared after validate
  // so the next set uses its own plan-derived default.
  final Map<String, Map<int, _Pending>> _pending = {};
  // skipped absolute set positions per session-exercise (UI-only).
  final Map<String, Set<int>> _skipped = {};
  // Plan from the template, indexed by exerciseId → list of planned sets
  // (sorted by setIndex). Empty list = no template plan (freestyle session).
  Map<String, List<TemplateExerciseSet>> _planByExercise = const {};
  // Last completed session per exerciseId for THIS template, used to
  // drive per-set progression. Null = no past data.
  final Map<String, SessionExerciseWithSets?> _lastByExercise = {};
  Timer? _sessionTicker;
  Duration _elapsed = Duration.zero;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _sessionTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => _refreshElapsed());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPlan();
    });
  }

  /// Reads the template's planned sets (if this session is from a template)
  /// and stashes the most recent past session per exercise so the row
  /// defaults can apply progressive overload.
  Future<void> _loadPlan() async {
    final detail = await ref
        .read(sessionRepositoryProvider)
        .getDetail(widget.sessionId);
    if (detail == null || !mounted) return;
    final templateId = detail.session.templateId;
    final planMap = <String, List<TemplateExerciseSet>>{};
    if (templateId != null) {
      final tpl = await ref
          .read(templateRepositoryProvider)
          .getWithExercises(templateId);
      if (tpl != null) {
        for (final tew in tpl.exercises) {
          // First-occurrence wins if the same exo appears twice in a template.
          planMap.putIfAbsent(tew.exercise.exerciseId, () => tew.sets);
        }
      }
    }
    // Fetch the last completed session per exercise (in this template).
    final lastByEx = <String, SessionExerciseWithSets?>{};
    for (final item in detail.exercises) {
      final exId = item.sessionExercise.exerciseId;
      if (lastByEx.containsKey(exId)) continue;
      lastByEx[exId] = await ref
          .read(sessionRepositoryProvider)
          .lastSessionExerciseInTemplate(
            exerciseId: exId,
            templateId: templateId,
          );
    }
    if (!mounted) return;
    setState(() {
      _planByExercise = planMap;
      _lastByExercise
        ..clear()
        ..addAll(lastByEx);
    });
  }

  @override
  void dispose() {
    _sessionTicker?.cancel();
    _restCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshElapsed() async {
    final detail = await ref
        .read(sessionRepositoryProvider)
        .getDetail(widget.sessionId);
    if (detail == null || !mounted) return;
    // Manual past-session entries already have an endedAt — show the
    // session's actual duration, not the wall-clock elapsed since
    // startedAt (which would read in days).
    final s = detail.session;
    final elapsed = s.endedAt != null
        ? s.endedAt!.difference(s.startedAt)
        : DateTime.now().difference(s.startedAt);
    setState(() => _elapsed = elapsed);
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(sessionDetailProvider(widget.sessionId));
    final settingsAsync = ref.watch(settingsStreamProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final action = await _confirmExit(context);
        if (action == _ExitAction.pause && context.mounted) {
          context.go('/home');
        } else if (action == _ExitAction.finish && context.mounted) {
          await _finish();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: detailAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur: $e')),
            data: (detail) {
              if (detail == null) {
                return const Center(child: Text('Séance introuvable'));
              }
              final settings = settingsAsync.maybeWhen(
                  data: (s) => s, orElse: () => const UserSettings());
              return _buildBody(detail, settings);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(SessionDetail detail, UserSettings settings) {
    final session = detail.session;
    final items = detail.exercises;

    if (items.isEmpty) {
      return Column(
        children: [
          _topBar(session.startedAt, 0),
          const Spacer(),
          const Text('Aucun exercice dans cette séance.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _addExerciseFreestyle(items.length),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un exercice'),
          ),
          const Spacer(),
        ],
      );
    }

    // Items can shrink under us (e.g. exo deletion / swap). Clamp the
    // tracked index so the "1/N" pill and dots indicator don't read past
    // the end of the list before the next onPageChanged fires.
    if (_currentPage >= items.length) {
      _currentPage = items.isEmpty ? 0 : items.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageCtrl.hasClients) return;
        _pageCtrl.jumpToPage(_currentPage);
      });
    }

    return Column(
      children: [
        _topBar(session.startedAt, items.length),
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (_, i) => _exercisePage(items, i, settings),
          ),
        ),
        if (items.length > 1)
          _PageDots(count: items.length, current: _currentPage.clamp(0, items.length - 1)),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: RestTimer(controller: _restCtrl),
        ),
      ],
    );
  }

  Widget _topBar(DateTime startedAt, int totalExos) {
    final cs = Theme.of(context).colorScheme;
    final mm = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final hh = _elapsed.inHours.toString();
    final ss = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final label = _elapsed.inHours > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              final action = await _confirmExit(context);
              if (action == _ExitAction.pause && mounted) {
                context.go('/home');
              } else if (action == _ExitAction.finish && mounted) {
                await _finish();
              }
            },
          ),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius:
                      BorderRadius.circular(AppTokens.radiusXL),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ],
                      ),
                    ),
                    if (totalExos > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        width: 1,
                        height: 14,
                        color: cs.outlineVariant,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${_currentPage.clamp(0, totalExos - 1) + 1}/$totalExos',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusM),
            ),
            onSelected: (v) async {
              switch (v) {
                case 'add':
                  await _addExerciseFreestyle(0);
                  break;
                case 'note':
                  await _editSessionNote();
                  break;
                case 'pause':
                  if (mounted) context.go('/home');
                  break;
                case 'finish':
                  await _finish();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'add',
                  child: ListTile(
                    leading: Icon(Icons.add_circle_outline),
                    title: Text('Ajouter un exercice'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  )),
              PopupMenuItem(
                  value: 'note',
                  child: ListTile(
                    leading: Icon(Icons.edit_note),
                    title: Text('Note de séance'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  )),
              PopupMenuItem(
                  value: 'pause',
                  child: ListTile(
                    leading: Icon(Icons.pause_circle_outline),
                    title: Text('Mettre en pause'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  )),
              PopupMenuItem(
                  value: 'finish',
                  child: ListTile(
                    leading: Icon(Icons.flag_outlined),
                    title: Text('Terminer la séance'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _exercisePage(List<SessionExerciseWithSets> items, int index,
      UserSettings settings) {
    final item = items[index];
    final exerciseAsync =
        ref.watch(exerciseByIdProvider(item.sessionExercise.exerciseId));
    final historyAsync = ref.watch(
        exerciseHistoryProvider(item.sessionExercise.exerciseId));

    return exerciseAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (exercise) {
        if (exercise == null) return const Center(child: Text('Exercice supprimé'));
        return historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur: $e')),
          data: (history) {
            // Filter out the current session-exercise from history (in-progress).
            final pastHistory = history
                .where((h) =>
                    h.sessionExercise.id != item.sessionExercise.id)
                .toList();
            final plannedSets = item.sets.length >= 3 ? item.sets.length : 3;
            final target = ProgressionEngine.computeNextTarget(
              exercise: exercise,
              plannedSets: plannedSets,
              history: pastHistory,
              settings: settings,
            );
            return _exerciseBody(
              items: items,
              index: index,
              item: item,
              exercise: exercise,
              target: target,
              settings: settings,
            );
          },
        );
      },
    );
  }

  Widget _exerciseBody({
    required List<SessionExerciseWithSets> items,
    required int index,
    required SessionExerciseWithSets item,
    required Exercise exercise,
    required ProgressionTarget target,
    required UserSettings settings,
  }) {
    final increment = exercise.effectiveIncrementKg(settings.defaultIncrementKg);
    final plan = _planByExercise[item.sessionExercise.exerciseId] ?? const [];
    final lastSession = _lastByExercise[item.sessionExercise.exerciseId];

    /// Per-position default reps + weight. Plan + last-session = progression.
    _Pending defaultFor(int pos) {
      final plannedSet = pos < plan.length ? plan[pos] : null;
      // No plan at all: legacy behaviour using the engine's target.
      if (plannedSet == null) {
        return _Pending(
          reps: target.targetReps,
          weight: target.targetWeightKg,
          rpe: target.targetRpe,
        );
      }
      // Match the same set-position in the most recent past session.
      final pastWorking = lastSession?.sets
              .where((s) => !s.isWarmup)
              .toList() ??
          const [];
      if (pastWorking.length > pos) {
        final last = pastWorking[pos];
        final rpeOk = (last.rpe ?? 8) <= 9;
        if (last.reps >= plannedSet.plannedReps && rpeOk) {
          // Hit target → bump weight by the increment.
          return _Pending(
            reps: plannedSet.plannedReps,
            weight: last.weightKg + increment,
            rpe: target.targetRpe,
          );
        }
        // Missed → retry the last weight you used.
        return _Pending(
          reps: plannedSet.plannedReps,
          weight: last.weightKg,
          rpe: target.targetRpe,
        );
      }
      // Never trained this slot → seed with the template's planned values.
      return _Pending(
        reps: plannedSet.plannedReps,
        weight: plannedSet.plannedWeightKg ?? exercise.startingWeightKg,
        rpe: target.targetRpe,
      );
    }

    /// Returns the (possibly user-edited) values for a given set position.
    _Pending pendingFor(int pos) =>
        _pending[item.sessionExercise.id]?[pos] ?? defaultFor(pos);

    void setPendingFor(int pos, _Pending p) {
      _pending.putIfAbsent(item.sessionExercise.id, () => {})[pos] = p;
    }

    final skipped = _skipped[item.sessionExercise.id] ?? <int>{};
    final savedCount = item.sets.length;
    // Plan length is the canonical "target sets" when a plan exists.
    final plannedCount = plan.isNotEmpty ? plan.length : target.targetSets;
    final totalSlots = [
      plannedCount,
      savedCount + skipped.length,
      3,
    ].reduce((a, b) => a > b ? a : b);

    final rows = <Widget>[];
    var savedConsumed = 0;
    var firstActiveAssigned = false;
    for (var pos = 0; pos < totalSlots; pos++) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 1));
      if (skipped.contains(pos)) {
        rows.add(SetRow(
          setIndex: pos,
          entry: null,
          reps: 0,
          weightKg: 0,
          rpe: null,
          incrementKg: increment,
          state: SetRowState.skipped,
          useRir: settings.useRirInsteadOfRpe,
          onRepsChanged: (_) {},
          onWeightChanged: (_) {},
          onRpeChanged: (_) {},
          onValidate: () {},
          onUnskip: () => setState(() {
            _skipped[item.sessionExercise.id] = {...skipped}..remove(pos);
          }),
        ));
        continue;
      }
      if (savedConsumed < savedCount) {
        final entry = item.sets[savedConsumed++];
        rows.add(SetRow(
          setIndex: pos,
          entry: entry,
          reps: entry.reps,
          weightKg: entry.weightKg,
          rpe: entry.rpe,
          incrementKg: increment,
          state: SetRowState.completed,
          useRir: settings.useRirInsteadOfRpe,
          bodyweightLabel: exercise.useBodyweight
              ? _bodyweightLabel(entry.weightKg, settings)
              : null,
          onRepsChanged: (_) {},
          onWeightChanged: (_) {},
          onRpeChanged: (_) {},
          onValidate: () {},
          onTap: () => _editExisting(entry),
        ));
        continue;
      }
      if (!firstActiveAssigned) {
        firstActiveAssigned = true;
        final p = pendingFor(pos);
        rows.add(SetRow(
          setIndex: pos,
          entry: null,
          reps: p.reps,
          weightKg: p.weight,
          rpe: p.rpe,
          incrementKg: increment,
          state: SetRowState.active,
          useRir: settings.useRirInsteadOfRpe,
          bodyweightLabel: exercise.useBodyweight
              ? _bodyweightLabel(p.weight, settings)
              : null,
          onRepsChanged: (v) => setState(() {
            setPendingFor(pos, p.copyWith(reps: v));
          }),
          onWeightChanged: (v) => setState(() {
            setPendingFor(pos, p.copyWith(weight: v));
          }),
          onRpeChanged: (v) => setState(() {
            setPendingFor(pos, p.copyWith(rpe: v));
          }),
          onValidate: () => _validateSet(
              item, p, settings, plannedCount,
              setPos: pos,
              restSeconds: item.sessionExercise.restSeconds ??
                  exercise.effectiveRestSeconds(
                      settings.defaultRestSeconds)),
          onSkip: () => setState(() {
            _skipped[item.sessionExercise.id] = {...skipped, pos};
          }),
        ));
        continue;
      }
      // Pending (not yet active) row — show its planned default.
      final pPreview = pendingFor(pos);
      rows.add(SetRow(
        setIndex: pos,
        entry: null,
        reps: pPreview.reps,
        weightKg: pPreview.weight,
        rpe: pPreview.rpe,
        incrementKg: increment,
        state: SetRowState.pending,
        useRir: settings.useRirInsteadOfRpe,
        onRepsChanged: (_) {},
        onWeightChanged: (_) {},
        onRpeChanged: (_) {},
        onValidate: () {},
        onSkip: () => setState(() {
          _skipped[item.sessionExercise.id] = {...skipped, pos};
        }),
      ));
    }

    final allDone = !firstActiveAssigned;
    final allExercisesDone = items.every((it) {
      final saved = it.sets.length;
      final skipped =
          (_skipped[it.sessionExercise.id] ?? const <int>{}).length;
      return saved + skipped >= 3;
    });

    final supersetGroupId = item.sessionExercise.supersetGroupId;
    final partners = supersetGroupId == null
        ? const <SessionExerciseWithSets>[]
        : items
            .where((it) =>
                it.sessionExercise.id != item.sessionExercise.id &&
                it.sessionExercise.supersetGroupId == supersetGroupId)
            .toList();

    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (supersetGroupId != null) _SupersetBanner(
          partnerCount: partners.length,
          onLeave: () => _leaveSuperset(item),
        ),
        // Exercise header: photo + name + actions, all in one cohesive row.
        _ExerciseHeader(
          exercise: exercise,
          onSwap: () => _openSwap(item, index),
          onSuperset: index > 0
              ? () => _toggleSupersetWithPrevious(items, index)
              : null,
          isSuperset: supersetGroupId != null,
          photoFuture: exercise.photoPath == null
              ? null
              : ref.read(photoStorageProvider).resolve(exercise.photoPath),
          onPhotoTap: _showFullPhoto,
        ),
        const SizedBox(height: 14),
        // Plan / Target presented as a tonal card with chips.
        _PlanCard(
          plan: plan,
          target: target,
          formatWeight: _fmt,
          formatPlanLine: _planLine,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetaChip(
              icon: Icons.timer_outlined,
              label: _formatRest(item.sessionExercise.restSeconds ??
                  exercise.effectiveRestSeconds(settings.defaultRestSeconds)),
              accent: item.sessionExercise.restSeconds != null,
              onTap: () => _editRestSeconds(item, exercise, settings),
            ),
            if (exercise.machineSettings != null &&
                exercise.machineSettings!.isNotEmpty)
              _MetaChip(
                icon: Icons.tune_rounded,
                label: exercise.machineSettings!,
                maxWidth: 240,
              ),
          ],
        ),
        const SizedBox(height: 14),
        // Sets card with strong visual segmentation per state.
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(AppTokens.radiusL),
            border: Border.all(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) rows[i],
              if (allDone) Container(
                color: AppTokens.successGreen.withOpacity(0.10),
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 20, color: AppTokens.successGreen),
                    const SizedBox(width: 8),
                    Text(
                      '$savedCount série${savedCount > 1 ? 's' : ''} '
                      'effectuée${savedCount > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: AppTokens.successGreen,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (index > 0)
              _PrevExerciseButton(
                previousExerciseId:
                    items[index - 1].sessionExercise.exerciseId,
                onPressed: () => _pageCtrl.previousPage(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                ),
              ),
            const Spacer(),
            if (index < items.length - 1)
              _NextExerciseButton(
                nextExerciseId:
                    items[index + 1].sessionExercise.exerciseId,
                onPressed: () => _pageCtrl.nextPage(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                ),
              ),
          ],
        ),
        if (allExercisesDone) ...[
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 68,
            child: FilledButton.icon(
              onPressed: _finish,
              icon: const Icon(Icons.flag_rounded, size: 22),
              label: const Text(
                'TERMINER LA SÉANCE',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: cs.tertiary,
                foregroundColor: cs.onTertiary,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppTokens.radiusM),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Future<void> _validateSet(SessionExerciseWithSets item, _Pending p,
      UserSettings settings, int targetSets,
      {required int setPos, int? restSeconds}) async {
    final restElapsed =
        _restCtrl.captureAndStart(restSeconds ?? settings.defaultRestSeconds);
    HapticFeedback.lightImpact();
    final entry = SetEntry(
      id: _uuid.v4(),
      sessionExerciseId: item.sessionExercise.id,
      setIndex: item.sets.length,
      reps: p.reps,
      weightKg: p.weight,
      rpe: p.rpe,
      restSeconds: restElapsed,
      completedAt: DateTime.now(),
    );
    await ref.read(sessionRepositoryProvider).upsertSet(entry);
    // Drop the pending override for this set so the next active row picks
    // its plan-derived default — needed for schemes like 7+6 reps.
    setState(() {
      _pending[item.sessionExercise.id]?.remove(setPos);
    });
  }

  Future<void> _editExisting(SetEntry entry) async {
    final updated = await showModalBottomSheet<SetEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditSetSheet(entry: entry),
    );
    if (updated != null) {
      await ref.read(sessionRepositoryProvider).upsertSet(updated);
    }
  }

  Future<void> _openSwap(SessionExerciseWithSets item, int index) async {
    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuickSwapSheet(
        currentExerciseId: item.sessionExercise.exerciseId,
      ),
    );
    if (picked == null) return;
    final repo = ref.read(sessionRepositoryProvider);
    if (item.sets.isEmpty) {
      await repo.deleteSessionExercise(item.sessionExercise.id);
      await addExerciseToSession(
        ref: ref,
        sessionId: widget.sessionId,
        exerciseId: picked.id,
        orderIndex: item.sessionExercise.orderIndex,
      );
    } else {
      // Keep old, insert new just after.
      await addExerciseToSession(
        ref: ref,
        sessionId: widget.sessionId,
        exerciseId: picked.id,
        orderIndex: item.sessionExercise.orderIndex + 1,
        replacedFromSessionExerciseId: item.sessionExercise.id,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exercice substitué : ${picked.name}')),
      );
    }
  }

  Future<void> _addExerciseFreestyle(int defaultIndex) async {
    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const QuickSwapSheet(),
    );
    if (picked == null) return;
    final detail =
        await ref.read(sessionRepositoryProvider).getDetail(widget.sessionId);
    final order = detail?.exercises.length ?? 0;
    await addExerciseToSession(
      ref: ref,
      sessionId: widget.sessionId,
      exerciseId: picked.id,
      orderIndex: order,
    );
  }

  Future<void> _toggleSupersetWithPrevious(
      List<SessionExerciseWithSets> items, int index) async {
    if (index <= 0) return;
    final repo = ref.read(sessionRepositoryProvider);
    final current = items[index].sessionExercise;
    final prev = items[index - 1].sessionExercise;
    // Use the previous exo's group if it has one, else create a new uuid.
    final groupId = prev.supersetGroupId ?? _uuid.v4();
    if (prev.supersetGroupId == null) {
      await repo.upsertSessionExercise(
          prev.copyWith(supersetGroupId: groupId));
    }
    await repo.upsertSessionExercise(
        current.copyWith(supersetGroupId: groupId));
  }

  Future<void> _leaveSuperset(SessionExerciseWithSets item) async {
    final repo = ref.read(sessionRepositoryProvider);
    await repo.upsertSessionExercise(item.sessionExercise
        .copyWith(clearSupersetGroupId: true));
  }

  Future<void> _editSessionNote() async {
    final repo = ref.read(sessionRepositoryProvider);
    final detail = await repo.getDetail(widget.sessionId);
    if (detail == null || !mounted) return;
    final controller =
        TextEditingController(text: detail.session.notes ?? '');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Note de séance',
                  style: Theme.of(sheetCtx).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Sommeil, fatigue, douleurs, sensations…',
                style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(sheetCtx)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "Ex: bien dormi, pas mal au dos cette fois",
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(sheetCtx, controller.text.trim()),
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    final updated = detail.session.copyWith(
      notes: result.isEmpty ? null : result,
      clearNotes: result.isEmpty,
      updatedAt: DateTime.now(),
    );
    await repo.upsertSession(updated);
  }

  Future<void> _finish() async {
    final repo = ref.read(sessionRepositoryProvider);
    final detail = await repo.getDetail(widget.sessionId);
    if (detail == null) return;
    // Manual past-session entries already have an endedAt baked in — keep
    // it so the duration reflects when the user actually trained.
    final endedAt = detail.session.endedAt ?? DateTime.now();
    final updated = detail.session.copyWith(
      endedAt: endedAt,
      updatedAt: DateTime.now(),
    );
    await repo.upsertSession(updated);
    // Fire-and-forget cloud backup so the just-finished workout is safe even
    // if the app is killed before the periodic sync runs.
    unawaited(ref.read(syncServiceProvider).sync());
    if (mounted) {
      context.go('/home');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Séance terminée 💪')),
      );
    }
  }

  Future<void> _showFullPhoto(File f) async {
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(child: Image.file(f)),
      ),
    );
  }

  Future<_ExitAction?> _confirmExit(BuildContext context) async {
    return showModalBottomSheet<_ExitAction>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.pause_circle_outline),
              title: const Text('Mettre en pause'),
              subtitle: const Text(
                  'Reprenez plus tard depuis l\'accueil. Aucune perte.'),
              onTap: () => Navigator.pop(context, _ExitAction.pause),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Terminer la séance'),
              subtitle: const Text('La séance est sauvegardée comme finie.'),
              onTap: () => Navigator.pop(context, _ExitAction.finish),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Annuler'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  String _planLine(List<TemplateExerciseSet> plan) {
    if (plan.isEmpty) return '—';
    final allSame = plan.every((s) =>
        s.plannedReps == plan.first.plannedReps &&
        s.plannedWeightKg == plan.first.plannedWeightKg);
    if (allSame) {
      final w = plan.first.plannedWeightKg;
      return '${plan.length}×${plan.first.plannedReps}'
          '${w == null ? '' : ' @ ${_fmt(w)}kg'}';
    }
    return plan
        .map((s) => '${s.plannedReps}'
            '${s.plannedWeightKg == null ? '' : '×${_fmt(s.plannedWeightKg!)}'}')
        .join(', ');
  }

  /// Renders the kg cell for bodyweight exercises. Returns "BW + 10kg" if the
  /// user set their bodyweight, else "+10kg".
  String _bodyweightLabel(double addedKg, UserSettings settings) {
    final added = addedKg == 0
        ? '0kg'
        : (addedKg > 0 ? '+${_fmt(addedKg)}kg' : '${_fmt(addedKg)}kg');
    final bw = settings.userBodyweightKg;
    if (bw == null) return added;
    final total = bw + addedKg;
    return '$added (${_fmt(total)}kg)';
  }

  String _formatRest(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}min' : '${m}min ${s}s';
  }

  Future<void> _editRestSeconds(
    SessionExerciseWithSets item,
    Exercise exercise,
    UserSettings settings,
  ) async {
    final initial = item.sessionExercise.restSeconds ??
        exercise.effectiveRestSeconds(settings.defaultRestSeconds);
    final result = await showModalBottomSheet<_RestEditResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RestEditSheet(
        initialSeconds: initial,
        isOverridden: item.sessionExercise.restSeconds != null,
        defaultSeconds:
            exercise.effectiveRestSeconds(settings.defaultRestSeconds),
      ),
    );
    if (result == null) return;
    final updated = item.sessionExercise.copyWith(
      restSeconds: result.reset ? null : result.seconds,
      clearRestSeconds: result.reset,
    );
    await ref.read(sessionRepositoryProvider).upsertSessionExercise(updated);
  }
}

class _PrevExerciseButton extends ConsumerWidget {
  final String previousExerciseId;
  final VoidCallback onPressed;
  const _PrevExerciseButton({
    required this.previousExerciseId,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exAsync = ref.watch(exerciseByIdProvider(previousExerciseId));
    final name = exAsync.valueOrNull?.name ?? 'Précédent';
    return _NavExerciseButton(
      label: name,
      icon: Icons.chevron_left_rounded,
      iconLeading: true,
      onPressed: onPressed,
    );
  }
}

class _NextExerciseButton extends ConsumerWidget {
  final String nextExerciseId;
  final VoidCallback onPressed;
  const _NextExerciseButton({
    required this.nextExerciseId,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exAsync = ref.watch(exerciseByIdProvider(nextExerciseId));
    final name = exAsync.valueOrNull?.name ?? 'Suivant';
    return _NavExerciseButton(
      label: name,
      icon: Icons.chevron_right_rounded,
      iconLeading: false,
      onPressed: onPressed,
    );
  }
}

class _NavExerciseButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool iconLeading;
  final VoidCallback onPressed;
  const _NavExerciseButton({
    required this.label,
    required this.icon,
    required this.iconLeading,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconWidget = Icon(icon, size: 20, color: cs.primary);
    final textWidget = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: TextStyle(
          color: cs.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppTokens.radiusM),
      child: Container(
        height: AppTokens.tapTarget,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: iconLeading
              ? [iconWidget, const SizedBox(width: 6), textWidget]
              : [textWidget, const SizedBox(width: 6), iconWidget],
        ),
      ),
    );
  }
}

class _SupersetBanner extends StatelessWidget {
  final int partnerCount;
  final VoidCallback onLeave;
  const _SupersetBanner({required this.partnerCount, required this.onLeave});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        border: Border.all(color: cs.secondary.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 18, color: cs.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Superset · enchaîne avec ' +
                  (partnerCount == 1 ? 'cet exo' : '$partnerCount exos'),
              style: TextStyle(
                color: cs.onSecondaryContainer,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          TextButton(
            onPressed: onLeave,
            style: TextButton.styleFrom(foregroundColor: cs.secondary),
            child: const Text('Détacher'),
          ),
        ],
      ),
    );
  }
}

class _ExerciseHeader extends StatelessWidget {
  final Exercise exercise;
  final VoidCallback onSwap;
  final VoidCallback? onSuperset;
  final bool isSuperset;
  final Future<File?>? photoFuture;
  final ValueChanged<File> onPhotoTap;
  const _ExerciseHeader({
    required this.exercise,
    required this.onSwap,
    required this.onSuperset,
    required this.isSuperset,
    required this.photoFuture,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (photoFuture != null)
          FutureBuilder<File?>(
            future: photoFuture,
            builder: (_, snap) {
              if (snap.data == null) {
                return Container(
                  width: 56,
                  height: 56,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTokens.radiusM),
                  ),
                  child: Icon(Icons.fitness_center,
                      size: 22, color: cs.onSurfaceVariant),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => onPhotoTap(snap.data!),
                  child: Hero(
                    tag: 'exo-photo-${exercise.id}',
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusM),
                      child: Image.file(
                        snap.data!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onLongPress: onSwap,
                child: Text(
                  exercise.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _muscleLabel(exercise),
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.swap_horiz_rounded),
          tooltip: 'Substituer',
          onPressed: onSwap,
          style: IconButton.styleFrom(
            backgroundColor: cs.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusS),
            ),
          ),
        ),
        if (onSuperset != null) ...[
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              Icons.link_rounded,
              color: isSuperset ? cs.secondary : null,
            ),
            tooltip: isSuperset
                ? "Étendre le superset à l'exo précédent"
                : "Mettre en superset avec l'exo précédent",
            onPressed: onSuperset,
            style: IconButton.styleFrom(
              backgroundColor: cs.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusS),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _muscleLabel(Exercise ex) {
    final m = ex.primaryMuscle.name;
    final eq = ex.equipment.name;
    return '${_pretty(m)} · ${_pretty(eq)}';
  }

  String _pretty(String enumName) {
    if (enumName.isEmpty) return enumName;
    final firstLetter = enumName[0].toUpperCase();
    final rest = enumName.substring(1).replaceAllMapped(
        RegExp(r'[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}');
    return firstLetter + rest;
  }
}

class _PlanCard extends StatelessWidget {
  final List<TemplateExerciseSet> plan;
  final ProgressionTarget target;
  final String Function(double) formatWeight;
  final String Function(List<TemplateExerciseSet>) formatPlanLine;
  const _PlanCard({
    required this.plan,
    required this.target,
    required this.formatWeight,
    required this.formatPlanLine,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPlan = plan.isNotEmpty;
    final title = hasPlan ? 'PLAN' : 'CIBLE';
    final body = hasPlan
        ? formatPlanLine(plan)
        : '${target.targetSets}×${target.targetReps} @ '
            '${formatWeight(target.targetWeightKg)} kg'
            '${target.targetRpe != null ? ' · RPE ${target.targetRpe}' : ''}';
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: hasPlan ? cs.secondary : cs.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (!hasPlan && target.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              target.reason,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final double? maxWidth;
  final VoidCallback? onTap;
  const _MetaChip({
    required this.icon,
    required this.label,
    this.accent = false,
    this.maxWidth,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = accent ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusS),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: accent
              ? cs.primary.withOpacity(0.10)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
          border: Border.all(
            color: accent
                ? cs.primary.withOpacity(0.4)
                : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int current;
  const _PageDots({required this.count, required this.current});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: i == current ? 18 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == current
                    ? cs.primary
                    : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

enum _ExitAction { pause, finish }

class _Pending {
  final int reps;
  final double weight;
  final int? rpe;
  const _Pending({required this.reps, required this.weight, this.rpe});
  _Pending copyWith({int? reps, double? weight, int? rpe}) => _Pending(
        reps: reps ?? this.reps,
        weight: weight ?? this.weight,
        rpe: rpe ?? this.rpe,
      );
}

class _RestEditResult {
  final int seconds;
  final bool reset;
  const _RestEditResult({required this.seconds, this.reset = false});
}

class _RestEditSheet extends StatefulWidget {
  final int initialSeconds;
  final bool isOverridden;
  final int defaultSeconds;
  const _RestEditSheet({
    required this.initialSeconds,
    required this.isOverridden,
    required this.defaultSeconds,
  });
  @override
  State<_RestEditSheet> createState() => _RestEditSheetState();
}

class _RestEditSheetState extends State<_RestEditSheet> {
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _seconds = widget.initialSeconds;
  }

  String _format(int s) {
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? '${m}min' : '${m}min ${r}s';
  }

  void _adjust(int delta) {
    setState(() {
      _seconds = (_seconds + delta).clamp(0, 60 * 30);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Repos pour cet exercice',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Par défaut : ${_format(widget.defaultSeconds)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FilledButton.tonal(
                  onPressed: () => _adjust(-30),
                  child: const Text('-30s'),
                ),
                FilledButton.tonal(
                  onPressed: () => _adjust(-15),
                  child: const Text('-15s'),
                ),
                Text(
                  _format(_seconds),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                FilledButton.tonal(
                  onPressed: () => _adjust(15),
                  child: const Text('+15s'),
                ),
                FilledButton.tonal(
                  onPressed: () => _adjust(30),
                  child: const Text('+30s'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (final preset in const [60, 90, 120, 150, 180, 240, 300])
                  ChoiceChip(
                    label: Text(_format(preset)),
                    selected: _seconds == preset,
                    onSelected: (_) => setState(() => _seconds = preset),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.isOverridden)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        const _RestEditResult(seconds: 0, reset: true),
                      ),
                      child: const Text('Réinitialiser'),
                    ),
                  ),
                if (widget.isOverridden) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _RestEditResult(seconds: _seconds),
                    ),
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditSetSheet extends StatefulWidget {
  final SetEntry entry;
  const _EditSetSheet({required this.entry});
  @override
  State<_EditSetSheet> createState() => _EditSetSheetState();
}

class _EditSetSheetState extends State<_EditSetSheet> {
  late TextEditingController repsCtrl;
  late TextEditingController weightCtrl;
  late TextEditingController rpeCtrl;

  @override
  void initState() {
    super.initState();
    repsCtrl = TextEditingController(text: widget.entry.reps.toString());
    weightCtrl =
        TextEditingController(text: widget.entry.weightKg.toString());
    rpeCtrl = TextEditingController(text: widget.entry.rpe?.toString() ?? '');
  }

  @override
  void dispose() {
    repsCtrl.dispose();
    weightCtrl.dispose();
    rpeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Série ${widget.entry.setIndex + 1}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: repsCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Reps', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Poids (kg)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: rpeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'RPE', border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final reps = int.tryParse(repsCtrl.text) ?? widget.entry.reps;
                final w = double.tryParse(weightCtrl.text) ??
                    widget.entry.weightKg;
                final rpe =
                    rpeCtrl.text.isEmpty ? null : int.tryParse(rpeCtrl.text);
                Navigator.pop(
                  context,
                  widget.entry.copyWith(
                    reps: reps,
                    weightKg: w,
                    rpe: rpe,
                    clearRpe: rpe == null,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
