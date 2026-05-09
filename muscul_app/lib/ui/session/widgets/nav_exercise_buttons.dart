import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';

/// Bouton "← Précédent" sous la liste de séries, montre le nom de l'exo
/// précédent (ou "Précédent" si non chargé).
class PrevExerciseButton extends ConsumerWidget {
  final String previousExerciseId;
  final VoidCallback onPressed;
  const PrevExerciseButton({
    super.key,
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

/// Bouton "Suivant →" sous la liste de séries.
class NextExerciseButton extends ConsumerWidget {
  final String nextExerciseId;
  final VoidCallback onPressed;
  const NextExerciseButton({
    super.key,
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
