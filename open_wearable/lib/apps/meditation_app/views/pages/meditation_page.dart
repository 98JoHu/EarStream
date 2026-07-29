import 'package:provider/provider.dart';

import 'drawer_page.dart';
import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import '../meditation_modes/bio_adaptive_view.dart';
import '../meditation_modes/demo_view.dart';
import '../meditation_modes/timer_view.dart';
import '../../model/measurement.dart';
import '../../model/user_account.dart';

enum MeditationMode {
  bioAdaptive(
    label: "Biosignal-Adaptive",
    icon: Icons.bolt,
    view: BioAdaptiveView(),
    description:
        'Stress-adaptive meditation is active and can respond to live biomarkers.',
  ),
  timer(
    label: "Timed",
    icon: Icons.alarm,
    view: TimerView(),
    description: 'Meditation with a fixed time duration.',
  ),
  demo(
    label: "Demo",
    icon: Icons.play_circle_outline,
    view: DemoView(),
    description: 'Demonstration of the meditation features.',
  );

  final String label;
  final IconData icon;
  final Widget view;
  final String description;

  const MeditationMode({
    required this.label,
    required this.icon,
    required this.view,
    required this.description,
  });
}

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
  Measurement? _measurement;
  MeditationMode? _selectedMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _measurement = Measurement(
          ppgSensor: widget.ppgSensor,
          accelerometerSensor: widget.accelerometerSensor,
          gyroscopeSensor: widget.gyroscopeSensor,
          sensorConfigProvider: widget.sensorConfigProvider,
          userAccount: widget.userAccount,
        );
      });
    });
  }

  @override
  void dispose() {
    _measurement?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_measurement == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final selectedMode = _selectedMode;
    if (selectedMode == null) {
      return _ModePicker(
        onModeSelected: (mode) => setState(() => _selectedMode = mode),
      );
    }

    return MultiProvider(
      providers: [
        Provider<Measurement>(create: (_) => _measurement!),
        Provider<UserAccount>(create: (_) => widget.userAccount),
        Provider<Wearable?>(create: (_) => widget.wearable),
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
              selectedMode.view,
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
