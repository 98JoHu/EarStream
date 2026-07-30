import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'dart:async';
import 'dart:math';
import 'user_account.dart';
import 'activity_tracker.dart';
import 'meditation.dart';
import 'hr_hrv_processor.dart';

enum EarstreamState { idle, running, stopped }

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
    nextPhase: MonitoringPhase.baseline,
  ),
  baseline(
    label: "Monitoring \u00b7 Baseline Adjustment",
    icon: Icons.straighten_outlined,
    duration: Duration(minutes: 5),
    color: Colors.blue,
    nextPhase: MonitoringPhase.monitoring,
  ),
  monitoring(
    label: "Monitoring",
    icon: Icons.monitor_heart,
    color: Color(0xFF4ECDC4),
  ),
  meditation(
    label: "Meditation",
    icon: Icons.self_improvement_outlined,
    color: Colors.purple,
  );

  final String label;
  final IconData icon;
  final Duration? duration;
  final Color color;
  final MonitoringPhase? nextPhase;

  const MonitoringPhase({
    required this.label,
    required this.icon,
    this.duration,
    required this.color,
    this.nextPhase,
  });
}

class PpgOpticalSample {
  final int timestamp;
  final double red;
  final double ir;
  final double green;
  final double ambient;

  const PpgOpticalSample({
    required this.timestamp,
    required this.red,
    required this.ir,
    required this.green,
    required this.ambient,
  });
}

class HeartRateSample {
  final int heartRate;
  final double? rmssd;

  const HeartRateSample({
    required this.heartRate,
    required this.rmssd,
  });
}

class Measurement {
  final Sensor ppgSensor;
  final Sensor accelerometerSensor;
  final Sensor gyroscopeSensor;
  final SensorConfigurationProvider sensorConfigProvider;
  final UserAccount userAccount;

  late final Stream<PpgOpticalSample> _ppgStream;
  late final Stream<PpgMotionSample> _accelerometerStream;
  late final HrHrvProcessor _processor;
  late final ActivityTracker _activityTracker;
  StreamSubscription<PpgOpticalSample>? _metricSubscription;
  StreamSubscription<PpgMotionSample>? _accelMetricSubscription;
  StreamSubscription<HeartRateSample>? _stressSubscription;
  Stream<int> get heartRate =>
      _processor.biometricStream.map((biometrics) => biometrics.heartRate);
  Stream<double?> get rmssd =>
      _processor.biometricStream.map((biometrics) => biometrics.rmssd);
  HeartRateSample? get latestBiometrics => _processor.latestSample;

  // Expose calculated values to UI
  ValueNotifier<StressLevel> stressLevel = ValueNotifier(StressLevel.relaxed);
  StressLevel get currentStressLevel => stressLevel.value;
  ValueNotifier<MonitoringPhase> monitoringPhase =
      ValueNotifier(MonitoringPhase.calibration);
  ValueNotifier<ActivityLevel> get activityLevel =>
      _activityTracker.activityLevel;
  ValueNotifier<BiometricMeditation?> meditation = ValueNotifier(null);

  /// Bumped by [reset]. The stream-driven widgets (the HR/RMSSD tiles and the
  /// heart-rate chart) hold their last value in widget state, and a reset
  /// emits nothing new to overwrite it — so the UI keys its subtree on this
  /// counter and lets Flutter discard that state instead.
  final ValueNotifier<int> resetGeneration = ValueNotifier(0);

  // Fields for handling the phases
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  EarstreamState _state = EarstreamState.idle;
  EarstreamState get state => _state;
  ValueNotifier<double?> progress = ValueNotifier(null);

  // Scripted stress-demo scenario (see simulateStress()), ported from the
  // main branch's MockHrSensor, with the same Ornstein-Uhlenbeck wandering on
  // top. Unlike the original it is anchored to the account's *live* stress
  // thresholds rather than to fixed BPM/ms constants: those thresholds derive
  // from the user's baseline, which varies enough with age/gender/fitness that
  // a fixed 97 BPM / 12 ms peak does not necessarily cross them, and the demo
  // would then never fire a meditation at all.
  Timer? _stressScenarioTimer;
  DateTime? _stressScenarioStartTime;
  double _scenarioHrOuState = 0;
  double _scenarioHrvOuState = 0;
  double _scenarioGaussianSpare = 0;
  bool _scenarioHasGaussianSpare = false;
  final Random _scenarioRandom = Random();

