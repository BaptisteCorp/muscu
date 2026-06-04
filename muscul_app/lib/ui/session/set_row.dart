import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/session.dart';
import 'int_wheel_sheet.dart';
import 'weight_edit_sheet.dart';

enum SetRowState { completed, active, pending, skipped }

/// Inline row for a single set: shows steppers when active, recap when validated,
/// a placeholder when pending, or a strikethrough label when skipped.
///
/// Built for one-handed use mid-workout — every interactive element meets the
/// 56pt comfort target so a sweaty thumb won't miss.
class SetRow extends StatelessWidget {
  final int setIndex;
  final SetEntry? entry;
  final int reps;
  final double weightKg;
  final int? rpe;
  final SetRowState state;
  final bool useRir;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int?> onRpeChanged;
  final VoidCallback onValidate;
  final VoidCallback? onSkip;
  final VoidCallback? onUnskip;
  final VoidCallback? onTap;
  final String? bodyweightLabel;

  const SetRow({
    super.key,
    required this.setIndex,
    required this.entry,
    required this.reps,
    required this.weightKg,
    required this.rpe,
    required this.state,
    required this.useRir,
    required this.onRepsChanged,
    required this.onWeightChanged,
    required this.onRpeChanged,
    required this.onValidate,
    this.onSkip,
    this.onUnskip,
    this.onTap,
    this.bodyweightLabel,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case SetRowState.completed:
        return _completed(context);
      case SetRowState.skipped:
        return _skipped(context);
      case SetRowState.pending:
        return _pending(context);
      case SetRowState.active:
        return _active(context);
    }
  }

