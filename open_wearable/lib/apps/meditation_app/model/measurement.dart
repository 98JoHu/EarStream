import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

import 'user_account.dart';
import 'bio_adaptive_session_config.dart';
import 'biometric_source.dart';
import 'stress_detector.dart';
import 'measurement_phase.dart';
import 'activity_tracker.dart' show ActivityLevel;
import 'meditation.dart' show BiometricMeditation;
import 'hr_hrv_processor.dart' show HeartRateSample;

class Measurement {
  final UserAccount userAccount;
  final BioAdaptiveSessionConfig sessionConfig;

  final BiometricSource _source;
  late final StressDetector _detector;
  late final MonitoringPhaseController _phaseController;
  StreamSubscription<HeartRateSample>? _latestBiometricsSubscription;
  HeartRateSample? _latestBiometrics;

  final ValueNotifier<BiometricMeditation?> meditation = ValueNotifier(null);

  Measurement._({
    required this.userAccount,
    required BiometricSource source,
    required List<MonitoringPhase> phases,
    required StressThresholdProvider stressThresholdProvider,
    required BaselineHeartRateProvider baselineHeartRateProvider,
    required this.sessionConfig,
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
    BioAdaptiveSessionConfig sessionConfig = BioAdaptiveSessionConfig.standard,
  }) {
    return Measurement._(
      userAccount: userAccount,
      source: SensorBiometricSource(
        ppgSensor: ppgSensor,
        accelerometerSensor: accelerometerSensor,
        gyroscopeSensor: gyroscopeSensor,
        sensorConfigProvider: sensorConfigProvider,
        hrvMinimumWindow: sessionConfig.hrvMinimumWindow,
      ),
      phases: [
        if (sessionConfig.includeCalibration)
          CalibrationPhase(duration: sessionConfig.calibrationDuration),
        BaselinePhase(
          userAccount: userAccount,
          duration: sessionConfig.baselineDuration,
          computationMode: sessionConfig.baselineComputationMode,
        ),
        StressMonitoringPhase(),
      ],
      stressThresholdProvider: () => userAccount.stressThresholds(
        stressThreshold: sessionConfig.stressThresholdOverride,
      ),
      baselineHeartRateProvider: () => userAccount.baselineBiometrics.$1,
      sessionConfig: sessionConfig,
    );
  }

  factory Measurement.simulated({
    required UserAccount userAccount,
    required ActivityLevel restingActivityLevel,
    BioAdaptiveSessionConfig sessionConfig = BioAdaptiveSessionConfig.standard,
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
      sessionConfig: sessionConfig,
    );
  }

  // Publish the heart rate and RMSSD
  Stream<int> get heartRate => _source.biometrics.map((b) => b.heartRate);
  Stream<double?> get rmssd => _source.biometrics.map((b) => b.rmssd);

  // The latest values stay local and are only included in a cloud prompt when
  // the session's explicit prompt policy permits it.
  HeartRateSample? get latestBiometrics => _latestBiometrics;

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
    _latestBiometricsSubscription = _source.biometrics.listen((sample) {
      _latestBiometrics = sample;
    });
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
    _latestBiometricsSubscription?.cancel();
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
      meditationSegmentDuration: sessionConfig.meditationSegmentDuration,
      promptPolicy: sessionConfig.promptPolicy,
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