  double _scenarioCalmHr = 72;
  double _scenarioCalmHrv = 42;
  double _scenarioStressedHr = 90;
  double _scenarioStressedHrv = 20;
  double _scenarioBuildUpIntensity = 0.3;
  double _scenarioHrOuSigmaStep = 0.763;

  static const double _scenarioOuAlpha = 0.9672; // exp(-1/30), 30s time const


  // Scenario timeline, in seconds from the button press: a rising build-up
  // that deliberately stops short of the threshold, a spike that crosses it
  // and fires the meditation, a stressed plateau long enough for a segment or
  // two to play, then a recovery back to baseline which flips the stress level
  // and so trips BiometricMeditation.checkEarlyExit().
  static const double _scenarioBuildUpEndSec = 20;
  static const double _scenarioSpikeEndSec = 35;
  static const double _scenarioPlateauEndSec = 80;
  static const double _scenarioRecoveryEndSec = 120;

  /// Consecutive calm readings required before a stressed session is declared
  /// recovered. At the 3s scenario tick that is ~9s — enough that one noisy
  /// RMSSD sample cannot cut a meditation short.
  static const int _calmReadingsToRecover = 3;
  int _calmReadings = 0;

  // Values for the demo view behaviour
  double? demoThreshold;
  Duration? baselineAdjustmentDuration;
  Duration? meditationSegmentDuration;

  Measurement({
    required this.ppgSensor,
    required this.accelerometerSensor,
    required this.gyroscopeSensor,
    required this.sensorConfigProvider,
    required this.userAccount,
  }) {
    final double sampleFreq = _configureSensorForStreaming(
      ppgSensor,
      sensorConfigProvider,
      fallbackFrequency: 100.0,
      targetFrequencyHz: 200,
    );
    _configureSensorForStreaming(
      accelerometerSensor,
      sensorConfigProvider,
      fallbackFrequency: 100.0,
      targetFrequencyHz: 100,
    );
    _configureSensorForStreaming(
      gyroscopeSensor,
      sensorConfigProvider,
      fallbackFrequency: 100.0,
      targetFrequencyHz: 200,
    );

    _ppgStream = ppgSensor.sensorStream
        .map<PpgOpticalSample?>((data) {
          final values = _sensorValuesAsDoubles(data);
          if (values == null) {
            return null;
          }
          return _extractPpgOpticalSample(ppgSensor, data, values);
        })
        .where((sample) => sample != null)
        .cast<PpgOpticalSample>()
        .asBroadcastStream();

    _accelerometerStream = accelerometerSensor.sensorStream
        .map<PpgMotionSample?>((data) {
          final values = _sensorValuesAsDoubles(data);
          if (values == null) {
            return null;
          }
          return _extractImuMotionSample(
            accelerometerSensor,
            data,
            values,
          );
        })
        .where((sample) => sample != null)
        .cast<PpgMotionSample>()
        .asBroadcastStream();

    final gyroscopeStream = gyroscopeSensor.sensorStream
        .map<PpgMotionSample?>((data) {
          final values = _sensorValuesAsDoubles(data);
          if (values == null) {
            return null;
          }
          return _extractImuMotionSample(
            gyroscopeSensor,
            data,
            values,
          );
        })
        .where((sample) => sample != null)
        .cast<PpgMotionSample>()
        .asBroadcastStream();

    _processor = HrHrvProcessor(
      sampleFreq: sampleFreq,
      timestampExponent: ppgSensor.timestampExponent,
    );
    _activityTracker = ActivityTracker(
      accelerometerStream: _accelerometerStream,
      gyroscopeStream: gyroscopeStream,
      timestampExponentAccelerometer: accelerometerSensor.timestampExponent,
      timestampExponentGyroscope: gyroscopeSensor.timestampExponent,
    );
  }

