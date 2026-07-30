import 'dart:async';
import 'dart:math';

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'package:flutter/foundation.dart';

import 'hr_hrv_processor.dart';
import 'activity_tracker.dart';

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

abstract interface class BiometricSource {
  // The stream of HR/HRV samples, needs to be broadcasted
  Stream<HeartRateSample> get biometrics;

  // Current activity level, needs to be broadcasted
  ValueListenable<ActivityLevel> get activityLevel;

  // Whether stress detection should be suppressed (e.g. due to high activity)
  bool get suppressStressDetection;

  void start();
  void pause();
  void resume();
  void reset();
  void dispose();
}

class SensorBiometricSource implements BiometricSource {
  final Sensor ppgSensor;
  final Sensor accelerometerSensor;
  final Sensor gyroscopeSensor;
  final SensorConfigurationProvider sensorConfigProvider;

  final Duration? hrvMinimumWindow;

  SensorBiometricSource({
    required this.ppgSensor,
    required this.accelerometerSensor,
    required this.gyroscopeSensor,
    required this.sensorConfigProvider,
    this.hrvMinimumWindow,
  });

  late final Stream<PpgOpticalSample> _ppgStream;
  late final Stream<PpgMotionSample> _accelerometerStream;
  late final HrHrvProcessor _processor;
  late final ActivityTracker _activityTracker;

  StreamSubscription<PpgOpticalSample>? _ppgSubscription;
  StreamSubscription<PpgMotionSample>? _accelSubscription;

  bool _started = false;

  @override
  Stream<HeartRateSample> get biometrics => _processor.biometricStream;

  @override
  ValueListenable<ActivityLevel> get activityLevel =>
      _activityTracker.activityLevel;

  @override
  bool get suppressStressDetection =>
      _activityTracker.shouldSuppressStressDetection();

  @override
  void start() {
    // Configure the sensor for streaming and get the sample frequency
    final double ppgFreq = _configureSensorForStreaming(
      ppgSensor,
      sensorConfigProvider,
      fallbackFrequency: 100.0,
      targetFrequencyHz: 200,
    );
    final double accelerometerFreq = _configureSensorForStreaming(
      accelerometerSensor,
      sensorConfigProvider,
      fallbackFrequency: 100.0,
      targetFrequencyHz: 100,
    );
    _configureSensorForStreaming(
      gyroscopeSensor,
      sensorConfigProvider,
      fallbackFrequency: 100.0,
      targetFrequencyHz: 100,
    );

    // Create the streams for PPG, accelerometer and gyroscope data
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

    // Create the HR/HRV processor and activity tracker
    _processor = HrHrvProcessor(
      sampleFreq: ppgFreq,
      accelerometerFreq: accelerometerFreq,
      timestampExponent: ppgSensor.timestampExponent,
    );
    _activityTracker = ActivityTracker(
      accelerometerStream: _accelerometerStream,
      gyroscopeStream: gyroscopeStream,
      timestampExponentAccelerometer: accelerometerSensor.timestampExponent,
      timestampExponentGyroscope: gyroscopeSensor.timestampExponent,
    );

    // Subscribe to the streams and start processing
    _subscribe();
    _started = true;
  }

  @override
  void pause() {
    if (!_started) return;
    _ppgSubscription?.cancel();
    _accelSubscription?.cancel();
    _activityTracker.pause();
  }

  @override
  void resume() {
    if (!_started) return;
    _subscribe();
    _activityTracker.start();
  }

  @override
  void reset() {
    if (!_started) return;
    _ppgSubscription?.cancel();
    _accelSubscription?.cancel();
    _activityTracker.reset();
    _processor.reset();
  }

  @override
  void dispose() {
    _ppgSubscription?.cancel();
    _accelSubscription?.cancel();
    if (_started) {
      _activityTracker.dispose();
      _processor.dispose();
    }

    scheduleMicrotask(() {
      _turnOffSensor(ppgSensor);
      _turnOffSensor(accelerometerSensor);
      _turnOffSensor(gyroscopeSensor);
    });
  }

  void _subscribe() {
    _ppgSubscription?.cancel();
    _ppgSubscription = _ppgStream.listen((data) {
      _processor.processPpgSample(
        data.timestamp,
        data.red,
        data.ir,
        data.green,
        data.ambient,
      );
    });

    _accelSubscription?.cancel();
    _accelSubscription = _accelerometerStream.listen((data) {
      _processor.processAccelerometerSample(
        data.timestamp,
        data.x,
        data.y,
        data.z,
      );
    });
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
}

class SimulatedBiometricSource implements BiometricSource {
  final ValueNotifier<ActivityLevel> _activityLevel;

  /// The two ends of the scripted arc: the resting values it starts from and
  /// the values its spike peaks at. The caller picks both, so the simulation
  /// depends on nothing but its own constructor arguments.
  final int startHeartRate;
  final double startRmssd;
  final int peakHeartRate;
  final double peakRmssd;

