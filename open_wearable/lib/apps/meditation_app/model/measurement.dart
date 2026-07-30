import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

import 'user_account.dart';
import 'biometric_source.dart';
import 'stress_detector.dart';
import 'measurement_phase.dart';
import 'activity_tracker.dart' show ActivityLevel;
import 'meditation.dart' show BiometricMeditation;

class Measurement {
  final UserAccount userAccount;
  final Duration? meditationSegmentDuration;

  final BiometricSource _source;
  late final StressDetector _detector;
  late final MonitoringPhaseController _phaseController;

  final ValueNotifier<BiometricMeditation?> meditation = ValueNotifier(null);

  Measurement._({
    required this.userAccount,
    required BiometricSource source,
    required List<MonitoringPhase> phases,
    required StressThresholdProvider stressThresholdProvider,
    required BaselineHeartRateProvider baselineHeartRateProvider,
    this.meditationSegmentDuration,
  }) : _source = source {
    _detector = StressDetector(
      thresholds: stressThresholdProvider,
      baselineHeartRate: baselineHeartRateProvider,
    );
    _detector.stressLevel.addListener(_onStressLevelChanged);
    _phaseController = MonitoringPhaseController(
      ctx: PhaseContext(
        source: _source,
        detector: _detector,
      ),
      phases: phases,
    );
  }

  factory Measurement.live({
    required Sensor ppgSensor,
    required Sensor accelerometerSensor,
    required Sensor gyroscopeSensor,
    required SensorConfigurationProvider sensorConfigProvider,
    required UserAccount userAccount,
    double? demoThreshold,
    Duration? baselineAdjustmentDuration,
    Duration? meditationSegmentDuration,
    Duration? hrvMinimumWindow,
  }) {
    return Measurement._(
      userAccount: userAccount,
      source: SensorBiometricSource(
        ppgSensor: ppgSensor,
        accelerometerSensor: accelerometerSensor,
        gyroscopeSensor: gyroscopeSensor,
        sensorConfigProvider: sensorConfigProvider,
        hrvMinimumWindow: hrvMinimumWindow,
      ),
      phases: [
        CalibrationPhase(),
        BaselinePhase(userAccount: userAccount),
        StressMonitoringPhase(),
      ],
      stressThresholdProvider: () =>
          userAccount.stressThresholds(stressThreshold: demoThreshold),
      baselineHeartRateProvider: () => userAccount.baselineBiometrics.$1,
      meditationSegmentDuration: meditationSegmentDuration,
    );
  }

  factory Measurement.simulated({
    required UserAccount userAccount,
    required ActivityLevel restingActivityLevel,
    double? demoThreshold,
    Duration? baselineAdjustmentDuration,
    Duration? meditationSegmentDuration,
  }) {
    return Measurement._(
      userAccount: userAccount,
      source: SimulatedBiometricSource(
        startHeartRate: 50,
        peakHeartRate: 120,
        startRmssd: 80.0,
        peakRmssd: 20.0,
        restingActivityLevel: restingActivityLevel,
      ),
      phases: [StressMonitoringPhase()],
      stressThresholdProvider: () => (90, 40.0),
      baselineHeartRateProvider: () => 60,
      meditationSegmentDuration: meditationSegmentDuration,
    );
  }

  // Publish the heart rate and RMSSD
  Stream<int> get heartRate => _source.biometrics.map((b) => b.heartRate);
  Stream<double?> get rmssd => _source.biometrics.map((b) => b.rmssd);

  // Publish the stress level
  ValueListenable<StressLevel> get stressLevel => _detector.stressLevel;
  StressLevel get currentStressLevel => _detector.stressLevel.value;

  // Publish the monitoring phase and progress
  ValueListenable<MonitoringPhase> get monitoringPhase =>
      _phaseController.phase;
  ValueListenable<double?> get progress => _phaseController.progress;

  // Publish the activity level
  ValueListenable<ActivityLevel> get activityLevel => _source.activityLevel;

  void start() {
    _source.start();
    _detector.reset();
    _phaseController.start();
  }

  void pause() {
    _source.pause();
    _phaseController.pause();
    _stopMeditation();
  }

  void resume() {
    _source.resume();
    _phaseController.resume();
  }

  void dispose() {
    _source.dispose();
    _detector.stressLevel.removeListener(_onStressLevelChanged);
    _detector.dispose();
    _phaseController.dispose();
    meditation.value?.dispose();
    meditation.dispose();
  }

  void _onStressLevelChanged() {
    if (_detector.currentStressLevel == StressLevel.stressed &&
        meditation.value == null) {
      _startMeditation();
    }
  }

  void _startMeditation() {
    final session = BiometricMeditation(
      userAccount: userAccount,
      measurement: this,
      meditationSegmentDuration: meditationSegmentDuration,
    );
    meditation.value = session;

    session.start().catchError((error, stackTrace) {
      debugPrint('Error starting meditation: $error');
      debugPrint('$stackTrace');
    }).whenComplete(() {
      if (meditation.value == session) {
        meditation.value = null;
      }
    });
  }

  void _stopMeditation() {
    final session = meditation.value;
    if (session != null) {
      session.stop();
      meditation.value = null;
    }
  }
}
