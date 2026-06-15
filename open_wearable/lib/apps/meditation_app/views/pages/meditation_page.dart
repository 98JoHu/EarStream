import 'package:provider/provider.dart';

import 'drawer_page.dart';
import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import '../meditation_modes/bio_adaptive_view.dart';
import '../meditation_modes/demo_view.dart';
import '../meditation_modes/timer_view.dart';
import '../../model/measurement.dart';

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
  final Sensor ppgSensor;
  final Sensor accelerometerSensor;
  final Sensor gyroscopeSensor;
  final SensorConfigurationProvider sensorConfigProvider;
  const MeditationPage({
    super.key,
    required this.ppgSensor,
    required this.accelerometerSensor,
    required this.gyroscopeSensor,
    required this.sensorConfigProvider,
  });

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
  late final Measurement _measurement;
  MeditationMode _selectedMode = MeditationMode.bioAdaptive;

  @override
  void initState() {
    super.initState();
    _measurement = Measurement(
      ppgSensor: widget.ppgSensor,
      accelerometerSensor: widget.accelerometerSensor,
      gyroscopeSensor: widget.gyroscopeSensor,
      sensorConfigProvider: widget.sensorConfigProvider,
    );
  }

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
          Provider<Measurement>(
            create: (_) => _measurement,
            child: _selectedMode.view,
          ),
        ],
      ),
    );
  }
}
