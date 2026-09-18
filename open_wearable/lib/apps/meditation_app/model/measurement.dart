import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

import '../configs/bio_adaptive_mode_config.dart';
import 'user_account.dart';
import 'bio_adaptive_session_config.dart';
import 'meditation_analytics.dart';
import 'biometric_source.dart';
import 'stress_detector.dart';
import 'measurement_phase.dart';
import 'activity_tracker.dart' show ActivityLevel;
import 'meditation.dart' show BiometricMeditation, Meditation;
import 'hr_hrv_processor.dart' show HeartRateSample;
import 'monitoring_meditation_deadline.dart';

class Measurement {
  final UserAccount userAccount;
  final BioAdaptiveSessionConfig sessionConfig;
  final MeditationAnalyticsStore? analyticsStore;

  final BiometricSource _source;
  late final StressDetector _detector;
  late final MonitoringPhaseController _phaseController;
  late final MonitoringMeditationDeadline _meditationDeadline;
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
    this.analyticsStore,
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
    _meditationDeadline = MonitoringMeditationDeadline(
      delay: sessionConfig.guaranteedMeditationDelay,
      onElapsed: _onGuaranteedMeditationDeadline,
    );
    _phaseController.phase.addListener(_onMonitoringPhaseChanged);
  }

  factory Measurement.live({
    required Sensor ppgSensor,
    required Sensor accelerometerSensor,
    required Sensor gyroscopeSensor,
    required SensorConfigurationProvider sensorConfigProvider,
    required UserAccount userAccount,
    BioAdaptiveSessionConfig sessionConfig = BioAdaptiveSessionConfig.standard,
    MeditationAnalyticsStore? analyticsStore,
  }) {
    return Measurement._(
      userAccount: userAccount,
      source: SensorBiometricSource(
        ppgSensor: ppgSensor,
        accelerometerSensor: accelerometerSensor,
        gyroscopeSensor: gyroscopeSensor,
        sensorConfigProvider: sensorConfigProvider,
        hrvMinimumWindow: sessionConfig.hrvMinimumWindow,
        metricWindowDuration: sessionConfig.metricWindowDuration,
        publishBestEffortEstimates: sessionConfig.useBestEffortEstimates,
        startInCalibration: sessionConfig.includeCalibration,
      ),
      phases: [
        if (sessionConfig.includeCalibration)
          CalibrationPhase(duration: sessionConfig.calibrationDuration),
        BaselinePhase(
          userAccount: userAccount,
          duration: sessionConfig.baselineDuration,
          computationMode: sessionConfig.baselineComputationMode,
          useBestEffortAtDeadline: sessionConfig.useBestEffortEstimates,
        ),
        StressMonitoringPhase(),
      ],
      stressThresholdProvider: () => userAccount.stressThresholds(
        stressThreshold: sessionConfig.stressThresholdOverride,
      ),
      baselineHeartRateProvider: () => userAccount.baselineBiometrics.$1,
      sessionConfig: sessionConfig,
      analyticsStore: analyticsStore,
    );
  }

  factory Measurement.recordedStress({
    required UserAccount userAccount,
    required ActivityLevel restingActivityLevel,
    BioAdaptiveSessionConfig sessionConfig = BioAdaptiveSessionConfig.standard,
  }) {
    return Measurement._(
      userAccount: userAccount,
      source: RecordedStressBiometricSource(
        restingActivityLevel: restingActivityLevel,
      ),
      phases: [StressMonitoringPhase()],
      stressThresholdProvider: () => (
        BioAdaptiveModeConfig.recordedStressDetectionHeartRate,
        BioAdaptiveModeConfig.recordedStressDetectionRmssd,
      ),
      baselineHeartRateProvider: () =>
          RecordedStressBiometricSource.baselineHeartRate.round(),
      sessionConfig: sessionConfig,
    );
  }

  // Publish the heart rate and RMSSD
  Stream<int> get heartRate => _source.biometrics.map((b) => b.heartRate);
  Stream<double?> get rmssd => _source.biometrics.map((b) => b.rmssd);

  // The latest values stay local and are only included in a cloud prompt when
  // the session's explicit prompt policy permits it.
  HeartRateSample? get latestBiometrics => _latestBiometrics;
  int? get baselineHeartRate => userAccount.baselineHeartRate;
  double? get baselineRmssd => userAccount.baselineRMSSD;

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
    _meditationDeadline.reset();
    _source.start();
    _latestBiometricsSubscription = _source.biometrics.listen((sample) {
      _latestBiometrics = sample;
    });
    _detector.reset();
    _phaseController.start();
    _onMonitoringPhaseChanged();
  }

  void pause() {
    _meditationDeadline.pause();
    _source.pause();
    _phaseController.pause();
    _stopMeditation();
  }

  void resume() {
    _source.resume();
    _phaseController.resume();
    _meditationDeadline.resume();
  }

  void dispose() {
    _latestBiometricsSubscription?.cancel();
    _source.dispose();
    _detector.stressLevel.removeListener(_onStressLevelChanged);
    _phaseController.phase.removeListener(_onMonitoringPhaseChanged);
    _meditationDeadline.dispose();
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

  void _onMonitoringPhaseChanged() {
    if (_phaseController.current is StressMonitoringPhase) {
      _meditationDeadline.enterMonitoring();
    }
  }

  void _onGuaranteedMeditationDeadline() {
    if (_phaseController.current is StressMonitoringPhase &&
        meditation.value == null) {
      _startMeditation();
    }
  }

  void _startMeditation() {
    if (meditation.value != null) return;
    _meditationDeadline.satisfy();
    if (_source case final RecordedStressBiometricSource recordedStress) {
      recordedStress.startRelaxationScenario();
    }
    final session = BiometricMeditation(
      userAccount: userAccount,
      measurement: this,
      meditationSegmentDuration: sessionConfig.meditationSegmentDuration,
      promptPolicy: sessionConfig.promptPolicy,
      analyticsStore: analyticsStore,
      analyticsMode:
          analyticsStore == null ? null : MeditationAnalyticsMode.bioAdaptive,
    );
    meditation.value = session;

    unawaited(
      session.start().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Error starting meditation: $error');
        debugPrint('$stackTrace');
        if (meditation.value == session) {
          meditation.value = null;
        }
        session.dispose();
      }),
    );
  }

  void _stopMeditation() {
    final session = meditation.value;
    if (session != null) dismissMeditation(session);
  }

  /// Removes a completed or manually stopped meditation from the UI and
  /// releases its audio resources. Natural completion remains visible until
  /// the attendee has acknowledged the success card.
  void dismissMeditation(Meditation session) {
    if (meditation.value != session) return;
    meditation.value = null;
    unawaited(session.stop().whenComplete(session.dispose));
  }
}
