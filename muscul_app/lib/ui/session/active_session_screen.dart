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
import '../../core/utils/one_rep_max.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/sync/sync_service.dart';
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
import 'set_prefill.dart';
import 'set_row.dart';
import 'start_session_controller.dart';
import 'widgets/exercise_header.dart';
import 'widgets/meta_chip.dart';
import 'widgets/nav_exercise_buttons.dart';
import 'widgets/page_dots.dart';
import 'widgets/plan_card.dart';
import 'widgets/session_note_banner.dart';

const _uuid = Uuid();

class ActiveSessionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const ActiveSessionScreen({super.key, required this.sessionId});

  @override
  ConsumerState<ActiveSessionScreen> createState() =>
      _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends ConsumerState<ActiveSessionScreen>
    with WidgetsBindingObserver {
  final _restCtrl = RestTimerController();
  final _pageCtrl = PageController();
  // User adjustments per session-exercise per set position. Keyed
  // [exerciseSessionId][setIndex] → pending values. Cleared after validate
  // so the next set uses its own plan-derived default.
  final Map<String, Map<int, PendingSet>> _pending = {};
  // skipped absolute set positions per session-exercise (UI-only).
  final Map<String, Set<int>> _skipped = {};
  // Extra set slots the user added on the fly via the "+" next to the dots,
  // per session-exercise (UI-only — a slot becomes a real set once validated).
  final Map<String, int> _extraSlots = {};
  // Plan from the template, indexed by exerciseId → list of planned sets
  // (sorted by setIndex). Empty list = no template plan (freestyle session).
  Map<String, List<TemplateExerciseSet>> _planByExercise = const {};
  Timer? _sessionTicker;
  Duration _elapsed = Duration.zero;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => _refreshElapsed());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPlan();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timers are derived from wall-clock timestamps, but the OS suspends our
    // periodic ticks while backgrounded — recompute both as soon as we're
    // back so the elapsed time and rest countdown are immediately accurate.
    if (state == AppLifecycleState.resumed) {
      _refreshElapsed();
      _restCtrl.refresh();
    }
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
    WidgetsBinding.instance.removeObserver(this);
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
            // The engine produces a real prescription only when there's at
            // least one past session with working sets — same condition it
            // uses internally. Below that, target is just the starting weight.
            final hasHistory =
                pastHistory.any((h) => h.sets.any((s) => !s.isWarmup));
            return _exerciseBody(
              items: items,
              index: index,
              item: item,
              exercise: exercise,
              target: target,
              hasHistory: hasHistory,
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
    required bool hasHistory,
    required UserSettings settings,
  }) {
    final plan = _planByExercise[item.sessionExercise.exerciseId] ?? const [];

    // Valeurs par défaut d'une série — logique pure et testée dans
    // set_prefill.dart (voir computeSetDefault pour la priorité exacte).
    PendingSet defaultFor(int pos) => computeSetDefault(
          pos: pos,
          sessionSets: item.sets,
          hasHistory: hasHistory,
          plan: plan,
          target: target,
        );

    /// Returns the (possibly user-edited) values for a given set position.
    PendingSet pendingFor(int pos) =>
        _pending[item.sessionExercise.id]?[pos] ?? defaultFor(pos);

    void setPendingFor(int pos, PendingSet p) {
      _pending.putIfAbsent(item.sessionExercise.id, () => {})[pos] = p;
    }

    final skipped = _skipped[item.sessionExercise.id] ?? <int>{};
    final savedCount = item.sets.length;
    final extraSlots = _extraSlots[item.sessionExercise.id] ?? 0;
    // Plan length is the canonical "target sets" when a plan exists.
    final plannedCount = plan.isNotEmpty ? plan.length : target.targetSets;
    // Base = plan (min 3 for freestyle) + the sets the user explicitly added
    // with the "+". We never spawn a fresh empty set just because the previous
    // one was validated — extra sets are added on demand only. We still widen
    // to fit every already-saved/skipped set so nothing gets hidden.
    final baseSlots =
        [plannedCount, 3].reduce((a, b) => a > b ? a : b) + extraSlots;
    final totalSlots = baseSlots > savedCount + skipped.length
        ? baseSlots
        : savedCount + skipped.length;

    // Classify every slot. The whole set sequence is now shown as a single
    // strip of dots — validated sets are a green check (tap to edit), skipped
    // a dash (tap to restore), the in-progress one is ringed, upcoming ones
    // hollow. No per-set rows anymore; only the in-progress set gets the
    // stepper card below the strip.
    final slotStates = <SetRowState>[];
    final slotTaps = <VoidCallback?>[];
    var activePos = -1;
    {
      var consumed = 0;
      for (var pos = 0; pos < totalSlots; pos++) {
        if (skipped.contains(pos)) {
          slotStates.add(SetRowState.skipped);
          final p = pos;
          slotTaps.add(() => setState(() {
                _skipped[item.sessionExercise.id] = {...skipped}..remove(p);
              }));
        } else if (consumed < savedCount) {
          final entry = item.sets[consumed++];
          slotStates.add(SetRowState.completed);
          slotTaps.add(() => _editExisting(entry));
        } else if (activePos < 0) {
          activePos = pos;
          slotStates.add(SetRowState.active);
          slotTaps.add(null);
        } else {
          slotStates.add(SetRowState.pending);
          slotTaps.add(null);
        }
      }
    }
    final progressDots = SetProgressDots(states: slotStates, taps: slotTaps);

    // Validating the active set finishes the exercise when no further set is
    // still pending after it (the user can always add one with "+"). Used to
    // auto-advance to the next exercise's page.
    final validatingFinishesExercise = activePos >= 0 &&
        !slotStates
            .skip(activePos + 1)
            .any((s) => s == SetRowState.pending);

    // The single stepper card for the set in progress (null once all done).
    Widget? activeRow;
    if (activePos >= 0) {
      final p = pendingFor(activePos);
      activeRow = SetRow(
        setIndex: activePos,
        entry: null,
        reps: p.reps,
        weightKg: p.weight,
        rpe: p.rpe,
        state: SetRowState.active,
        useRir: settings.useRirInsteadOfRpe,
        bodyweightLabel: exercise.useBodyweight
            ? _bodyweightLabel(p.weight, settings)
            : null,
        onRepsChanged: (v) => setState(() {
          setPendingFor(activePos, p.copyWith(reps: v));
        }),
        onWeightChanged: (v) => setState(() {
          setPendingFor(activePos, p.copyWith(weight: v));
        }),
        onRpeChanged: (v) => setState(() {
          setPendingFor(activePos, p.copyWith(rpe: v));
        }),
        onValidate: () async {
          await _validateSet(
            item, p, settings, plannedCount,
            setPos: activePos,
            restSeconds: item.sessionExercise.restSeconds ??
                exercise.effectiveRestSeconds(settings.defaultRestSeconds),
          );
          // Dernière série de l'exo validée → on enchaîne automatiquement sur
          // l'exo suivant (s'il y en a un).
          if (validatingFinishesExercise &&
              index < items.length - 1 &&
              mounted &&
              _pageCtrl.hasClients) {
            _pageCtrl.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
        onSkip: () => setState(() {
          _skipped[item.sessionExercise.id] = {...skipped, activePos};
        }),
      );
    }

    final allDone = activePos < 0;
    final allExercisesDone = items.every((it) {
      final saved = it.sets.length;
      final skipped =
          (_skipped[it.sessionExercise.id] ?? const <int>{}).length;
      return saved + skipped >= 3;
    });

    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Exercise header: photo + name + actions, all in one cohesive row.
        // Superset UI is disabled for now — pass no-op so the button hides.
        ExerciseHeader(
          exercise: exercise,
          onSwap: () => _openSwap(item, index),
          onSuperset: null,
          isSuperset: false,
          photoFuture: exercise.photoPath == null
              ? null
              : ref.read(photoStorageProvider).resolve(exercise.photoPath),
          onPhotoTap: _showFullPhoto,
        ),
        const SizedBox(height: 14),
        // Plan / Target presented as a tonal card with chips.
        PlanCard(
          plan: plan,
          target: target,
          hasHistory: hasHistory,
          formatWeight: fmtKg,
          formatPlanLine: _planLine,
          // Pas de 1RM pour le poids du corps : la charge additionnelle seule
          // ne donne pas une estimation parlante.
          oneRepMaxKg: exercise.useBodyweight
              ? null
              : estimateOneRepMax(target.targetWeightKg, target.targetReps),
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
              // Progress strip — a dot per set, the whole sequence at a glance,
              // followed by a "+" to tack on an extra set on the fly.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      progressDots,
                      const SizedBox(width: 7),
                      _AddSetButton(
                        onTap: () => setState(() {
                          _extraSlots.update(
                            item.sessionExercise.id,
                            (v) => v + 1,
                            ifAbsent: () => 1,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              if (activeRow != null) ...[
                const Divider(height: 1),
                activeRow,
              ],
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
        // Two equal-width halves so the buttons sit symmetrically and never
        // overlap, whatever the exercise names' length. An empty slot keeps
        // the lone button (first / last exo) on its own side.
        Row(
          children: [
            Expanded(
              child: index > 0
                  ? PrevExerciseButton(
                      previousExerciseId:
                          items[index - 1].sessionExercise.exerciseId,
                      onPressed: () => _pageCtrl.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: index < items.length - 1
                  ? NextExerciseButton(
                      nextExerciseId:
                          items[index + 1].sessionExercise.exerciseId,
                      onPressed: () => _pageCtrl.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                    )
                  : const SizedBox.shrink(),
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
    // Fire-and-forget the cloud push so validating a set doesn't block the
    // UI on a slow network. Local DB has the row already; the next full
    // sync (app start / login / resume) retries on failure.
    final svc = ref.read(syncServiceProvider);
    svc.pushSet(entry.id).ignore();
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
      svc.pushTemplate(templateId).ignore();
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
      ref.read(syncServiceProvider).pushSet(updated.id).ignore();
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
      final removedId = item.sessionExercise.id;
      await repo.deleteSessionExercise(removedId);
      ref
          .read(syncServiceProvider)
          .deleteSessionExerciseOnCloud(removedId)
          .ignore();
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

  // Superset feature disabled for now (new idea pending). The data plumbing
  // (model field, DB column, sync) is kept intact so existing groups survive
  // and the UI can be re-enabled later — only the entry points are gone.

  Future<void> _editSessionNote() async {
    final repo = ref.read(sessionRepositoryProvider);
    final detail = await repo.getDetail(widget.sessionId);
    if (detail == null || !mounted) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _SessionNoteSheet(initialNote: detail.session.notes ?? ''),
    );
    if (result == null) return;
    final updated = detail.session.copyWith(
      notes: result.isEmpty ? null : result,
      clearNotes: result.isEmpty,
      updatedAt: DateTime.now(),
    );
    await repo.upsertSession(updated);
    ref.read(syncServiceProvider).pushSession(updated.id).ignore();
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
    // Fire-and-forget the cloud push so finishing the session doesn't make
    // the user stare at a frozen button for 5-15s on a slow network. The
    // workout is already in local DB; the next full sync (app start /
    // login / resume) retries on failure.
    ref
        .read(syncServiceProvider)
        .pushSessionWithChildren(widget.sessionId)
        .ignore();
    // A freestyle session (no template) is often worth keeping. Offer to turn
    // what was just done into a reusable template, with a summary of the
    // sets/weights, before leaving the screen.
    String? savedTemplateName;
    if (detail.session.templateId == null && hasAnyWorkingSet && mounted) {
      savedTemplateName = await _offerSaveAsTemplate(detail);
    }
    if (!mounted) return;
    // Grab the (persistent, app-level) messenger before navigating, then show
    // the confirmation AFTER the route swap. Inserting a SnackBar and tearing
    // down this route in the same frame trips InheritedElement's
    // "_dependents.isEmpty" assertion.
    final messenger = ScaffoldMessenger.of(context);
    context.go('/home');
    if (savedTemplateName != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Template « $savedTemplateName » enregistré')),
      );
    }
  }

  /// Builds a template draft from the just-finished freestyle session and, if
  /// the user confirms (and names it), persists it and pushes it to the cloud.
  /// Returns the saved template's name (for the caller to confirm), or null if
  /// nothing was saved.
  Future<String?> _offerSaveAsTemplate(SessionDetail detail) async {
    final exRepo = ref.read(exerciseRepositoryProvider);
    final drafts = <_FreestyleDraftExercise>[];
    for (final e in detail.exercises) {
      final working = e.sets.where((s) => !s.isWarmup).toList()
        ..sort((a, b) => a.setIndex.compareTo(b.setIndex));
      if (working.isEmpty) continue;
      final ex = await exRepo.getById(e.sessionExercise.exerciseId);
      drafts.add(_FreestyleDraftExercise(
        exercise: ex,
        sessionExercise: e.sessionExercise,
        sets: working,
      ));
    }
    if (drafts.isEmpty || !mounted) return null;

    final name = await _askTemplateName(drafts);
    if (name == null || !mounted) return null;

    final templateId = _uuid.v4();
    final now = DateTime.now();
    final template = WorkoutTemplate(
      id: templateId,
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    final tewList = <TemplateExerciseWithSets>[];
    for (var i = 0; i < drafts.length; i++) {
      final d = drafts[i];
      final teId = _uuid.v4();
      tewList.add(TemplateExerciseWithSets(
        exercise: WorkoutTemplateExercise(
          id: teId,
          templateId: templateId,
          exerciseId: d.sessionExercise.exerciseId,
          orderIndex: i,
          targetSets: d.sets.length,
          restSeconds: d.sessionExercise.restSeconds,
        ),
        sets: [
          for (var j = 0; j < d.sets.length; j++)
            TemplateExerciseSet(
              id: _uuid.v4(),
              templateExerciseId: teId,
              setIndex: j,
              plannedReps: d.sets[j].reps,
              // Bodyweight exercises carry no planned load in templates.
              plannedWeightKg: (d.exercise?.useBodyweight ?? false)
                  ? null
                  : d.sets[j].weightKg,
            ),
        ],
      ));
    }
    final tplRepo = ref.read(templateRepositoryProvider);
    await tplRepo.upsertTemplate(template);
    await tplRepo.setTemplateExercises(templateId, tewList);
    ref.read(syncServiceProvider).pushTemplate(templateId).ignore();
    return name;
  }

  /// Bottom sheet: shows a per-exercise recap of what was done and asks for a
  /// template name. Returns the trimmed name, or null if the user skips.
  Future<String?> _askTemplateName(
      List<_FreestyleDraftExercise> drafts) async {
    final items = [
      for (final d in drafts)
        (name: d.exercise?.name ?? 'Exercice', summary: _draftSummaryLine(d)),
    ];
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TemplateNameSheet(
        items: items,
        initialName: 'Freestyle ${fmtDate(DateTime.now())}',
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  /// Compact recap of a draft exercise's working sets, e.g. "4×10 @ 60kg" when
  /// uniform, or "10×60, 8×60, …" when the sets differ.
  String _draftSummaryLine(_FreestyleDraftExercise d) {
    final sets = d.sets;
    final bw = d.exercise?.useBodyweight ?? false;
    final allSame = sets.every((s) =>
        s.reps == sets.first.reps && s.weightKg == sets.first.weightKg);
    if (allSame) {
      final w = sets.first.weightKg;
      return '${sets.length}×${sets.first.reps}'
          '${bw ? '' : ' @ ${fmtKg(w)}kg'}';
    }
    return sets
        .map((s) => '${s.reps}${bw ? '' : '×${fmtKg(s.weightKg)}'}')
        .join(', ');
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
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.pause_circle_outline),
              title: const Text('Mettre en pause'),
              subtitle: const Text(
                  'Reprenez plus tard depuis l\'accueil. Aucune perte.'),
              onTap: () => Navigator.pop(sheetCtx, _ExitAction.pause),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Terminer la séance'),
              subtitle: const Text('La séance est sauvegardée comme finie.'),
              onTap: () => Navigator.pop(sheetCtx, _ExitAction.finish),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Abandonner la séance'),
              subtitle: const Text(
                  'Supprime cette séance et tout ce qui a été saisi.'),
              onTap: () => Navigator.pop(sheetCtx, _ExitAction.abandon),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.arrow_back_rounded),
              title: const Text('Continuer la séance'),
              onTap: () => Navigator.pop(sheetCtx),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmAbandon() async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Abandonner la séance ?'),
            content: const Text(
                "Toutes les séries saisies seront perdues. Cette action est irréversible."),
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
    ref.read(syncServiceProvider).pushSession(widget.sessionId).ignore();
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
    ref.read(syncServiceProvider).pushSessionExercise(updated.id).ignore();
  }
}


enum _ExitAction { pause, finish, abandon }

/// Bottom sheet asking for a template name with a recap of the freestyle
/// session. A dedicated StatefulWidget so the [TextEditingController] lives
/// exactly as long as the sheet and is disposed in [dispose] — disposing it
/// inline right after `showModalBottomSheet` returns crashes, because the exit
/// transition still rebuilds the TextField with the now-dead controller.
class _TemplateNameSheet extends StatefulWidget {
  final List<({String name, String summary})> items;
  final String initialName;
  const _TemplateNameSheet({required this.items, required this.initialName});

  @override
  State<_TemplateNameSheet> createState() => _TemplateNameSheetState();
}

class _TemplateNameSheetState extends State<_TemplateNameSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ajouter aux templates',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Réutilise cette séance freestyle quand tu veux.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppTokens.radiusM),
                  border: Border.all(color: cs.outlineVariant),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final it in widget.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              it.summary,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Nom du template',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Plus tard'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, _controller.text.trim()),
                      child: const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet to edit the session note. Owns its [TextEditingController] so
/// it's disposed only when the sheet is truly gone (not right after the modal
/// future resolves, which still runs the exit animation over the field).
class _SessionNoteSheet extends StatefulWidget {
  final String initialNote;
  const _SessionNoteSheet({required this.initialNote});

  @override
  State<_SessionNoteSheet> createState() => _SessionNoteSheetState();
}

class _SessionNoteSheetState extends State<_SessionNoteSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _controller.dispose();
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Note de séance',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Sommeil, fatigue, douleurs, sensations…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Ex: bien dormi, pas mal au dos cette fois",
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, _controller.text.trim()),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One exercise of a freestyle session being turned into a template: its
/// (possibly null) catalog entry plus the working sets actually performed.
class _FreestyleDraftExercise {
  final Exercise? exercise;
  final SessionExercise sessionExercise;
  final List<SetEntry> sets;
  const _FreestyleDraftExercise({
    required this.exercise,
    required this.sessionExercise,
    required this.sets,
  });
}

/// Small "+" disc sitting right after the set dots: appends one extra set
/// slot to the current exercise so the user can do more sets than planned
/// without leaving the screen. Matches the dot sizing so the strip stays even.
class _AddSetButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSetButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Ajouter une série',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary.withOpacity(0.12),
            border: Border.all(color: cs.primary, width: 1.5),
          ),
          child: Icon(Icons.add, size: 16, color: cs.primary),
        ),
      ),
    );
  }
}

