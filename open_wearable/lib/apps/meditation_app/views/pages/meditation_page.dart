import 'drawer_page.dart';
import 'package:flutter/material.dart';
import '../meditation_modes/bio_adaptive_view.dart';
import '../meditation_modes/demo_view.dart';
import '../meditation_modes/timer_view.dart';

enum MeditationMode {
  bioAdaptive(label: "Bio-Scan", icon: Icons.bolt, view: BioAdaptiveView()),
  timer(label: "Timer", icon: Icons.alarm, view: TimerView()),
  demo(label: "Demo", icon: Icons.play_circle_outline, view: DemoView());

  final String label;
  final IconData icon;
  final Widget view;

  const MeditationMode({
    required this.label,
    required this.icon,
    required this.view,
  });
}

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
  MeditationMode _selectedMode = MeditationMode.bioAdaptive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<MeditationMode>(
            segments: MeditationMode.values
                .map(
                  (mode) => ButtonSegment<MeditationMode>(
                    value: mode,
                    label: Text(mode.label),
                    icon: Icon(mode.icon),
                  ),
                )
                .toList(),
            selected: {_selectedMode},
            onSelectionChanged: (Set<MeditationMode> newSelection) {
              setState(() {
                _selectedMode = newSelection.first;
              });
              // TODO: Implement mode switching logic here
            },
          ),
          const SizedBox(height: 24),
          _selectedMode.view,
        ],
      ),
    );
  }
}