  SimulatedBiometricSource({
    required this.startHeartRate,
    required this.startRmssd,
    required this.peakHeartRate,
    required this.peakRmssd,
    required ActivityLevel restingActivityLevel,
  }) : _activityLevel = ValueNotifier<ActivityLevel>(restingActivityLevel);

  final _controller = StreamController<HeartRateSample>.broadcast();

  final Stopwatch _clock = Stopwatch();
  Timer? _timer;

  @override
  Stream<HeartRateSample> get biometrics => _controller.stream;

  @override
  ValueListenable<ActivityLevel> get activityLevel => _activityLevel;

  @override
  bool get suppressStressDetection => false;

  // --- Ornstein-Uhlenbeck wandering state (gives the ramp a realistic wobble)
  double _hrOuState = 0;
  double _hrvOuState = 0;
  double _gaussianSpare = 0;
  bool _hasGaussianSpare = false;
  final Random _random = Random();
  static const double _ouAlpha = 0.9672;

  /// How far up the start -> peak ramp the build-up climbs before the spike.
  /// Kept short of the peak so the rise is visible before anything triggers.
  static const double _buildUpIntensity = 0.3;

  /// Step size of the HR wandering, scaled to the ramp: the 0.763 was tuned
  /// against a 26 BPM span, and on a narrower one an unscaled sigma would
  /// swamp the trend.
  late final double _hrOuSigmaStep =
      0.763 * (((peakHeartRate - startHeartRate).abs() / 26.0).clamp(0.15, 1.0));

  // Scenario timeline, in seconds from start: a rising build-up that stops
  // short of the peak, a spike that reaches it, a plateau long enough for a
  // meditation segment or two, then a recovery back to the starting values.
  static const double _buildUpEndSec = 20;
  static const double _spikeEndSec = 35;
  static const double _plateauEndSec = 80;
  static const double _recoveryEndSec = 120;

  @override
  void start() {
    _resetScenarioState();
    _clock
      ..reset()
      ..start();
    _startTimer();
  }

  @override
  void pause() {
    _clock.stop();
    _timer?.cancel();
  }

  @override
  void resume() {
    _clock.start();
    _startTimer();
  }

  @override
  void reset() {
    _timer?.cancel();
    _clock
      ..stop()
      ..reset();
    _resetScenarioState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
    _activityLevel.dispose();
  }

  void _resetScenarioState() {
    _hrOuState = 0;
    _hrvOuState = 0;
    _hasGaussianSpare = false;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _emitNextSample();
    });
  }

  void _emitNextSample() {
    final tSec = _clock.elapsedMilliseconds / 1000.0;
    final (hr, hrv) = _scenarioValues(tSec);

    // Mean-reverting random walk around the deterministic trend.
    _hrOuState = (_ouAlpha * _hrOuState) + (_hrOuSigmaStep * _gaussian());
    final hrvOuSigma = (hrv * 0.025).clamp(0.5, 3.0);
    _hrvOuState = (_ouAlpha * _hrvOuState) + (hrvOuSigma * _gaussian());

    // Floors only — an upper clamp here would quietly clip a caller that asked
    // for a peak above it.
    final noisyHr = max(1.0, hr + _hrOuState);
    final noisyHrv = max(1.0, hrv + _hrvOuState);

    final sample = HeartRateSample(
      heartRate: noisyHr.round(),
      rmssd: noisyHrv,
    );
    _controller.add(sample);
  }

  /// Deterministic HR/HRV arc, as a fraction of the way from the starting
  /// values (0) to the peak values (1).
  double _scenarioIntensity(double tSec) {
    if (tSec <= _buildUpEndSec) {
      return _buildUpIntensity * (tSec / _buildUpEndSec);
    }
    if (tSec <= _spikeEndSec) {
      final frac = (tSec - _buildUpEndSec) / (_spikeEndSec - _buildUpEndSec);
      return _buildUpIntensity + (1.0 - _buildUpIntensity) * frac;
    }
    if (tSec <= _plateauEndSec) {
      return 1.0;
    }
    if (tSec <= _recoveryEndSec) {
      final frac = (tSec - _plateauEndSec) / (_recoveryEndSec - _plateauEndSec);
      return 1.0 - frac;
    }
    return 0.0;
  }

  (double hr, double hrv) _scenarioValues(double tSec) {
    final intensity = _scenarioIntensity(tSec);
    final hr = startHeartRate + (peakHeartRate - startHeartRate) * intensity;
    final hrv = startRmssd + (peakRmssd - startRmssd) * intensity;
    return (hr, hrv);
  }

  /// Polar Box-Muller transform — standard-normal samples for the OU wandering.
  double _gaussian() {
    if (_hasGaussianSpare) {
      _hasGaussianSpare = false;
      return _gaussianSpare;
    }
    double u, v, s;
    do {
      u = _random.nextDouble() * 2 - 1;
      v = _random.nextDouble() * 2 - 1;
      s = u * u + v * v;
    } while (s >= 1.0 || s == 0.0);
    final mul = sqrt(-2.0 * log(s) / s);
    _gaussianSpare = v * mul;
    _hasGaussianSpare = true;
    return u * mul;
  }
}
