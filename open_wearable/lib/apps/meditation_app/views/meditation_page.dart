import 'drawer_page.dart';
import 'package:flutter/material.dart';

class MeditationPage extends StatefulWidget implements DrawerPage {
  const MeditationPage({super.key});

  @override
  String get label => "Meditation Mode";

  @override
  IconData get icon => Icons.tune_outlined;

  @override
  IconData get selectedIcon => Icons.tune;

  @override
  State<MeditationPage> createState() => _MeditationPageState();
}

class _MeditationPageState extends State<MeditationPage> {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("Meditation Mode"),
    );
  }
}
