import 'package:flutter/material.dart';

/// Politique de confidentialité affichée in-app (accès requis par le Play
/// Store). Le MÊME texte est versionné dans `docs/privacy_policy.md` à héberger
/// publiquement (l'URL est demandée dans la fiche Play Store + Data Safety).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Confidentialité')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            privacyPolicyText,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

/// Texte source de la politique. ⚠️ Remplace `CONTACT_EMAIL` et la date avant
/// publication, et garde `docs/privacy_policy.md` synchronisé.
const String privacyPolicyText = '''
Politique de confidentialité — Reps

Dernière mise à jour : 2026-06-10

Reps est une application de suivi de musculation. Cette politique explique
quelles données sont traitées et comment.

1. Données traitées
- Compte : ton adresse e-mail (pour créer le compte et synchroniser).
- Entraînement : exercices, modèles de séance, séances, séries (reps, charge,
  RPE), notes, photos d'exercices que tu ajoutes.
- Mensurations : poids de corps que tu saisis (optionnel).
- Réglages de l'app.

L'application fonctionne aussi SANS compte : dans ce cas, toutes tes données
restent uniquement sur ton appareil et rien n'est envoyé en ligne.

2. Finalités
- Faire fonctionner l'app (calcul de progression, historique, statistiques).
- Synchroniser tes données entre tes appareils si tu crées un compte.

3. Hébergement
Si tu utilises un compte, tes données sont stockées chez notre sous-traitant
Supabase, qui les héberge sur des serveurs sécurisés. L'accès est restreint à
ton seul compte (sécurité au niveau des lignes).

4. Partage
Tes données ne sont ni vendues ni partagées à des fins publicitaires. Aucune
donnée n'est transmise à des tiers en dehors de l'hébergement décrit ci-dessus.

5. Conservation et suppression
Tu peux supprimer ton compte à tout moment depuis l'app
(Accueil → ton compte → « Supprimer mon compte »). La suppression efface
définitivement ton compte et toutes les données associées, côté serveur comme
sur l'appareil. Tu peux aussi te déconnecter sans supprimer.

6. Tes droits (RGPD)
Tu disposes d'un droit d'accès, de rectification et d'effacement de tes
données. L'effacement est immédiat via la suppression de compte ci-dessus.

7. Contact
Pour toute question : CONTACT_EMAIL
''';
