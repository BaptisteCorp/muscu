import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Bandeau visible au-dessus d'un exo qui appartient à un superset, avec
/// l'action "Détacher" pour quitter le groupe.
class SupersetBanner extends StatelessWidget {
  final int partnerCount;
  final VoidCallback onLeave;
  const SupersetBanner({
    super.key,
    required this.partnerCount,
    required this.onLeave,
  });

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
              'Superset · enchaîne avec '
              '${partnerCount == 1 ? 'cet exo' : '$partnerCount exos'}',
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
