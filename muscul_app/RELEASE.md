# Publier Reps sur le Play Store

## 1. Keystore d'upload (une seule fois)
```bash
keytool -genkey -v -keystore ~/reps-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Puis copie `android/key.properties.example` → `android/key.properties` (non
versionné) et renseigne `storePassword`, `keyPassword`, `keyAlias`, `storeFile`
(chemin absolu vers le `.jks`).

⚠️ **Sauvegarde le `.jks` et les mots de passe** : sans Play App Signing, les
perdre = impossible de publier une mise à jour. Active **Play App Signing** à la
1re publication (Google détient la clé finale, tu ne fournis que la clé d'upload).

Sans `key.properties`, les builds release retombent sur les clés debug (pratique
en dev, **refusé** par le Play Store).

## 2. Versionner
Incrémente à chaque dépôt dans `pubspec.yaml` : `version: 1.0.0+1`
(`x.y.z+N` → `N` = versionCode, doit augmenter à chaque upload).

## 3. Construire l'App Bundle (format exigé par le Play Store)
```bash
flutter build appbundle --release --dart-define-from-file=lib/.env.json
```
Sortie : `build/app/outputs/bundle/release/app-release.aab`.
(L'APK `flutter build apk` ne sert qu'au sideload de test.)

## 4. Côté Supabase (à faire avant le lancement)
- Exécuter `supabase/schema.sql` (idempotent) — crée notamment la fonction
  `delete_current_user()` utilisée par « Supprimer mon compte ».
- Configurer un **SMTP custom** (l'e-mail par défaut Supabase est rate-limité).
- Vérifier que le projet est sur un tier qui ne se met pas en pause.

## 5. Console Play (hors code)
- **Politique de confidentialité** : héberger `docs/privacy_policy.md` à une URL
  publique et la renseigner (remplacer `CONTACT_EMAIL`).
- **Data safety** : déclarer e-mail + données d'entraînement + poids + photos,
  et la suppression de compte (in-app : Accueil → compte → Supprimer ;
  + l'URL web de suppression si demandée).
- **Assets** : icône 512×512, feature graphic, captures d'écran, description.

## Reste recommandé (non bloquant)
- Crash reporting (Sentry).
- Ré-activer R8 avec des règles ProGuard ciblées (FileProvider/image_picker).
