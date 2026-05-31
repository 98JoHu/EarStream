import 'package:flutter/material.dart';
import 'drawer_page.dart';

class PreferencesPage extends StatefulWidget implements DrawerPage {
  const PreferencesPage({super.key});

  @override
  String get label => "Meditation Preferences";

  @override
  IconData get icon => Icons.spa_outlined;

  @override
  IconData get selectedIcon => Icons.spa;

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("Meditation Preferences"),
    );
  }
}