  void start({
    double? demoThreshold,
    Duration? baselineAdjustmentDuration,
    Duration? meditationSegmentDuration,
    Duration? hrvMinimumWindow,
  }) {
    // if any of the parameters are provided, override the default values for this session
    this.demoThreshold = demoThreshold;
    this.baselineAdjustmentDuration = baselineAdjustmentDuration;
    this.meditationSegmentDuration = meditationSegmentDuration;
    // Shortens how much RR history must accumulate before RMSSD is reported.
    // Only demo flows set this — see HrHrvProcessor.hrvMinimumWindow.
    if (hrvMinimumWindow != null) {
      _processor.hrvMinimumWindow = hrvMinimumWindow;
    }

    // Reset the stopwatch to 0 and start it
    _stopwatch
      ..reset()
      ..start();
    // App is now running
    _state = EarstreamState.running;
    // Start with calibration phase
    monitoringPhase.value = MonitoringPhase.calibration;
    // Detect activity level
    _activityTracker.start();

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // If the user has provided a custom baseline adjustment duration, use it; otherwise, use the default duration for the current phase
      bool changeBaselineDuration = baselineAdjustmentDuration != null &&
          monitoringPhase.value == MonitoringPhase.baseline;
      final duration = changeBaselineDuration
          ? baselineAdjustmentDuration
          : monitoringPhase.value.duration;
      if (duration == null) {
        progress.value = null;
        return;
      }
      progress.value =
          _stopwatch.elapsed.inMilliseconds / duration.inMilliseconds;

      // Check if the current phase duration has elapsed
      if (_stopwatch.elapsed >= duration) {
        // Move to the next phase
        monitoringPhase.value = monitoringPhase.value.nextPhase!;
        // Reset the stopwatch for the next phase
        _stopwatch
          ..reset()
          ..start();
        // Start the subscription (if any) for the phase just entered
        _activatePhaseSubscription();
      }
    });

    // Listen to the PPG stream and process incoming samples => HR and HRV
    _metricSubscription?.cancel();
    _metricSubscription = _ppgStream.listen((data) {
      _processor.processPpgSample(
        data.timestamp,
        data.red,
        data.ir,
        data.green,
        data.ambient,
      );
    });
    // Feed the accelerometer to the processor for motion cancellation/gating
    _accelMetricSubscription?.cancel();
    _accelMetricSubscription = _accelerometerStream.listen((data) {
      _processor.processAccelerometerSample(
        data.timestamp,
        data.x,
        data.y,
        data.z,
      );
    });
  }

  void stop() {
    // Stop the stopwatch
    _stopwatch.stop();
    // App is now stopped
    _state = EarstreamState.stopped;
    // Stop detecting activity level
    _activityTracker.stop();
    // Stop listening to the PPG and accelerometer streams
    _metricSubscription?.cancel();
    _accelMetricSubscription?.cancel();
    _stressSubscription?.cancel();
    // Stop any simulated stress scenario
    _stressScenarioTimer?.cancel();
    // Stop any ongoing meditation
    if (meditation.value != null) {
      meditation.value!.stop();
      meditation.value = null;
    }
  }

  void resume() {
    // Resume the stopwatch
    _stopwatch.start();
    // App is now running
    _state = EarstreamState.running;
    // Resume detecting activity level
    _activityTracker.start();
    // Resume listening to the PPG stream
    _metricSubscription?.cancel();
    _metricSubscription = _ppgStream.listen((data) {
      _processor.processPpgSample(
        data.timestamp,
        data.red,
        data.ir,
        data.green,
        data.ambient,
      );
    });
    // Resume listening to the accelerometer stream
    _accelMetricSubscription?.cancel();
    _accelMetricSubscription = _accelerometerStream.listen((data) {
      _processor.processAccelerometerSample(
        data.timestamp,
        data.x,
        data.y,
        data.z,
      );
    });
    // Resume with current phase
    _activatePhaseSubscription();
  }

  /// Starts the stress-detection subscription (if any) for the current
  /// [monitoringPhase] value. Called both when entering a new phase (see the
  /// ticker in [start]) and when [resume]ing into whatever phase was active.
  void _activatePhaseSubscription() {
    switch (monitoringPhase.value) {
      case MonitoringPhase.calibration:
        break;
      case MonitoringPhase.baseline:
        _stressSubscription?.cancel();
        _stressSubscription = adjustBaseline();
        break;
      case MonitoringPhase.monitoring:
        _stressSubscription?.cancel();
        _stressSubscription = monitorStress();
        break;
      case MonitoringPhase.meditation:
        // if there was a meditation session ongoing, it has been stopped
        monitoringPhase.value = MonitoringPhase.monitoring;
        _stressSubscription?.cancel();
        _stressSubscription = monitorStress();
        break;
    }
  }

  void reset() {
    // Reset the stopwatch
    _stopwatch
      ..stop()
      ..reset();
    // Cancel ticker watching for phase duration
    _ticker?.cancel();
    // App is now idle
    _state = EarstreamState.idle;
    // Reset the monitoring phase to calibration
    monitoringPhase.value = MonitoringPhase.calibration;
    // Reset stress level to relaxed
    stressLevel.value = StressLevel.relaxed;
    // Reset activity tracker
    _activityTracker.reset();
    // Stop listening to the PPG stream and heart rate/HRV processing
    _metricSubscription?.cancel();
    _accelMetricSubscription?.cancel();
    _stressSubscription?.cancel();
    // Stop any simulated stress scenario
    _stressScenarioTimer?.cancel();
    // Stop any ongoing meditation
    if (meditation.value != null) {
      meditation.value!.stop();
      meditation.value = null;
    }
    // Reset filters from the HR/HRV processor
    _processor.reset();
    // Drop the stale HR/RMSSD readouts and chart trace still held in widget
    // state (see resetGeneration).
    resetGeneration.value++;
  }

  void dispose() {
    // Cancel the ticker and stopwatch
    _ticker?.cancel();
    // Cancel all stream subscriptions if they are active
    _metricSubscription?.cancel();
    _accelMetricSubscription?.cancel();
    _stressSubscription?.cancel();
    _stressScenarioTimer?.cancel();
    // Dispose of the activity tracker and HR/HRV processor
    _activityTracker.dispose();
    _processor.dispose();
    // Dispose of the ValueNotifiers
    stressLevel.dispose();
    monitoringPhase.dispose();
    progress.dispose();
    resetGeneration.dispose();
    if (meditation.value != null) {
      meditation.value!.dispose();
    }
    meditation.dispose();
    // Turn off the sensors to save battery. Deferred to a microtask because
    // this notifies SensorConfigurationProvider, an ancestor of this widget;
    // calling that synchronously here would notify it while the widget tree
    // is still locked for this disposal pass ("setState() or
    // markNeedsBuild() called when widget tree was locked").
    scheduleMicrotask(() {
      _turnOffSensor(ppgSensor);
      _turnOffSensor(accelerometerSensor);
      _turnOffSensor(gyroscopeSensor);
    });
  }

  StreamSubscription<HeartRateSample> adjustBaseline() {
    final (heartRateThreshold, rmssdThreshold) = userAccount.baselineBiometrics;
    final startTime = DateTime.now();

    final subscription = _processor.biometricStream.listen((data) {
      final int elapsedSeconds =
          DateTime.now().difference(startTime).inMilliseconds;
      double timeRatio =
          elapsedSeconds / MonitoringPhase.baseline.duration!.inMilliseconds;
      timeRatio = timeRatio.clamp(0.0, 1.0);

      final double studyWeight = timeRatio * 0.3;
      final double measuredWeight = 1.0 - studyWeight;

      final (currentHeartRate, currentRmssd) = (data.heartRate, data.rmssd);

      final dynamicHeartRate =
          (studyWeight * heartRateThreshold + measuredWeight * currentHeartRate)
              .round();
      userAccount.baselineHeartRate = dynamicHeartRate;
      if (currentRmssd != null) {
        final dynamicRmssdThreshold =
            studyWeight * rmssdThreshold + measuredWeight * currentRmssd;
        userAccount.baselineRMSSD = dynamicRmssdThreshold;
      }
    });

    return subscription;
  }

  StreamSubscription<HeartRateSample> monitorStress() {
    // Detect stress
    final subscription = _processor.biometricStream.listen((data) {
      final (heartRate, rmssd) = (data.heartRate, data.rmssd);

      if (stressLevel.value == StressLevel.stressed) {
        _trackRecovery(heartRate, rmssd);
        return;
      }
      _calmReadings = 0;

      // if user is highly active, suppress stress detection
      if (_activityTracker.shouldSupressStressDetection()) {
        return;
      }

      // Check if the user is stressed based on heart rate and RMSSD thresholds
      if (checkStressLevel(heartRate, rmssd) == StressLevel.stressed) {
        // Start a meditation session if the user is stressed
        stressLevel.value = StressLevel.stressed;
        monitoringPhase.value = MonitoringPhase.meditation;
        _startMeditation();
      }
    });
    return subscription;
  }

  /// Watches an already-stressed session for a return to baseline.
  ///
  /// [BiometricMeditation.checkEarlyExit] ends the session once the stress
  /// level flips back to relaxed, so without this the flag would never clear
  /// and every meditation would run its full segment count regardless of how
  /// the user's biometrics recovered.
  void _trackRecovery(int heartRate, double? rmssd) {
    // RMSSD is null until enough RR history has accumulated. checkStressLevel
    // reads that as "relaxed", which would end a meditation on missing data
    // rather than on real recovery — so skip those samples entirely.
    if (rmssd == null) {
      return;
    }
    if (checkStressLevel(heartRate, rmssd) == StressLevel.stressed) {
      _calmReadings = 0;
      return;
    }
    _calmReadings++;
    if (_calmReadings >= _calmReadingsToRecover) {
      _calmReadings = 0;
      stressLevel.value = StressLevel.relaxed;
    }
  }

  void _startMeditation() {
    final session = BiometricMeditation(
      userAccount: userAccount,
      measurement: this,
      meditationSegmentDuration: meditationSegmentDuration,
    );
    meditation.value = session;
    // start() completes when the session finishes — either by running out of
    // segments or by exiting early on recovery. Either way the monitoring
    // phase has to be handed back, or the UI stays stuck on "Meditation" and
    // a later stress episode has nothing to transition from. The error branch
    // matters as much as the success one: a TTS or playback failure that
    // escaped start() would otherwise strand the session on screen forever.
    session.start().catchError((Object error, StackTrace stack) {
      debugPrint('Meditation session failed: $error\n$stack');
    }).whenComplete(() {
      if (meditation.value != session) {
        return; // superseded or torn down; whoever replaced it owns the phase
      }
      if (monitoringPhase.value == MonitoringPhase.meditation) {
        monitoringPhase.value = MonitoringPhase.monitoring;
      }
    });
  }

  void simulateStress() {
    // Cancel any existing subscriptions or timers
    _metricSubscription?.cancel();
    _accelMetricSubscription?.cancel();
    _stressSubscription?.cancel();

    // Re-running the scenario over a session still playing would leave two
    // meditations speaking over each other.
    if (meditation.value != null) {
      meditation.value!.stop();
      meditation.value = null;
    }

    // Start a new timer for the stress scenario
    _stressScenarioTimer?.cancel();
    _stressScenarioStartTime = DateTime.now();

    // Reset the Ornstein-Uhlenbeck states for HR and HRV
    _scenarioHrOuState = 0;
    _scenarioHrvOuState = 0;
    // A stressed level left over from an earlier episode would send every
    // sample down the recovery path and stop the scenario ever triggering.
    _calmReadings = 0;
    stressLevel.value = StressLevel.relaxed;

    _prepareScenarioAnchors();

    // Start a periodic timer to simulate HR and HRV values every 3s
    _stressScenarioTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final tSec =
          DateTime.now().difference(_stressScenarioStartTime!).inSeconds;
      final (hr, hrv) = _scenarioValues(tSec.toDouble());

      // Mean-reverting random walk around the deterministic trend, same as
      // MockHrSensor: gives the curve a realistic wobble instead of a
      // perfectly smooth ramp.
      _scenarioHrOuState = (_scenarioOuAlpha * _scenarioHrOuState) +
          (_scenarioHrOuSigmaStep * _scenarioGaussian());
      final hrvOuSigma = (hrv * 0.025).clamp(0.5, 3.0);
      _scenarioHrvOuState = (_scenarioOuAlpha * _scenarioHrvOuState) +
          (hrvOuSigma * _scenarioGaussian());

      final noisyHr = (hr + _scenarioHrOuState).clamp(40.0, 120.0);
      final noisyHrv = (hrv + _scenarioHrvOuState).clamp(1.0, 200.0);
      _processor.emitSimulatedSample(noisyHr.round(), noisyHrv);
    });

    // Move to the monitoring phase
    monitoringPhase.value = MonitoringPhase.monitoring;
    // Simulate stress on activity tracker
    _activityTracker.simulateStress();
    // Start monitoring stress based on the simulated HR and HRV values
    _stressSubscription = monitorStress();
  }

  /// Pins the scenario's calm and stressed endpoints either side of the
  /// account's current stress thresholds, so the spike is guaranteed to cross
  /// them however the baseline works out.
  void _prepareScenarioAnchors() {
    final (heartRateThreshold, rmssdThreshold) =
        userAccount.stressThresholds(stressThreshold: demoThreshold);
    final (baselineHeartRate, baselineRmssd) = userAccount.baselineBiometrics;

    final anchors = computeScenarioAnchors(
      baselineHeartRate: baselineHeartRate,
      baselineRmssd: baselineRmssd,
      heartRateThreshold: heartRateThreshold,
      rmssdThreshold: rmssdThreshold,
    );
    _scenarioCalmHr = anchors.calmHr;
    _scenarioCalmHrv = anchors.calmHrv;
    _scenarioStressedHr = anchors.stressedHr;
    _scenarioStressedHrv = anchors.stressedHrv;
    _scenarioBuildUpIntensity = anchors.buildUpIntensity;
    _scenarioHrOuSigmaStep = anchors.hrOuSigmaStep;
  }

  StressLevel checkStressLevel(int heartRate, double? rmssd) {
    // determine the stress thresholds based on the user's baseline biometrics and any provided demo threshold
    final (heartRateThreshold, rmssdThreshold) =
        userAccount.stressThresholds(stressThreshold: demoThreshold);

    // if heart rate is above the threshold and RMSSD is below the threshold, then the user is stressed
    if (heartRate > heartRateThreshold &&
        rmssd != null &&
        rmssd < rmssdThreshold) {
      return StressLevel.stressed;
    }
    return StressLevel.relaxed;
  }

  /// Deterministic HR/HRV arc for the scripted demo, as a fraction of the way
  /// from the account's calm baseline (0) to comfortably past its stress
  /// thresholds (1). See the timeline constants for the phases.
  double _scenarioIntensity(double tSec) {
    if (tSec <= _scenarioBuildUpEndSec) {
      return _scenarioBuildUpIntensity * (tSec / _scenarioBuildUpEndSec);
    }
    if (tSec <= _scenarioSpikeEndSec) {
      final frac = (tSec - _scenarioBuildUpEndSec) /
          (_scenarioSpikeEndSec - _scenarioBuildUpEndSec);
      return _scenarioBuildUpIntensity +
          (1.0 - _scenarioBuildUpIntensity) * frac;
    }
    if (tSec <= _scenarioPlateauEndSec) {
      return 1.0;
    }
    if (tSec <= _scenarioRecoveryEndSec) {
      final frac = (tSec - _scenarioPlateauEndSec) /
          (_scenarioRecoveryEndSec - _scenarioPlateauEndSec);
      return 1.0 - frac;
    }
    return 0.0;
  }

  (double hr, double hrv) _scenarioValues(double tSec) {
    final intensity = _scenarioIntensity(tSec);
    final hr =
        _scenarioCalmHr + (_scenarioStressedHr - _scenarioCalmHr) * intensity;
    final hrv = _scenarioCalmHrv +
        (_scenarioStressedHrv - _scenarioCalmHrv) * intensity;
    return (hr.clamp(40.0, 120.0), hrv.clamp(1.0, 200.0));
  }

  /// Polar Box-Muller transform — standard-normal samples for the scenario's
  /// Ornstein-Uhlenbeck wandering (same algorithm as MockHrSensor).
  double _scenarioGaussian() {
    if (_scenarioHasGaussianSpare) {
      _scenarioHasGaussianSpare = false;
      return _scenarioGaussianSpare;
    }
    double u, v, s;
    do {
      u = _scenarioRandom.nextDouble() * 2 - 1;
      v = _scenarioRandom.nextDouble() * 2 - 1;
      s = u * u + v * v;
    } while (s >= 1.0 || s == 0.0);
    final mul = sqrt(-2.0 * log(s) / s);
    _scenarioGaussianSpare = v * mul;
    _scenarioHasGaussianSpare = true;
    return u * mul;
  }

  List<double>? _sensorValuesAsDoubles(SensorValue data) {
    if (data is SensorDoubleValue) {
      return data.values;
    }
    if (data is SensorIntValue) {
      return data.values
          .map((value) => value.toDouble())
          .toList(growable: false);
    }
    return null;
  }

  PpgOpticalSample? _extractPpgOpticalSample(
    Sensor sensor,
    SensorValue data,
    List<double> values,
  ) {
    if (values.isEmpty) {
      return null;
    }

    int? findAxisIndex(List<String> keywords) {
      for (var i = 0; i < sensor.axisNames.length; i++) {
        final axis = sensor.axisNames[i].toLowerCase();
        if (keywords.any(axis.contains)) {
          return i;
        }
      }
      return null;
    }

    double valueAt(int? index, double fallback) {
      if (index != null && index >= 0 && index < values.length) {
        return values[index];
      }
      return fallback;
    }

    final fallbackRed = values[0];
    final fallbackIr = values.length > 1 ? values[1] : fallbackRed;
    final fallbackGreen = values.length > 2 ? values[2] : fallbackRed;
    final fallbackAmbient = values.length > 3 ? values[3] : 0.0;

    // Usually channels are [red, ir, green, ambient], but we prefer axis-name
    // matching when available to avoid firmware-order mismatches.
    final red = valueAt(findAxisIndex(['red']), fallbackRed);
    final ir = valueAt(findAxisIndex(['ir', 'infrared']), fallbackIr);
    final green = valueAt(findAxisIndex(['green']), fallbackGreen);
    final ambient = valueAt(findAxisIndex(['ambient']), fallbackAmbient);

    return PpgOpticalSample(
      timestamp: data.timestamp,
      red: red,
      ir: ir,
      green: green,
      ambient: ambient,
    );
  }

  PpgMotionSample _extractImuMotionSample(
    Sensor sensor,
    SensorValue data,
    List<double> values,
  ) {
    int? findAxisIndex(List<String> keywords) {
      for (var i = 0; i < sensor.axisNames.length; i++) {
        final axis = sensor.axisNames[i].toLowerCase();
        if (keywords.any(axis.contains)) {
          return i;
        }
      }
      return null;
    }

    double valueAt(int? index, double fallback) {
      if (index != null && index >= 0 && index < values.length) {
        return values[index];
      }
      return fallback;
    }

    final fallbackX = values.isNotEmpty ? values[0] : 0.0;
    final fallbackY = values.length > 1 ? values[1] : 0.0;
    final fallbackZ = values.length > 2 ? values[2] : 0.0;

    final x = valueAt(findAxisIndex(['x']), fallbackX);
    final y = valueAt(findAxisIndex(['y']), fallbackY);
    final z = valueAt(findAxisIndex(['z']), fallbackZ);

    return PpgMotionSample(
      timestamp: data.timestamp,
      x: x,
      y: y,
      z: z,
    );
  }

  void _turnOffSensor(Sensor sensor) {
    final configuration = sensor.relatedConfigurations.firstOrNull;
    final offValue = configuration?.offValue;
    if (configuration == null || offValue == null) {
      return;
    }

    sensorConfigProvider.addSensorConfiguration(
      configuration,
      offValue,
      markPending: false,
    );
    configuration.setConfiguration(offValue);
  }

  double _configureSensorForStreaming(
    Sensor sensor,
    SensorConfigurationProvider configProvider, {
    required double fallbackFrequency,
    required int targetFrequencyHz,
  }) {
    final configuration = sensor.relatedConfigurations.firstOrNull;
    if (configuration == null) {
      return fallbackFrequency;
    }

    if (configuration is ConfigurableSensorConfiguration &&
        configuration.availableOptions.contains(StreamSensorConfigOption())) {
      configProvider.addSensorConfigurationOption(
        configuration,
        StreamSensorConfigOption(),
        markPending: false,
      );
    }

    final values = configProvider.getSensorConfigurationValues(
      configuration,
      distinct: true,
    );
    SensorConfigurationValue? appliedValue;
    if (values.isNotEmpty) {
      appliedValue = _selectBestConfigurationValue(
        values,
        targetFrequencyHz: targetFrequencyHz,
      );
      configProvider.addSensorConfiguration(
        configuration,
        appliedValue,
        markPending: false,
      );
    }

    final selectedValue =
        configProvider.getSelectedConfigurationValue(configuration) ??
            appliedValue;
    if (selectedValue != null) {
      configuration.setConfiguration(selectedValue);
    }

    if (selectedValue is SensorFrequencyConfigurationValue) {
      return selectedValue.frequencyHz;
    }

    return fallbackFrequency;
  }

  SensorConfigurationValue _selectBestConfigurationValue(
    List<SensorConfigurationValue> values, {
    required int targetFrequencyHz,
  }) {
    final frequencyValues =
        values.whereType<SensorFrequencyConfigurationValue>().toList();
    if (frequencyValues.isEmpty) {
      return values.first;
    }

    SensorFrequencyConfigurationValue? nextBigger;
    SensorFrequencyConfigurationValue? maxValue;
    for (final value in frequencyValues) {
      if (maxValue == null || value.frequencyHz > maxValue.frequencyHz) {
        maxValue = value;
      }
      if (value.frequencyHz >= targetFrequencyHz &&
          (nextBigger == null || value.frequencyHz < nextBigger.frequencyHz)) {
        nextBigger = value;
      }
    }

    return nextBigger ?? maxValue ?? values.first;
  }
}

