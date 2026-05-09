import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/progression_target.dart';
import '../../domain/models/session.dart';
import '../../domain/models/user_settings.dart';
import '../../domain/models/workout_template.dart';
import '../../domain/progression/progression_engine.dart';
import 'edit_set_sheet.dart';
import 'pending_set.dart';
import 'quick_swap_sheet.dart';
import 'rest_edit_sheet.dart';
import 'rest_timer.dart';
import 'set_row.dart';
import 'start_session_controller.dart';
import 'widgets/exercise_header.dart';
import 'widgets/meta_chip.dart';
import 'widgets/nav_exercise_buttons.dart';
import 'widgets/page_dots.dart';
import 'widgets/plan_card.dart';
import 'widgets/session_note_banner.dart';
import 'widgets/superset_banner.dart';

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
  final Map<String, Map<int, PendingSet>> _pending = {};
  // skipped absolute set positions per session-exercise (UI-only).
  final Map<String, Set<int>> _skipped = {};
  // Plan from the template, indexed by exerciseId → list of planned sets
  // (sorted by setIndex). Empty list = no template plan (freestyle session).
  Map<String, List<TemplateExerciseSet>> _planByExercise = const {};
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
    if (!mounted) return;
    setState(() {
      _planByExercise = planMap;
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
        } else if (action == _ExitAction.abandon && context.mounted) {
          if (await _confirmAbandon()) await _abandonSession();
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
        if ((session.notes ?? '').isNotEmpty)
          SessionNoteBanner(
            note: session.notes!,
            onTap: _editSessionNote,
          ),
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (_, i) => _exercisePage(items, i, settings),
          ),
        ),
        if (items.length > 1)
          PageDots(count: items.length, current: _currentPage.clamp(0, items.length - 1)),
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
              } else if (action == _ExitAction.abandon && mounted) {
                if (await _confirmAbandon()) await _abandonSession();
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
            // Source de vérité pour le nombre de séries planifiées :
            // 1. le template s'il existe (plan.length)
            // 2. sinon ce que l'utilisateur a déjà saisi (item.sets.length)
            // 3. fallback à 3 (séance freestyle vierge).
            final templatePlan =
                _planByExercise[item.sessionExercise.exerciseId] ?? const [];
            final plannedSets = templatePlan.isNotEmpty
                ? templatePlan.length
                : (item.sets.length >= 3 ? item.sets.length : 3);
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

    // The template plan stores the weights at the moment the user designed
    // it — once progressive overload kicks in, those numbers are stale.
    // Rebase the plan onto the engine's target so the PLAN card shows what
    // the user will actually do today (e.g. 4×8 @ 49kg, not @ 44kg).
    final displayPlan = plan.isEmpty
        ? const <TemplateExerciseSet>[]
        : [
            for (final s in plan)
              s.copyWith(
                plannedReps: target.targetReps,
                plannedWeightKg: target.targetWeightKg,
              ),
          ];

    /// Valeurs par défaut de chaque série :
    ///   1. si une série précédente a déjà été validée dans cette séance,
    ///      on reprend ses reps/poids — l'utilisateur n'a qu'à saisir une
    ///      fois s'il dévie du target (ex. plan à 40kg mais il fait 60kg,
    ///      les séries 2/3/4 doivent défaulter à 60kg, pas rester à 40kg) ;
    ///   2. sinon on retombe sur le moteur de surcharge progressive (target).
    /// Le plan du template ne sert que pour la STRUCTURE (nombre de séries) ;
    /// ses reps/poids planifiés ne sont pas re-imposés à chaque séance,
    /// sinon la progression serait gelée.
    PendingSet defaultFor(int pos) {
      final lastValidated = item.sets.where((s) => !s.isWarmup).toList();
      if (lastValidated.isNotEmpty) {
        final last = lastValidated.last;
        return PendingSet(
          reps: last.reps,
          weight: last.weightKg,
          rpe: null,
        );
      }
      return PendingSet(
        reps: target.targetReps,
        weight: target.targetWeightKg,
        rpe: null,
      );
    }

    /// Returns the (possibly user-edited) values for a given set position.
    PendingSet pendingFor(int pos) =>
        _pending[item.sessionExercise.id]?[pos] ?? defaultFor(pos);

    void setPendingFor(int pos, PendingSet p) {
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
        if (supersetGroupId != null) SupersetBanner(
          partnerCount: partners.length,
          onLeave: () => _leaveSuperset(item),
        ),
        // Exercise header: photo + name + actions, all in one cohesive row.
        ExerciseHeader(
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
        PlanCard(
          plan: displayPlan,
          target: target,
          formatWeight: fmtKg,
          formatPlanLine: _planLine,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MetaChip(
              icon: Icons.timer_outlined,
              label: fmtRest(item.sessionExercise.restSeconds ??
                  exercise.effectiveRestSeconds(settings.defaultRestSeconds)),
              accent: item.sessionExercise.restSeconds != null,
              onTap: () => _editRestSeconds(item, exercise, settings),
            ),
            if (exercise.machineSettings != null &&
                exercise.machineSettings!.isNotEmpty)
              MetaChip(
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
              PrevExerciseButton(
                previousExerciseId:
                    items[index - 1].sessionExercise.exerciseId,
                onPressed: () => _pageCtrl.previousPage(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                ),
              ),
            const Spacer(),
            if (index < items.length - 1)
              NextExerciseButton(
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

  Future<void> _validateSet(SessionExerciseWithSets item, PendingSet p,
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
    final repo = ref.read(sessionRepositoryProvider);
    await repo.upsertSet(entry);
    // Drop the pending override for this set so the next active row picks
    // its plan-derived default — needed for schemes like 7+6 reps.
    setState(() {
      _pending[item.sessionExercise.id]?.remove(setPos);
    });
    // Ratchet: if this session was started from a template, sync the
    // validated set's reps/weight back into the template so the user
    // sees the latest progression next time they look at it or start
    // another session from the same template.
    final detail = await repo.getDetail(widget.sessionId);
    final templateId = detail?.session.templateId;
    if (templateId != null) {
      await ref.read(templateRepositoryProvider).applyValidatedSet(
            templateId: templateId,
            exerciseId: item.sessionExercise.exerciseId,
            reps: entry.reps,
            weightKg: entry.weightKg,
          );
    }
  }

  Future<void> _editExisting(SetEntry entry) async {
    final updated = await showModalBottomSheet<SetEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditSetSheet(entry: entry),
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
    // Refuser de terminer une séance dans laquelle aucune série n'a été
    // validée — sinon l'historique se remplit de séances vides.
    final hasAnyWorkingSet = detail.exercises
        .any((e) => e.sets.any((s) => !s.isWarmup));
    final isManualEntry = detail.session.endedAt != null;
    if (!hasAnyWorkingSet && !isManualEntry) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Valide au moins une série avant de terminer la séance')),
      );
      return;
    }
    // Manual past-session entries already have an endedAt baked in — keep
    // it so the duration reflects when the user actually trained.
    final endedAt = detail.session.endedAt ?? DateTime.now();
    final updated = detail.session.copyWith(
      endedAt: endedAt,
      updatedAt: DateTime.now(),
    );
    await repo.upsertSession(updated);
    // Push session + its exercises + sets synchronously so the
    // just-finished workout is safe on the cloud before the user can
    // reinstall, kill the app, or lose the device. The periodic sync
    // would also push, but it's not guaranteed to run in time.
    try {
      await ref
          .read(syncServiceProvider)
          .pushSessionWithChildren(widget.sessionId);
    } catch (_) {/* best-effort; the periodic sync will retry */}
    // Background full sync for everything else (settings, bodyweight…).
    unawaited(ref.read(syncServiceProvider).sync());
    if (mounted) {
      context.go('/home');
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
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Abandonner la séance'),
              subtitle: const Text(
                  'Supprime cette séance et tout ce qui a été saisi.'),
              onTap: () => Navigator.pop(context, _ExitAction.abandon),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.arrow_back_rounded),
              title: const Text('Continuer la séance'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmAbandon() async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Abandonner la séance ?'),
            content: const Text(
                "Toutes les séries saisies seront perdues. Cette action est irréversible."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Abandonner'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _abandonSession() async {
    final repo = ref.read(sessionRepositoryProvider);
    await repo.softDeleteSession(widget.sessionId);
    if (mounted) {
      context.go('/home');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Séance abandonnée')),
      );
    }
  }

  String _planLine(List<TemplateExerciseSet> plan) {
    if (plan.isEmpty) return '—';
    final allSame = plan.every((s) =>
        s.plannedReps == plan.first.plannedReps &&
        s.plannedWeightKg == plan.first.plannedWeightKg);
    if (allSame) {
      final w = plan.first.plannedWeightKg;
      return '${plan.length}×${plan.first.plannedReps}'
          '${w == null ? '' : ' @ ${fmtKg(w)}kg'}';
    }
    return plan
        .map((s) => '${s.plannedReps}'
            '${s.plannedWeightKg == null ? '' : '×${fmtKg(s.plannedWeightKg!)}'}')
        .join(', ');
  }

  /// Renders the kg cell for bodyweight exercises. Returns "BW + 10kg" if the
  /// user set their bodyweight, else "+10kg".
  String _bodyweightLabel(double addedKg, UserSettings settings) {
    final added = addedKg == 0
        ? '0kg'
        : (addedKg > 0 ? '+${fmtKg(addedKg)}kg' : '${fmtKg(addedKg)}kg');
    final bw = settings.userBodyweightKg;
    if (bw == null) return added;
    final total = bw + addedKg;
    return '$added (${fmtKg(total)}kg)';
  }

  Future<void> _editRestSeconds(
    SessionExerciseWithSets item,
    Exercise exercise,
    UserSettings settings,
  ) async {
    final initial = item.sessionExercise.restSeconds ??
        exercise.effectiveRestSeconds(settings.defaultRestSeconds);
    final result = await showModalBottomSheet<RestEditResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RestEditSheet(
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


enum _ExitAction { pause, finish, abandon }

