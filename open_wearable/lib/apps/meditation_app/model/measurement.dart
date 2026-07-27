import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'dart:async';
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
  EarstreamState _state = EarstreamState.idle;
  EarstreamState get state => _state;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  ValueNotifier<double?> progress = ValueNotifier(null);

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
        // TODO: Resume meditation if it was ongoing
        break;
    }
  }

  void reset() {
    // Reset the stopwatch
    _stopwatch.reset();
    // App is now idle
    _state = EarstreamState.idle;
    // Reset the monitoring phase to calibration
    monitoringPhase.value = MonitoringPhase.calibration;
    // Reset stress level to relaxed
    stressLevel.value = StressLevel.relaxed;
    // Stop detecting activity level
    _activityTracker.stop();
    // Stop listening to the PPG stream and heart rate/HRV processing
    _metricSubscription?.cancel();
    _accelMetricSubscription?.cancel();
    _stressSubscription?.cancel();
    // TODO: reset filters / decide what to do with meditation
  }

  void dispose() {
    // TODO: Clean up resources
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
        // TODO: check if user is still stressed and if not then change the stress level to relaxed
        return;
      }

      // Check if the user is stressed based on heart rate and RMSSD thresholds
      final (heartRate, rmssd) = (data.heartRate, data.rmssd);
      // TODO: take activity level into account when determining stress level
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
    // TODO: tweek heart rate and heart rate variability to simulate stress
    stressLevel.value = StressLevel.stressed;
    monitoringPhase.value = MonitoringPhase.meditation;
    meditation.value =
        BiometricMeditation(userAccount: userAccount, measurement: this);
    meditation.value!.start();
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
