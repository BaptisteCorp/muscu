# Muscul App

Application Android de suivi de séances de musculation, **local-first** — implémente le design `2026-04-30-muscul-app-design.md` (v1).

## Pré-requis

- **Flutter** 3.19+ (Dart 3.3+) — https://docs.flutter.dev/get-started/install
- **Android SDK** + un device Android avec USB debugging, ou un émulateur API 24+

## Premier lancement

```bash
cd muscul_app

# 1. Récupère les dépendances
flutter pub get

# 2. Génère le code Drift (la base de données typée)
dart run build_runner build --delete-conflicting-outputs

# 3. Lance sur un device Android branché
flutter run
```

> ⚠️ Si vous n'avez pas encore le wrapper Gradle (`android/gradlew`), exécutez une fois `flutter create --platforms=android .` depuis le dossier `muscul_app/` pour générer les fichiers Gradle/Android manquants. Tous les fichiers Kotlin et de configuration personnalisés présents seront préservés.

## Structure

```
muscul_app/
├── lib/
│   ├── main.dart, app.dart
│   ├── core/         theme, router, providers, widgets transverses
│   ├── data/         Drift DB, repositories, photo storage
│   ├── domain/       modèles, moteur de progression (pur Dart)
│   └── ui/           home, planning, library, progression, session
├── test/             unit + repo
└── integration_test/ golden path
```

## Tests

```bash
# Unit (incl. ProgressionEngine — TDD)
flutter test

# Integration (sur device)
flutter test integration_test/
```

Le **moteur de progression** (`lib/domain/progression/`) est volontairement pur Dart, sans dépendance Flutter ni I/O — il est testable en isolation et couvert par `test/domain/progression/progression_engine_test.dart`.

## Build APK signé

```bash
# Pour développement / install local (signature debug)
flutter build apk --release

# Pour publier (à configurer dans android/app/build.gradle)
flutter build appbundle --release
```

## Stack

- Flutter 3 / Dart 3, Material 3
- **Riverpod** pour la gestion d'état
- **go_router** pour la navigation
- **Drift** (SQLite typé) pour la persistance locale
- **fl_chart** pour les graphes
- **image_picker** pour les photos machines

Le code est organisé en couches **UI → Domain → Data**. Les repositories sont des interfaces ; en v1 il n'existe que les implémentations locales `LocalXxxRepository`. La sync cloud (Firebase) sera ajoutée en Phase 2 sans toucher l'UI ni le domaine.

## Différence avec le design

- Les modèles de domaine sont des classes Dart immuables avec `copyWith` manuel (au lieu de `freezed`) — moins de friction de codegen sur ce premier scaffold. Migration vers freezed possible plus tard sans changement d'API publique.

## Notes

- **Champs sync** (`updatedAt`, `syncStatus`, `remoteId`, `deletedAt`) sont déjà présents en BDD — inutilisés en v1, prêts pour la Phase 2.
- **Exercices par défaut** seedés au premier lancement (~30 exercices essentiels couvrant push/pull/legs/core), non modifiables ni supprimables — dupliquez-les pour les personnaliser.
- **Photos** stockées dans `<app_documents>/exercise_photos/<exerciseId>.jpg`, seul le chemin relatif est persistant en BDD.
