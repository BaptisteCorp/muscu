# Muscul App — Design

**Date** : 2026-04-30
**Statut** : Draft pour validation utilisateur

## 1. Vision

Application Android de suivi de séances de musculation, **local-first**, avec à terme une synchronisation cloud pour permettre l'agrégation de statistiques anonymisées sur l'ensemble des utilisateurs (analyses de tendances, etc.).

L'utilisateur peut :
- Cataloguer des exercices (par défaut + custom, avec photo de la machine, marque/modèle, réglages)
- Construire des templates de séance ordonnés
- Réaliser une séance en mode immersif (focus minimal, validation d'une série en 1-2 taps)
- Substituer rapidement un exercice en cours de séance (machine occupée, etc.)
- Consulter sa progression (graphes, e1RM, volume, records perso)
- Planifier ses prochaines séances et consulter l'historique

L'app calcule la **prochaine cible (sets × reps × poids)** pour chaque exercice via un moteur de progression configurable :
- **Double progression** (par défaut)
- **Auto-régulé RPE/e1RM** (option par exercice)

L'incrément de poids est paramétrable (global + override par exercice, défaut 2.5 kg).

## 2. Stack technique

- **Plateforme** : Android uniquement (v1)
- **Framework** : Flutter 3.x / Dart 3.x
- **State management** : Riverpod
- **Navigation** : go_router
- **Persistance locale** : Drift (SQLite typé)
- **Modèles immuables** : freezed + json_serializable
- **Graphes** : fl_chart
- **Photos** : image_picker + path_provider (stockage local en JPEG compressé)
- **Cloud (Phase 2 — non implémenté en v1)** : Firebase Auth + Firestore + Firebase Storage + export BigQuery pour analyses

## 3. Architecture globale

```
┌─────────────────────────────────────────────┐
│           App Flutter (Android)             │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │  UI Layer (Material 3, Riverpod)     │  │
│  └──────────────────────────────────────┘  │
│  ┌──────────────────────────────────────┐  │
│  │  Domain Layer                        │  │
│  │  - Models (Exercise, Workout, Set…)  │  │
│  │  - Use cases (ProgressionEngine…)    │  │
│  └──────────────────────────────────────┘  │
│  ┌──────────────────────────────────────┐  │
│  │  Data Layer                          │  │
│  │  - Repositories (interface)          │  │
│  │  - LocalDataSource (Drift / SQLite)  │  │
│  │  - RemoteDataSource (Firestore) [v2] │  │
│  │  - SyncService [v2]                  │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
              │ (Phase 2 uniquement)
              ▼
┌─────────────────────────────────────────────┐
│  Firebase: Auth + Firestore + Storage       │
│  → Export BigQuery pour analyses agrégées   │
└─────────────────────────────────────────────┘
```

**Principe local-first** : toutes les écritures vont d'abord sur SQLite local. La sync vers Firestore est un layer optionnel et asynchrone qui s'active quand l'utilisateur se connecte (Phase 2).

**Découpage en couches** : UI → Domain → Data, dépendances dirigées vers le domaine. Les repositories sont des interfaces, leur implémentation locale est la seule en v1, une implémentation `SyncedRepository` sera ajoutée en v2 sans modifier l'UI ni le domaine.

## 4. Modèle de données

### Entités

**`Exercise`** — catalogue d'exercices
- `id` (UUID v4)
- `name` (texte, ex: "Développé couché")
- `category` (enum : `push` / `pull` / `legs` / `core` / `cardio`)
- `primaryMuscle` (enum)
- `secondaryMuscles` (liste d'enums)
- `equipment` (enum : `barbell` / `dumbbell` / `machine` / `cable` / `bodyweight` / `other`)
- `isCustom` (bool — false = exo seed par défaut, true = créé par l'utilisateur)
- `defaultIncrementKg` (double, nullable — override de l'incrément global)
- `progressionStrategy` (enum : `doubleProgression` / `rpeAutoregulated`)
- `targetRepRangeMin` (int, ex: 8)
- `targetRepRangeMax` (int, ex: 12)
- `startingWeightKg` (double, défaut 20.0 pour barre, 0.0 pour bodyweight — utilisé comme poids initial quand l'exo n'a pas d'historique)
- `notes` (texte libre, nullable)
- `machineBrandModel` (texte libre, nullable — ex: "Technogym Selection 700 — Chest Press")
- `machineSettings` (texte libre, nullable — ex: "Siège: 4 / Dossier: 2 / Position bras: B")
- `photoPath` (chemin local relatif, nullable — ex: `exercise_photos/<id>.jpg`)
- Champs sync (présents dès la v1, inutilisés sans cloud) : `updatedAt`, `syncStatus`, `remoteId`, `deletedAt`

**`WorkoutTemplate`** — modèle de séance réutilisable (ex: "Push A")
- `id`, `name`, `notes`
- `createdAt`, `updatedAt`
- Champs sync

**`WorkoutTemplateExercise`** — jonction template ↔ exercise, **ordonnée**
- `templateId`, `exerciseId`, `orderIndex`
- `targetSets` (int, ex: 3)

**`WorkoutSession`** — séance réellement effectuée
- `id`, `templateId` (nullable, si freestyle)
- `startedAt`, `endedAt` (nullable tant que la séance n'est pas terminée)
- `notes`
- `plannedFor` (date, nullable — utilisé pour les séances planifiées non démarrées)
- Champs sync

**`SessionExercise`** — instance d'exercice dans une séance, ordonnée
- `id`, `sessionId`, `exerciseId`, `orderIndex`
- `note` (texte libre par exercice)
- `replacedFromSessionExerciseId` (nullable — trace une substitution effectuée en cours de séance)

**`SetEntry`** — une série effectuée
- `id`, `sessionExerciseId`, `setIndex`
- `reps` (int)
- `weightKg` (double)
- `rpe` (int 1–10, nullable)
- `rir` (int, nullable — alternative à RPE selon préférence user)
- `restSeconds` (int — durée du repos qui a précédé cette série, mesurée par chrono)
- `isWarmup` (bool, défaut false)
- `isFailure` (bool, défaut false)
- `completedAt` (timestamp)

**`UserSettings`** (singleton local)
- `defaultIncrementKg` (double, défaut 2.5)
- `weightUnit` (enum : `kg` / `lb`, défaut kg)
- `defaultRestSeconds` (int, défaut 120)
- `useRirInsteadOfRpe` (bool, défaut false)
- `themeMode` (enum : `system` / `light` / `dark`)

### Règles de cohérence

- Tous les IDs sont des UUID v4 générés côté client (pas d'auto-increment) → permet la sync ultérieure sans remapping.
- Les exercices par défaut ont `isCustom = false` ; ils sont seedés à la première ouverture de l'app, ne sont pas synchronisés en cloud, et ne peuvent être ni renommés ni supprimés (mais peuvent être copiés via "Dupliquer" pour devenir des custom modifiables).
- Suppression d'un `Exercise` référencé par des sessions passées → soft delete (`deletedAt`) ; l'historique reste lisible.
- Les photos sont stockées dans `<app_documents>/exercise_photos/<exerciseId>.jpg` (JPEG compressé), seul le chemin relatif est en BDD.

### Seed des exercices par défaut

~30 exercices essentiels couvrant les patterns fondamentaux :
- **Push** : Développé couché barre, Développé couché haltères, Développé incliné, Développé militaire, Élévations latérales, Dips, Extensions triceps poulie, Pompes
- **Pull** : Soulevé de terre, Tractions, Rowing barre, Rowing haltère, Tirage vertical, Tirage horizontal, Curl barre, Curl haltères, Face pull
- **Legs** : Squat barre, Front squat, Squat bulgare, Presse à cuisses, Leg curl, Leg extension, Hip thrust, Mollets debout, Mollets assis
- **Core** : Gainage, Crunch lesté, Roue abdominale

## 5. Navigation et écrans

### Modes

**Mode "Hors séance"** — bottom navigation 4 onglets (toujours visible) :

1. **Accueil** (`HomeScreen`) — séance du jour suggérée, raccourcis "Démarrer" / "Reprendre" si une séance est en pause, carte "Prochaine séance planifiée" si applicable
2. **Planning** (`PlanningScreen`) — vue calendrier compact + timeline scrollable des séances planifiées (futures) et passées, filtres par période, tap → planifier ou consulter
3. **Bibliothèque** (`LibraryScreen`) — deux sous-onglets : *Templates* (CRUD) et *Exercices* (catalogue par défaut + custom, recherche, filtres, CRUD avec photo et réglages machine)
4. **Progression** (`ProgressionScreen`) — section *Records perso* en carrousel (1RM estimé, meilleur volume, meilleure série), graphes par exercice (e1RM dans le temps, volume hebdomadaire), historique tabulaire

**Mode "Séance" (immersif)** — `ActiveSessionScreen` :
- Plein écran, bottom nav cachée, retour bloqué (confirmation requise pour quitter)
- Sortie : "Terminer la séance" (sauvegarde + récap) ou "Mettre en pause" (la séance reste reprenable depuis Accueil)
- Aucun accès aux stats / autres exos pendant la séance — focus total

### `ActiveSessionScreen` — détail (UX critique)

**Layout** : un seul exercice affiché à la fois, plein écran.

```
┌──────────────────────────────────────┐
│ ← Push A           [Σ 24:31]    ⋮   │
├──────────────────────────────────────┤
│                                      │
│  Développé couché              [📷]  │
│  Cible : 3×10 @ 60kg  RPE 8         │
│                                      │
│  ┌────────────────────────────────┐ │
│  │ Série 1 ✓   10 × 60kg   RPE 8 │ │
│  ├────────────────────────────────┤ │
│  │ Série 2 ✓   10 × 60kg   RPE 8 │ │
│  ├────────────────────────────────┤ │
│  │ Série 3   [ 10 ]  [ 60 ]  [8] │ │
│  │           reps    kg     RPE  │ │
│  │                                │ │
│  │        [   VALIDER   ]         │ │
│  └────────────────────────────────┘ │
│                                      │
│  ⏱  Repos : 1:23 / 2:00              │
│                                      │
├──────────────────────────────────────┤
│  ◀  Squat       │      Rowing  ▶    │
└──────────────────────────────────────┘
```

**Principes UX**
- Valeurs préremplies depuis la dernière série (ou la cible). Cas nominal : 1 tap = "Valider".
- Steppers ± inline (boutons +/− 1 rep, +/− `incrementKg` poids, +/− 1 RPE) — pas de clavier qui s'ouvre. Édition fine = tap long sur le champ → clavier numérique.
- Bouton VALIDER énorme en bas (zone pouce, mains moites).
- Swipe horizontal = passer à l'exo suivant/précédent.
- Tap sur une série déjà validée = correction inline directe (pas de modal).
- Chrono de repos toujours visible, démarre auto à la validation, vibration + notification locale à la fin.
- Photo machine : thumbnail dans le header, tap = plein écran.
- Menu `⋮` (en haut à droite) = actions rares : ajouter/supprimer un exo, réordonner, note, mettre en pause, terminer.

### Substitution rapide en cours de séance — `QuickSwapSheet`

Déclenché par tap long sur le nom de l'exo ou icône **⇄**. Bottom sheet plein écran, **un seul écran**, aucune navigation.

Composé de 3 zones, du plus rapide au plus complet :

1. **Suggestions intelligentes** (carrousel horizontal de cartes en haut)
   - Algo : exercices ayant le même `primaryMuscle` et la même `category` que l'exo prévu
   - Tap = swap immédiat

2. **Recherche rapide** (barre de saisie au milieu)
   - Filtre du catalogue (par défaut + custom) à la frappe
   - Tap = swap immédiat

3. **Création à la volée** (bouton `+ Nouvel exo rapide` en bas)
   - Mini-formulaire 3 champs : nom, muscle principal, équipement
   - Reste hérité des défauts sensés (fourchette 8–12 reps, stratégie `doubleProgression`, `incrementKg` global), complétable plus tard
   - Création avec `isCustom = true` puis substitution dans la séance

### Comportement après swap

- L'ordre des exos est préservé : on remplace l'exo à la même position.
- Si l'utilisateur avait déjà fait des séries sur l'exo remplacé : l'ancien `SessionExercise` est conservé avec ses séries (pas de perte de données), un nouveau `SessionExercise` est créé juste après dans l'ordre, et `replacedFromSessionExerciseId` lie les deux.
- Si aucune série n'avait été faite : l'ancien `SessionExercise` est supprimé, le nouveau prend sa place.
- La cible (`ProgressionTarget`) est recalculée pour le nouvel exo via `ProgressionEngine.computeNextTarget` sur son propre historique. Si l'exo n'a pas d'historique, valeurs initiales placeholder éditables.

## 6. Moteur de progression

Composant pur (sans I/O), testable en isolation. Une seule fonction publique :

```dart
ProgressionTarget computeNextTarget({
  required Exercise exercise,
  required int plannedSets, // nb de séries prévues (vient du WorkoutTemplateExercise, ou recopié de la dernière séance si freestyle)
  required List<SessionExercise> history, // séances passées de cet exo, plus récentes en premier — chaque SessionExercise contient ses SetEntry
  required UserSettings settings,
});

class ProgressionTarget {
  final int targetSets;       // = plannedSets (l'engine ne change pas le nombre de séries en v1)
  final int targetReps;       // même cible pour toutes les séries de travail
  final double targetWeightKg;
  final int? targetRpe;       // null si stratégie A et l'utilisateur n'utilise pas le RPE
  final String reason;        // texte court affiché à l'utilisateur
}
```

Le moteur ne pilote ni le nombre de séries ni le temps de repos en v1 — il propose uniquement reps × poids (et RPE en stratégie B). Le `targetSets` retourné est une recopie de `plannedSets`.

### Stratégie A — Double progression (`doubleProgression`)

Paramètres : `targetRepRangeMin`, `targetRepRangeMax`, `incrementKg` (override exo > settings global).

Soit **série de travail** = série avec `isWarmup = false`. Soit **dernière séance** = la `SessionExercise` la plus récente dans `history`. Soit `lastTopReps` = nombre de reps de la **série de travail comportant le moins de reps** dans la dernière séance, et `lastWeight` = poids commun aux séries de travail (en cas de poids variables, on prend le poids le plus utilisé). Le RPE pris en compte est le RPE max sur les séries de travail (`null` traité comme RPE 8).

1. Si `lastTopReps >= targetRepRangeMax` ET RPE ≤ 9 :
   → poids = `lastWeight + incrementKg`, reps = `targetRepRangeMin`
   → `reason` = "+{incrementKg}kg car {plannedSets}×{max} réussi"
2. Sinon, si `lastTopReps >= ancienne_cible` ET RPE ≤ 9 :
   → poids = `lastWeight`, reps = `min(lastTopReps + 1, targetRepRangeMax)`
   → `reason` = "+1 rep, on monte vers {max}"
3. Sinon (échec partiel, ou RPE = 10) :
   → poids = `lastWeight`, reps = ancienne cible (= reps demandées la dernière fois ; faute de mieux on reprend `lastTopReps`)
   → `reason` = "On retente les mêmes valeurs"
4. Si `history` est vide ou ne contient aucune série de travail : valeurs initiales = `targetRepRangeMin` reps × `Exercise.startingWeightKg` (champ ajouté à `Exercise`, défaut 20kg ou 0 selon `equipment`). Modifiable inline dans la séance.

### Stratégie B — Auto-régulé RPE (`rpeAutoregulated`)

Basé sur l'**e1RM** (1-rep-max estimé) et un RPE cible mobile.

**Calcul e1RM** par série (formule Epley adaptée RPE) :
```
e1RM = poids × (1 + (reps + (10 - rpe)) / 30)
```

Pour chaque séance, on prend le **meilleur e1RM** parmi les séries de travail (hors warmup).

Algo :
1. Calculer la moyenne mobile sur les 3 dernières séances → `e1RM_courant`
2. Tendance : `slope = (e1RM_séance_n − e1RM_séance_n-3) / 3`
   - `slope > 0.5 kg/séance` → RPE cible = 8
   - `0 ≤ slope ≤ 0.5` → RPE cible = 7.5
   - `slope < 0` → RPE cible = 7 (deload léger)
3. Cible reps : milieu de la fourchette (`(min + max) / 2`, arrondi)
4. Cible poids déduit par formule inverse :
   ```
   weight = e1RM_courant / (1 + (targetReps + (10 - targetRpe)) / 30)
   ```
5. Arrondi au multiple de `incrementKg` le plus proche.
6. `reason` = ex: "Charge calculée pour {targetReps} reps @ RPE {targetRpe} (e1RM courant {x}kg)"

**Cas limite** : moins de 2 séances d'historique → fallback sur stratégie A avec message "Pas assez d'historique pour le mode auto-régulé, on reste en double progression".

### Tests unitaires (TDD strict)

- Double progression : seuil haut atteint à RPE ≤ 9 → +incrément, reps redescendent au min
- Double progression : seuil haut atteint mais RPE 10 → pas d'incrément, mêmes valeurs
- Double progression : reps incomplètes → mêmes valeurs
- Double progression : aucun historique → valeurs initiales (`startingWeightKg`, `targetRepRangeMin`)
- Double progression : +1 rep si toutes les séries OK et fourchette pas atteinte
- Double progression : warmup ignoré (les séries `isWarmup = true` ne participent pas au calcul)
- RPE auto : e1RM en hausse → RPE cible 8
- RPE auto : e1RM stable → RPE cible 7.5
- RPE auto : e1RM en baisse → RPE cible 7 (deload)
- RPE auto : <2 séances → fallback double progression avec message
- Override incrément exo > settings global respecté
- Arrondi correct au multiple de incrément (ex: 47.3 → 47.5 si increment 2.5)
- `targetSets` retourné = `plannedSets` (l'engine ne change pas le nb de séries)

## 7. Synchronisation cloud (Phase 2 — design seulement)

### Modèle Firestore

```
users/{userId}
  exercises/{exerciseId}        ← exos custom de l'user (les défauts ne sont pas synchros)
  templates/{templateId}
  sessions/{sessionId}
    sessionExercises/{...}
      sets/{...}
  settings/{singletonDoc}
```

Photos machines → **Firebase Storage** : `users/{userId}/exercise_photos/{exerciseId}.jpg`

### Mécanisme

**Champs sync** sur chaque entité (présents dès la v1) :
- `updatedAt` (timestamp serveur si synchro, sinon local)
- `syncStatus` (`pending` / `synced` / `conflict`)
- `remoteId` (nullable)
- `deletedAt` (nullable, soft delete)

**SyncService** (background isolate, déclenché à l'ouverture + toutes les 5 min si réseau dispo) :
1. **Push** : entités `pending` → écriture Firestore → `synced`
2. **Pull** : query par collection `where updatedAt > lastSyncTime` → merge local
3. **Conflit** : last-write-wins au niveau entité, log dans table `sync_conflicts` consultable depuis Settings

### BigQuery (analyses anonymisées)

- Activer l'export Firestore → BigQuery natif (config console Firebase)
- Vue agrégée anonymisée : `user_hash` (pas de PII), events utiles (type d'exo, reps, poids, RPE, e1RM, date)
- **Consentement RGPD** : écran de consentement explicite à la première connexion, opt-in pour la collecte agrégée, opt-out depuis Settings (filtré côté export BQ via flag `analyticsConsent`)

### Auth (v2)

- `firebase_auth` avec Sign in with Google + email/password
- Premier login avec données locales existantes : choix "Garder local / écraser avec cloud / fusionner" (défaut fusion last-write-wins)

## 8. Structure du projet et tests

### Arborescence Flutter

```
muscul_app/
├── android/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── theme/
│   │   ├── router/
│   │   ├── utils/
│   │   └── widgets/
│   ├── data/
│   │   ├── db/
│   │   │   ├── database.dart
│   │   │   ├── tables/
│   │   │   └── seeds/
│   │   ├── repositories/
│   │   └── photo_storage.dart
│   ├── domain/
│   │   ├── models/
│   │   └── progression/
│   │       ├── progression_engine.dart
│   │       ├── strategies/
│   │       │   ├── double_progression.dart
│   │       │   └── rpe_autoregulated.dart
│   │       └── e1rm.dart
│   └── ui/
│       ├── home/
│       ├── planning/
│       ├── library/
│       │   ├── templates/
│       │   └── exercises/
│       ├── progression/
│       └── session/
│           ├── active_session_screen.dart
│           ├── set_row.dart
│           ├── rest_timer.dart
│           └── quick_swap_sheet.dart
├── test/
│   ├── domain/
│   │   └── progression/
│   ├── data/
│   │   └── repositories/
│   └── ui/
├── integration_test/
└── pubspec.yaml
```

### Stratégie de tests

- **Unit (priorité haute)** : `ProgressionEngine` à 100% (TDD strict)
- **Repository tests** : Drift `NativeDatabase.memory()` → CRUD + scénarios (séance avec swap, soft delete)
- **Widget tests** : `ActiveSessionScreen`, `QuickSwapSheet`, steppers `SetRow`
- **Integration test** : un seul, golden path (créer un exo custom → créer template → démarrer séance → valider 3 séries → terminer → vérifier la cible suggérée à la séance suivante)

## 9. Jalons d'implémentation

Chacun fera l'objet d'un plan d'implémentation séparé :

- **Jalon 1 — Fondations** : projet Flutter, Drift DB, modèles, repositories locaux, seed des 30 exos par défaut, navigation 4 onglets stub
- **Jalon 2 — Catalogue & Templates** : écrans Bibliothèque (CRUD exos avec photo + machine, CRUD templates ordonnés par drag & drop)
- **Jalon 3 — Mode séance** : `ActiveSessionScreen`, steppers, chrono de repos, validation rapide, persistance des séries
- **Jalon 4 — Quick swap** : substitution d'exo en cours de séance avec suggestions + création rapide
- **Jalon 5 — Progression engine** : double progression + RPE auto-régulé, branchement dans HomeScreen et ActiveSessionScreen
- **Jalon 6 — Stats & PR** : `ProgressionScreen` avec graphes (`fl_chart`), records perso, vue historique des séances
- **Jalon 7 — Planning** : timeline planifiées/passées, planification d'une séance future
- **Jalon 8 — Polish & APK** : icône, splash, dark/light, build APK signé pour Android

**Phase 2 (séparée)** — Sync Firebase + Auth + BigQuery + écran consentement RGPD. À planifier une fois la v1 utilisée quelques semaines.

## 10. Hors-scope v1

Explicitement non couvert en v1, à recadrer plus tard :
- iOS et build cross-platform
- Sync cloud, comptes utilisateurs, partage social
- Cardio détaillé (HR, distances GPS) — la catégorie cardio est présente mais le modèle est orienté séries × reps × poids
- Plans d'entraînement multi-semaines automatiques (ex: cycles linéaires programmés)
- Import de données externes (Strong, Hevy, FitNotes)
- Notifications de rappel de séance
- Mode "compétition" (powerlifting attempts, etc.)
- Calcul de calories / nutrition
