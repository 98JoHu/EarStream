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

  // Expose calculated values to UI
  ValueNotifier<StressLevel> stressLevel = ValueNotifier(StressLevel.relaxed);
  StressLevel get currentStressLevel => stressLevel.value;
  ValueNotifier<MonitoringPhase> monitoringPhase =
      ValueNotifier(MonitoringPhase.calibration);
  ValueNotifier<ActivityLevel> get activityLevel =>
      _activityTracker.activityLevel;
  ValueNotifier<BiometricMeditation?> meditation = ValueNotifier(null);

  // Fields for handling the phases
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  EarstreamState _state = EarstreamState.idle;
  EarstreamState get state => _state;
  ValueNotifier<double?> progress = ValueNotifier(null);

  // Scripted stress-demo scenario (see simulateStress()), ported from the
  // main branch's MockHrSensor: a deterministic 2-minute HR/HRV build-up
  // used for demos, with the same Ornstein-Uhlenbeck wandering on top.
  Timer? _stressScenarioTimer;
  DateTime? _stressScenarioStartTime;
  double _scenarioHrOuState = 0;
  double _scenarioHrvOuState = 0;
  double _scenarioGaussianSpare = 0;
  bool _scenarioHasGaussianSpare = false;
  final Random _scenarioRandom = Random();

  static const double _scenarioBaseHr = 71.0;
  static const double _scenarioBaseHrv = 80.0;
  static const double _scenarioPhase1EndHr = 80.0;
  static const double _scenarioPhase1EndHrv = 50.0;
  static const double _scenarioPeakHr = 97.0;
  static const double _scenarioPeakHrv = 12.0;
  static const double _scenarioOuAlpha = 0.9672; // exp(-1/30), 30s time const
  static const double _scenarioOuSigmaStep = 0.763; // BPM per tick

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
      targetFrequencyHz: 200,
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

  void start() {
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
      final duration = monitoringPhase.value.duration;
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
        // TODO: Resume meditation if it was ongoing => think about how to handle this case, maybe store the meditation state and resume it
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
    if (meditation.value != null) {
      meditation.value!.dispose();
      meditation.value = null;
    }
    meditation.dispose();
    // Turn off the sensors to save battery
    _turnOffSensor(ppgSensor);
    _turnOffSensor(accelerometerSensor);
    _turnOffSensor(gyroscopeSensor);
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
      // if user is stressed already then don't change the stress level
      if (stressLevel.value == StressLevel.stressed) {
        return;
      }
      // if user is highly active, suppress stress detection
      if (_activityTracker.shouldSupressStressDetection()) {
        return;
      }

      // Check if the user is stressed based on heart rate and RMSSD thresholds
      final (heartRate, rmssd) = (data.heartRate, data.rmssd);
      if (checkStressLevel(heartRate, rmssd) == StressLevel.stressed) {
        // Start a meditation session if the user is stressed
        stressLevel.value = StressLevel.stressed;
        monitoringPhase.value = MonitoringPhase.meditation;
        meditation.value =
            BiometricMeditation(userAccount: userAccount, measurement: this);
        meditation.value!.start();
      }
    });
    return subscription;
  }

  void simulateStress() {
    // Cancel any existing subscriptions or timers
    _metricSubscription?.cancel();
    _accelMetricSubscription?.cancel();
    _stressSubscription?.cancel();

    // Start a new timer for the stress scenario
    _stressScenarioTimer?.cancel();
    _stressScenarioStartTime = DateTime.now();

    // Reset the Ornstein-Uhlenbeck states for HR and HRV
    _scenarioHrOuState = 0;
    _scenarioHrvOuState = 0;

    // Start a periodic timer to simulate HR and HRV values every second
    _stressScenarioTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final tSec =
          DateTime.now().difference(_stressScenarioStartTime!).inSeconds;
      final (hr, hrv) = _scenarioValues(tSec);

      // Mean-reverting random walk around the deterministic trend, same as
      // MockHrSensor: gives the curve a realistic wobble instead of a
      // perfectly smooth ramp.
      _scenarioHrOuState = (_scenarioOuAlpha * _scenarioHrOuState) +
          (_scenarioOuSigmaStep * _scenarioGaussian());
      final hrvOuSigma = (hrv * 0.025).clamp(0.5, 3.0);
      _scenarioHrvOuState = (_scenarioOuAlpha * _scenarioHrvOuState) +
          (hrvOuSigma * _scenarioGaussian());

      final noisyHr = (hr + _scenarioHrOuState).clamp(40.0, 120.0);
      final noisyHrv = (hrv + _scenarioHrvOuState).clamp(5.0, 200.0);
      _processor.emitSimulatedSample(noisyHr.round(), noisyHrv);
    });

    // Move to the monitoring phase
    monitoringPhase.value = MonitoringPhase.monitoring;
    // Simulate stress on activity tracker
    _activityTracker.simulateStress();
    // Start monitoring stress based on the simulated HR and HRV values
    _stressSubscription = monitorStress();
  }

  StressLevel checkStressLevel(int heartRate, double? rmssd) {
    // if heart rate is above the threshold and RMSSD is below the threshold, then the user is stressed
    if (heartRate > userAccount.stressThresholds.$1 &&
        rmssd != null &&
        rmssd < userAccount.stressThresholds.$2) {
      return StressLevel.stressed;
    }
    return StressLevel.relaxed;
  }

  /// Deterministic 2-minute HR/HRV build-up (baseline -> peak stress), ported
  /// from the main branch's MockHrSensor. Phase 1 (0-90s) ramps gently below
  /// the stress thresholds; phase 2 (90-120s) spikes to peak stress; after
  /// 120s it holds at peak.
  (double hr, double hrv) _scenarioValues(int tSec) {
    double hr, hrv;
    if (tSec <= 90) {
      final frac = tSec / 90.0;
      hr = _scenarioBaseHr + (_scenarioPhase1EndHr - _scenarioBaseHr) * frac;
      hrv =
          _scenarioBaseHrv - (_scenarioBaseHrv - _scenarioPhase1EndHrv) * frac;
    } else {
      final frac = ((tSec - 90) / 30.0).clamp(0.0, 1.0);
      hr = _scenarioPhase1EndHr +
          (_scenarioPeakHr - _scenarioPhase1EndHr) * frac;
      hrv = _scenarioPhase1EndHrv -
          (_scenarioPhase1EndHrv - _scenarioPeakHrv) * frac;
    }
    return (hr.clamp(40.0, 120.0), hrv.clamp(5.0, 200.0));
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
