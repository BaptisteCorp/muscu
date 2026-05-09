import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tabs/bodyweight_tab.dart';
import 'tabs/exercise_progression_tab.dart';
import 'tabs/sessions_progression_tab.dart';
import 'tabs/volume_progression_tab.dart';

/// Onglet "Progression" : 4 sous-onglets (Exos, Séances, Volume, Poids).
/// Chaque sous-onglet est un widget dédié dans `tabs/`.
class ProgressionScreen extends ConsumerWidget {
  const ProgressionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Progression'),
          bottom: const TabBar(
            tabAlignment: TabAlignment.fill,
            labelPadding: EdgeInsets.symmetric(horizontal: 4),
            labelStyle: TextStyle(fontSize: 13),
            tabs: [
              Tab(text: 'Exos'),
              Tab(text: 'Séances'),
              Tab(text: 'Volume'),
              Tab(text: 'Poids'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          ExerciseProgressionTab(),
          SessionsProgressionTab(),
          VolumeProgressionTab(),
          BodyweightTab(),
        ]),
      ),
    );
  }
}
