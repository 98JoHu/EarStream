import 'package:provider/provider.dart';

import 'drawer_page.dart';
import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import '../meditation_modes/bio_adaptive_view.dart';
import '../meditation_modes/demo_view.dart';
import '../meditation_modes/timer_view.dart';
import '../../model/user_account.dart';

enum MeditationMode {
  bioAdaptive(
    label: "Biosignal-Adaptive",
    icon: Icons.bolt,
    build: _bioAdaptiveView,
    description:
        'Stress-adaptive meditation is active and can respond to live biomarkers.',
  ),
  timer(
    label: "Timed",
    icon: Icons.alarm,
    build: _timerView,
    description: 'Meditation with a fixed time duration.',
  ),
  demo(
    label: "Demo",
    icon: Icons.play_circle_outline,
    build: _demoView,
    description: 'Demonstration of the meditation features.',
  );

  final String label;
  final IconData icon;
  final Widget Function(MeditationPage page) build;
  final String description;

  const MeditationMode({
    required this.label,
    required this.icon,
    required this.build,
    required this.description,
  });
}

Widget _bioAdaptiveView(MeditationPage page) => BioAdaptiveView(
      ppgSensor: page.ppgSensor,
      accelerometerSensor: page.accelerometerSensor,
      gyroscopeSensor: page.gyroscopeSensor,
      sensorConfigProvider: page.sensorConfigProvider,
    );
Widget _timerView(MeditationPage page) => const TimerView();
Widget _demoView(MeditationPage page) => DemoView(
      ppgSensor: page.ppgSensor,
      accelerometerSensor: page.accelerometerSensor,
      gyroscopeSensor: page.gyroscopeSensor,
      sensorConfigProvider: page.sensorConfigProvider,
    );

class MeditationPage extends StatefulWidget implements DrawerPage {
  final Sensor ppgSensor;
  final Sensor accelerometerSensor;
  final Sensor gyroscopeSensor;
  final SensorConfigurationProvider sensorConfigProvider;
  final UserAccount userAccount;
  final Wearable? wearable;

  const MeditationPage({
    super.key,
    required this.ppgSensor,
    required this.accelerometerSensor,
    required this.gyroscopeSensor,
    required this.sensorConfigProvider,
    required this.userAccount,
    this.wearable,
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
  MeditationMode? _selectedMode;

  @override
  Widget build(BuildContext context) {
    final selectedMode = _selectedMode;
    if (selectedMode == null) {
      return _ModePicker(
        onModeSelected: (mode) => setState(() => _selectedMode = mode),
      );
    }

    return MultiProvider(
      providers: [
        Provider<UserAccount>.value(value: widget.userAccount),
        Provider<Wearable?>.value(value: widget.wearable),
      ],
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  text: "Selected Mode: ",
                  style: Theme.of(context).textTheme.titleMedium,
                  children: [
                    TextSpan(
                      text: selectedMode.label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              selectedMode.build(widget),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModePicker extends StatelessWidget {
  final ValueChanged<MeditationMode> onModeSelected;

  const _ModePicker({required this.onModeSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Choose a meditation mode",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            for (final mode in MeditationMode.values) ...[
              Card(
                child: ListTile(
                  leading: Icon(mode.icon),
                  title: Text(mode.label),
                  onTap: () => onModeSelected(mode),
                  subtitle: Text(mode.description),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
