import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/exercise.dart';

/// Bandeau du haut de chaque page d'exo : photo (optionnelle), nom, libellé
/// muscle/équipement, bouton de substitution et bouton superset.
class ExerciseHeader extends StatelessWidget {
  final Exercise exercise;
  final VoidCallback onSwap;
  final VoidCallback? onSuperset;
  final bool isSuperset;
  final Future<File?>? photoFuture;
  final ValueChanged<File> onPhotoTap;
  const ExerciseHeader({
    super.key,
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
                      borderRadius: BorderRadius.circular(AppTokens.radiusM),
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
              Text(
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
              const SizedBox(height: 2),
              Text(
                '${muscleLabel(exercise.primaryMuscle)} · ${exercise.equipment.label}',
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
}
