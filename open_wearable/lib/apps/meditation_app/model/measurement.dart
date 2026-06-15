import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

enum ActivityLevel {
  resting(
    label: "Resting",
    icon: Icons.airline_seat_individual_suite,
  ),
  light(
    label: "Light",
    icon: Icons.directions_walk,
  ),
  moderate(
    label: "Moderate",
    icon: Icons.directions_run,
  ),
  vigorous(
    label: "Vigorous",
    icon: Icons.fitness_center,
  ),
  intense(
    label: "Intense",
    icon: Icons.local_fire_department,
  );

  final String label;
  final IconData icon;

  const ActivityLevel({
    required this.label,
    required this.icon,
  });
}

enum StressLevel {
  relaxed(
    label: "Relaxed",
    icon: Icons.spa_rounded,
    color: Colors.green,
    backgroundColor: Color(0xFFC8E6C9),
  ),
  stressed(
    label: "Stressed",
    icon: Icons.bolt_rounded,
    color: Colors.red,
    backgroundColor: Color(0xFFFFCDD2),
  );

  final String label;
  final IconData icon;
  final Color color;
  final Color backgroundColor;

  const StressLevel({
    required this.label,
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });
}

enum MonitoringPhase {
  calibration(
    label: "Calibration (30s)",
    icon: Icons.settings_outlined,
    duration: Duration(seconds: 30),
    color: Colors.orange,
  ),
  baseline(
    label: "Monitoring \u00b7 Baseline Adjustment",
    icon: Icons.straighten_outlined,
    duration: Duration(minutes: 5),
    color: Colors.blue,
  ),
  monitoring(
    label: "Monitoring",
    icon: Icons.monitor_heart,
    duration: Duration(),
    color: Color(0xFF4ECDC4),
  ),
  meditation(
    label: "Meditation",
    icon: Icons.self_improvement_outlined,
    duration: Duration(),
    color: Colors.purple,
  );

  final String label;
  final IconData icon;
  final Duration duration;
  final Color color;

  const MonitoringPhase({
    required this.label,
    required this.icon,
    required this.duration,
    required this.color,
  });
}

class Measurement extends ChangeNotifier {
  final Sensor ppgSensor;
  final Sensor accelerometerSensor;
  final Sensor gyroscopeSensor;
  final SensorConfigurationProvider sensorConfigProvider;

  Measurement({
    required this.ppgSensor,
    required this.accelerometerSensor,
    required this.gyroscopeSensor,
    required this.sensorConfigProvider,
  });

  ValueNotifier<ActivityLevel> get activityLevel => _activityLevel;
  ValueNotifier<StressLevel> get stressLevel => _stressLevel;
  ValueNotifier<MonitoringPhase> get monitoringPhase => _monitoringPhase;
  ValueNotifier<int> get heartRate => _heartRate;
  ValueNotifier<int> get rmssd => _rmssd;

  final ValueNotifier<ActivityLevel> _activityLevel =
      ValueNotifier(ActivityLevel.intense);
  final ValueNotifier<StressLevel> _stressLevel =
      ValueNotifier(StressLevel.stressed);
  final ValueNotifier<MonitoringPhase> _monitoringPhase =
      ValueNotifier(MonitoringPhase.calibration);
  final ValueNotifier<int> _heartRate = ValueNotifier(70);
  final ValueNotifier<int> _rmssd = ValueNotifier(50);

  void startMeasuring() {
    // Simulate changes in measurement values
    Future.delayed(const Duration(seconds: 5), () {
      _monitoringPhase.value = MonitoringPhase.baseline;
      _stressLevel.value = StressLevel.relaxed;
      _activityLevel.value = ActivityLevel.light;
    });

    Future.delayed(const Duration(seconds: 10), () {
      _monitoringPhase.value = MonitoringPhase.monitoring;
      _stressLevel.value = StressLevel.stressed;
      _activityLevel.value = ActivityLevel.moderate;
    });

    Future.delayed(const Duration(seconds: 15), () {
      _monitoringPhase.value = MonitoringPhase.meditation;
      _stressLevel.value = StressLevel.relaxed;
      _activityLevel.value = ActivityLevel.resting;
    });
  }
}