  Widget _completed(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final weightStr = bodyweightLabel != null
        ? bodyweightLabel!
        : '${fmtKg(entry!.weightKg)} kg';
    final rpeText = entry!.rpe != null
        ? '${useRir ? "RIR" : "RPE"} ${useRir ? (10 - entry!.rpe!) : entry!.rpe}'
        : null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            _SetIndexBadge(index: setIndex, completed: true),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: 16,
                ),
                child: Row(
                  children: [
                    Text(
                      '${entry!.reps}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(' × ', style: TextStyle(color: cs.onSurfaceVariant)),
                    Text(
                      weightStr,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    if (rpeText != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusS),
                        ),
                        child: Text(
                          rpeText,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _skipped(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _SetIndexBadge(index: setIndex, skipped: true),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Passée',
              style: TextStyle(
                color: muted,
                fontStyle: FontStyle.italic,
                fontSize: 14,
                decoration: TextDecoration.lineThrough,
                decorationColor: muted,
              ),
            ),
          ),
          if (onUnskip != null)
            TextButton(
              onPressed: onUnskip,
              child: const Text('Annuler'),
            ),
        ],
      ),
    );
  }

  Widget _pending(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _SetIndexBadge(index: setIndex),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$reps × ${fmtKg(weightKg)} kg',
                    style: TextStyle(
                      color: muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: '   à venir',
                    style: TextStyle(
                      color: muted.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onSkip != null)
            IconButton(
              icon: const Icon(Icons.skip_next_outlined),
              tooltip: 'Passer cette série',
              onPressed: onSkip,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _active(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUpdate = entry != null;
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.07),
        border: Border(
          left: BorderSide(color: cs.primary, width: 3),
        ),
      ),
      // Tightened paddings vs. before: the active row used to push pending
      // rows off-screen on phone-height screens.
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No header here — the progress dot strip above the card already
          // shows which set is in progress.
          Row(
            children: [
              Expanded(
                child: _BigStepper(
                  label: 'reps',
                  value: reps.toString(),
                  onTap: () => _editRepsManually(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigStepper(
                  label: bodyweightLabel != null ? '+kg' : 'kg',
                  value: fmtKg(weightKg),
                  onTap: () => _editWeightManually(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigStepper(
                  label: useRir ? 'RIR' : 'RPE',
                  value: rpe == null
                      ? '—'
                      : (useRir ? (10 - rpe!).toString() : rpe!.toString()),
                  onTap: () => _editRpeManually(context),
                  onInfo: () => _showRpeInfo(context, useRir),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: AppTokens.tapTarget,
                  child: FilledButton(
                    onPressed: onValidate,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusM),
                      ),
                    ),
                    child: Text(isUpdate ? 'METTRE À JOUR' : 'VALIDER'),
                  ),
                ),
              ),
              if (onSkip != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: AppTokens.tapTarget,
                  width: AppTokens.tapTarget,
                  child: OutlinedButton(
                    onPressed: onSkip,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: cs.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusM),
                      ),
                    ),
                    child: Icon(
                      Icons.skip_next_outlined,
                      size: 24,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Wheel picker pour les reps (1..60).
  Future<void> _editRepsManually(BuildContext context) async {
    final picked = await showIntWheel(
      context,
      title: 'Répétitions',
      min: 1,
      max: 60,
      initial: reps,
      unit: 'reps',
    );
    if (picked != null) onRepsChanged(picked);
  }

  /// Wheel picker pour le RPE (1..10) ou le RIR (0..9). On présente l'échelle
  /// affichée à l'utilisateur et on reconvertit en RPE pour le stockage.
  Future<void> _editRpeManually(BuildContext context) async {
    final currentRpe = (rpe ?? 8).clamp(1, 10);
    if (useRir) {
      final picked = await showIntWheel(
        context,
        title: 'RIR — reps en réserve',
        min: 0,
        max: 9,
        initial: 10 - currentRpe,
      );
      if (picked != null) onRpeChanged((10 - picked).clamp(1, 10));
    } else {
      final picked = await showIntWheel(
        context,
        title: 'RPE — intensité perçue',
        min: 1,
        max: 10,
        initial: currentRpe,
      );
      if (picked != null) onRpeChanged(picked.clamp(1, 10));
    }
  }

  /// Opens the kilo-by-kilo wheel picker for manual weight entry, then pushes
  /// the chosen value back through [onWeightChanged].
  Future<void> _editWeightManually(BuildContext context) async {
    final picked = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (_) => WeightEditSheet(
        initialKg: weightKg,
        allowNegative: bodyweightLabel != null,
        unitLabel: bodyweightLabel != null ? '+kg' : 'kg',
      ),
    );
    if (picked != null) onWeightChanged(picked);
  }
}

class _SetIndexBadge extends StatelessWidget {
  final int index;
  final bool completed;
  final bool skipped;
  const _SetIndexBadge({
    required this.index,
    this.completed = false,
    this.skipped = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    final Widget child;
    if (completed) {
      bg = AppTokens.successGreen.withOpacity(0.18);
      fg = AppTokens.successGreen;
      child = Icon(Icons.check_rounded, size: 18, color: fg);
    } else if (skipped) {
      bg = cs.surfaceContainerHigh;
      fg = cs.onSurfaceVariant;
      child = Icon(Icons.remove, size: 16, color: fg);
    } else {
      bg = cs.surfaceContainerHigh;
      fg = cs.onSurfaceVariant;
      child = Text(
        '${index + 1}',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }
}

/// Horizontal strip of small numbered circles — one per set — summarising the
/// whole sequence at a glance: validated (green check), the set in progress
/// (filled primary, ringed), skipped (dash) and upcoming (hollow outline).
/// Replaces the old stack of "à venir" preview rows.
class SetProgressDots extends StatelessWidget {
  final List<SetRowState> states;

  /// Per-set tap handler (same length as [states], or null). Validated dots
  /// open the set editor; skipped dots restore the set. Unused slots are null.
  final List<VoidCallback?>? taps;

  const SetProgressDots({super.key, required this.states, this.taps});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < states.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          _Dot(
            index: i,
            state: states[i],
            onTap: (taps != null && i < taps!.length) ? taps![i] : null,
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final int index;
  final SetRowState state;
  final VoidCallback? onTap;
  const _Dot({required this.index, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color bg;
    final Widget child;
    Border? border;
    var ringed = false;
    switch (state) {
      case SetRowState.completed:
        bg = AppTokens.successGreen;
        child = const Icon(Icons.check_rounded, size: 15, color: Colors.white);
        break;
      case SetRowState.active:
        bg = cs.primary;
        ringed = true;
        child = Text(
          '${index + 1}',
          style: TextStyle(
            color: cs.onPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        );
        break;
      case SetRowState.skipped:
        bg = cs.surfaceContainerHigh;
        child = Icon(Icons.remove, size: 14, color: cs.onSurfaceVariant);
        break;
      case SetRowState.pending:
        bg = Colors.transparent;
        border = Border.all(color: cs.outline, width: 1.5);
        child = Text(
          '${index + 1}',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        );
        break;
    }
    final dot = Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: border),
      child: child,
    );
    // Outer ring to make the in-progress set pop without enlarging the row.
    final Widget visual = ringed
        ? Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.primary.withOpacity(0.35), width: 2),
            ),
            child: dot,
          )
        : dot;
    if (onTap == null) return visual;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: visual,
    );
  }
}

/// Vertical "stepper" : label en haut, grosse valeur tabulaire au centre,
/// et un bouton molette en bas. Plus de +/- : tout se règle à la molette
/// (tap valeur ou bouton), c'est plus simple et plus lisible. Vertical car
/// trois colonnes se partagent la largeur de la ligne.
class _BigStepper extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onInfo;

  /// Ouvre le picker (tap sur la valeur ou sur le bouton molette).
  final VoidCallback onTap;
  const _BigStepper({
    required this.label,
    required this.value,
    required this.onTap,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              if (onInfo != null) ...[
                const SizedBox(width: 3),
                GestureDetector(
                  onTap: onInfo,
                  child: Icon(
                    Icons.info_outline,
                    size: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          // Hero value — fixed height so all 3 columns line up.
          SizedBox(
            height: 30,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _StepperButton(icon: Icons.tune_rounded, onPressed: onTap),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _StepperButton({required this.icon, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppTokens.radiusS),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
        ),
        child: Icon(icon, size: 20, color: cs.onSurface),
      ),
    );
  }
}

void _showRpeInfo(BuildContext context, bool useRir) {
  showDialog(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(useRir
          ? 'RIR — Reps In Reserve'
          : 'RPE — Rate of Perceived Exertion'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(useRir
                ? "Combien de reps il te restait dans le réservoir à la fin de la série."
                : "À quel point la série était dure, sur une échelle de 1 à 10."),
            const SizedBox(height: 12),
            const Text('Repères :',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (useRir) ...const [
              Text("• RIR 0 → max, impossible d'en faire une de plus"),
              Text('• RIR 1 → 1 rep encore en réserve'),
              Text('• RIR 2 → 2 reps en réserve (cible classique)'),
              Text('• RIR 3 → 3 reps en réserve, série modérée'),
              Text('• RIR 4+ → trop léger pour de la prise de muscle'),
            ] else ...const [
              Text('• RPE 10 → max, 0 rep en réserve (échec)'),
              Text('• RPE 9  → très dur, 1 rep en réserve'),
              Text('• RPE 8  → dur, 2 reps en réserve (cible classique)'),
              Text('• RPE 7  → modéré, 3 reps en réserve'),
              Text('• RPE 6 et moins → échauffement / trop léger'),
            ],
            const SizedBox(height: 12),
            Text(
              "L'app utilise cette valeur pour calibrer la progression : "
              "${useRir ? 'RIR ≤ 1' : 'RPE ≥ 9'} signale qu'on est proche de l'échec, "
              "et la cible n'augmentera pas tant que tu n'as pas un peu de marge.",
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