/// How far past the stress thresholds the scripted demo peak sits. Enough
/// margin that the scenario's random wandering cannot land the peak back on
/// the calm side of the threshold.
const double _scenarioStressOvershoot = 0.10;

/// Endpoints for the scripted stress demo, pinned either side of the account's
/// live stress thresholds.
///
/// Lifted out of [Measurement] so the guarantee the demo rests on — that the
/// spike always crosses the threshold and the recovery always falls back below
/// it, for *any* profile the baseline defaults can produce — is checkable
/// without standing up sensors.
@visibleForTesting
({
  double calmHr,
  double calmHrv,
  double stressedHr,
  double stressedHrv,
  double buildUpIntensity,
  double hrOuSigmaStep,
}) computeScenarioAnchors({
  required int baselineHeartRate,
  required double baselineRmssd,
  required int heartRateThreshold,
  required double rmssdThreshold,
}) {
  final calmHr = baselineHeartRate.toDouble();
  final calmHrv = baselineRmssd;
  final stressedHr = heartRateThreshold * (1 + _scenarioStressOvershoot);
  final stressedHrv = rmssdThreshold * (1 - _scenarioStressOvershoot);

  // Where along the calm -> stressed ramp each threshold is crossed. The
  // build-up stops short of the earlier of the two so that the rising trend
  // stays visibly sub-threshold until the spike.
  double crossing(double calm, double threshold, double stressed) {
    final span = stressed - calm;
    if (span.abs() < 1e-6) return 1.0;
    return ((threshold - calm) / span).clamp(0.0, 1.0);
  }

  final buildUpIntensity = 0.6 *
      min(
        crossing(calmHr, heartRateThreshold.toDouble(), stressedHr),
        crossing(calmHrv, rmssdThreshold, stressedHrv),
      );

  // Keep the wobble proportional to the ramp. The original 0.763 was tuned
  // against a fixed 26 BPM span; on a tight threshold an unscaled sigma would
  // swamp the ramp and trigger before the spike.
  final hrSpan = (stressedHr - calmHr).abs();

  return (
    calmHr: calmHr,
    calmHrv: calmHrv,
    stressedHr: stressedHr,
    stressedHrv: stressedHrv,
    buildUpIntensity: buildUpIntensity,
    hrOuSigmaStep: 0.763 * (hrSpan / 26.0).clamp(0.15, 1.0),
  );
}
