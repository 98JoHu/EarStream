import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'dart:async';
import 'user_account.dart';
import 'activity_tracker.dart';
import 'meditation.dart';
import 'hr_hrv_processor.dart';

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
  late final HrHrvProcessor _processor;
  late final ActivityTracker activityTracker;
  StreamSubscription<PpgOpticalSample>? metricSubscription;
  Stream<int> get heartRate =>
      _processor.biometricStream.map((biometrics) => biometrics.heartRate);
  Stream<double?> get rmssd =>
      _processor.biometricStream.map((biometrics) => biometrics.rmssd);

  // Expose calculated values to UI
  ValueNotifier<StressLevel> stressLevel = ValueNotifier(StressLevel.relaxed);
  ValueNotifier<MonitoringPhase> monitoringPhase =
      ValueNotifier(MonitoringPhase.calibration);
  ValueNotifier<ActivityLevel> get activityLevel =>
      activityTracker.activityLevel;
  Timer? _monitoringPhaseTimer;
  ValueNotifier<Meditation?> meditation = ValueNotifier(null);

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

    final accelerometerStream = accelerometerSensor.sensorStream
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
    activityTracker = ActivityTracker(
      accelerometerStream: accelerometerStream,
      gyroscopeStream: gyroscopeStream,
      timestampExponentAccelerometer: accelerometerSensor.timestampExponent,
      timestampExponentGyroscope: gyroscopeSensor.timestampExponent,
    );
  }

  Future<void> start() async {
    // Listen to the PPG stream and process incoming samples => HR and HRV
    metricSubscription = _ppgStream.listen((data) {
      _processor.processPpgSample(data.timestamp, data.green, data.ambient);
    });
    // Detect activity level
    activityTracker.start();

    // Start with calibration phase
    _monitoringPhaseTimer?.cancel();
    await Future.delayed(MonitoringPhase.calibration.duration);

    // Execute baseline phase after calibration
    monitoringPhase.value = MonitoringPhase.baseline;
    final subscription = adjustBaseline();
    await Future.delayed(MonitoringPhase.baseline.duration);
    subscription.cancel();

    // Stress detection
    monitoringPhase.value = MonitoringPhase.monitoring;
    monitorStress();
  }

  void stop() {
    _monitoringPhaseTimer?.cancel();
    activityTracker.stop();
    metricSubscription?.cancel();
    // TODO: add more cleanup
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
          elapsedSeconds / MonitoringPhase.baseline.duration.inMilliseconds;
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

  void monitorStress() {
    // Detect stress
    _processor.biometricStream.listen((data) {
      // if user is stressed already then don't change the stress level
      if (stressLevel.value == StressLevel.stressed) {
        return;
      }

      // Check if the user is stressed based on heart rate and RMSSD thresholds
      final (heartRate, rmssd) = (data.heartRate, data.rmssd);
      // TODO: take activity level into account when determining stress level
      if (heartRate > userAccount.stressThresholds.$1 &&
          rmssd != null &&
          rmssd < userAccount.stressThresholds.$2) {
        stressLevel.value = StressLevel.stressed;
        monitoringPhase.value = MonitoringPhase.meditation;
        meditation.value =
            Meditation(userAccount: userAccount, measurement: this);
        meditation.value!.start();
      }
    });
  }

  void simulateStress() {
    stressLevel.value = StressLevel.stressed;
    monitoringPhase.value = MonitoringPhase.meditation;
    // TODO: tweek heart rate and heart rate variability to simulate stress
    meditation.value = Meditation(userAccount: userAccount, measurement: this);
    meditation.value!.start();
  }

  void reset() {
    stressLevel.value = StressLevel.relaxed;
    monitoringPhase.value = MonitoringPhase.calibration;
    meditation.value = null;
    // TODO: Reset measurements
  }

  void checkStressLevel() {}

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
