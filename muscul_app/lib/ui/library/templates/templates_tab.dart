import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/workout_template.dart';

class TemplatesTab extends ConsumerWidget {
  const TemplatesTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(allTemplatesProvider);
    return asyncList.when(
      data: (list) {
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text('Aucun template. Tapez + pour en créer un.',
                  textAlign: TextAlign.center),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _TemplateTile(list[i]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
    );
  }
}

class _TemplateTile extends ConsumerWidget {
  final WorkoutTemplate template;
  const _TemplateTile(this.template);

  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Supprimer ce template ?'),
        content: const Text(
            "Les séances passées qui utilisaient ce template restent dans "
            "l'historique."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('tpl_${template.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(Icons.delete_rounded, color: cs.onError),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) =>
          ref.read(templateRepositoryProvider).softDelete(template.id),
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
          onTap: () => context.push('/library/template/${template.id}'),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusL),
              border: Border.all(color: cs.outlineVariant),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(AppTokens.radiusM),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.fitness_center_rounded,
                      color: cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (template.notes != null && template.notes!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          template.notes!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
