import 'dart:async';
import 'dart:math';

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'package:flutter/foundation.dart';

import '../configs/bio_adaptive_mode_config.dart';
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

  HeartRateSample? get bestEffortEstimate;

  /// Resolves the strongest baseline estimate available at the end of a
  /// time-constrained measurement. Sensor implementations may use retained
  /// conditioned signal that is intentionally not part of the live stream.
  HeartRateSample? finalizeBaselineEstimate();

  void beginCalibration();
  void beginMeasurement();
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
  final Duration? metricWindowDuration;
  final bool publishBestEffortEstimates;
  final bool startInCalibration;

  SensorBiometricSource({
    required this.ppgSensor,
    required this.accelerometerSensor,
    required this.gyroscopeSensor,
    required this.sensorConfigProvider,
    this.hrvMinimumWindow,
    this.metricWindowDuration,
    this.publishBestEffortEstimates = false,
    this.startInCalibration = false,
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
  HeartRateSample? get bestEffortEstimate => _processor.bestEffortEstimate;

  @override
  HeartRateSample? finalizeBaselineEstimate() =>
      _processor.finalizeBaselineEstimate();

  @override
  void start() {
    // Configure the sensor for streaming and get the sample frequency
    final double ppgFreq = _configureSensorForStreaming(
      ppgSensor,
      sensorConfigProvider,
      fallbackFrequency: BioAdaptiveModeConfig.ppgFallbackFrequencyHz,
      targetFrequencyHz: BioAdaptiveModeConfig.ppgTargetFrequencyHz,
    );
    final double accelerometerFreq = _configureSensorForStreaming(
      accelerometerSensor,
      sensorConfigProvider,
      fallbackFrequency: BioAdaptiveModeConfig.accelerometerFallbackFrequencyHz,
      targetFrequencyHz: BioAdaptiveModeConfig.accelerometerTargetFrequencyHz,
    );
    _configureSensorForStreaming(
      gyroscopeSensor,
      sensorConfigProvider,
      fallbackFrequency: BioAdaptiveModeConfig.gyroscopeFallbackFrequencyHz,
      targetFrequencyHz: BioAdaptiveModeConfig.gyroscopeTargetFrequencyHz,
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
      hrvMinimumWindow: hrvMinimumWindow,
      metricWindowDuration: metricWindowDuration,
      publishBestEffortEstimates: publishBestEffortEstimates,
    );
    if (startInCalibration) {
      _processor.beginCalibration();
    }
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
  void beginCalibration() {
    if (_started) _processor.beginCalibration();
  }

  @override
  void beginMeasurement() {
    if (_started) _processor.beginMeasurement();
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

/// Replays the recording-derived stress trajectory from the original app.
///
/// The centre line is the original two-minute scenario: HR 71 -> 80 -> 97
/// BPM and RMSSD 80 -> 50 -> 12 ms. The first transition lasts 90 seconds and
/// the stress spike lasts another 30 seconds. The small mean-reverting
/// variation is also retained from the original implementation so the signal
/// has the same natural character instead of looking perfectly linear.
class RecordedStressBiometricSource implements BiometricSource {
  final ValueNotifier<ActivityLevel> _activityLevel;

  static const double baselineHeartRate =
      BioAdaptiveModeConfig.recordedStressBaselineHeartRate;
  static const double baselineRmssd =
      BioAdaptiveModeConfig.recordedStressBaselineRmssd;
  static const double buildUpHeartRate =
      BioAdaptiveModeConfig.recordedStressBuildUpHeartRate;
  static const double buildUpRmssd =
      BioAdaptiveModeConfig.recordedStressBuildUpRmssd;
  static const double peakHeartRate =
      BioAdaptiveModeConfig.recordedStressPeakHeartRate;
  static const double peakRmssd = BioAdaptiveModeConfig.recordedStressPeakRmssd;

  RecordedStressBiometricSource({
    required ActivityLevel restingActivityLevel,
  }) : _activityLevel = ValueNotifier<ActivityLevel>(restingActivityLevel);

  final _controller = StreamController<HeartRateSample>.broadcast();

  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  bool _measurementEnabled = true;
  HeartRateSample? _latestEstimate;
  bool _relaxationActive = false;
  double _relaxationStartHr = peakHeartRate;
  double _relaxationStartHrv = peakRmssd;

  @override
  Stream<HeartRateSample> get biometrics => _controller.stream;

  @override
  ValueListenable<ActivityLevel> get activityLevel => _activityLevel;

  @override
  bool get suppressStressDetection => false;

  @override
  HeartRateSample? get bestEffortEstimate => _latestEstimate;

  @override
  HeartRateSample? finalizeBaselineEstimate() => _latestEstimate;

  @override
  void beginCalibration() {
    _measurementEnabled = false;
    _latestEstimate = null;
  }

  @override
  void beginMeasurement() {
    _measurementEnabled = true;
  }

  // --- Ornstein-Uhlenbeck wandering state (gives the ramp a realistic wobble)
  double _hrOuState = 0;
  double _hrvOuState = 0;
  double _gaussianSpare = 0;
  bool _hasGaussianSpare = false;
  final Random _random = Random();
  static const double _ouAlpha = BioAdaptiveModeConfig.recordedStressOuAlpha;

  static const double _hrOuSigmaStep =
      BioAdaptiveModeConfig.recordedStressHrOuSigmaStep;
  static const double _buildUpEndSec =
      BioAdaptiveModeConfig.recordedStressBuildUpEndSeconds;
  static const double _spikeEndSec =
      BioAdaptiveModeConfig.recordedStressSpikeEndSeconds;

  // The original app started this six-minute recovery when the meditation
  // began, allowing its normal HR-based early-exit behavior to remain intact.
  static const double _relaxationTargetHr =
      BioAdaptiveModeConfig.relaxationTargetHeartRate;
  static const double _relaxationTargetHrv =
      BioAdaptiveModeConfig.relaxationTargetRmssd;
  static const double _relaxationDurationSec =
      BioAdaptiveModeConfig.relaxationDurationSeconds;

  @override
  void start() {
    _resetScenarioState();
    _latestEstimate = null;
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
    _latestEstimate = null;
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
    _relaxationActive = false;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      BioAdaptiveModeConfig.recordedStressSampleInterval,
      (_) {
        _emitNextSample();
      },
    );
  }

  void _emitNextSample() {
    if (!_measurementEnabled) return;
    final tSec = _clock.elapsed.inSeconds.toDouble();
    final (hr, hrv) = _relaxationActive
        ? _relaxationValues(tSec)
        : stressTrajectoryAt(_clock.elapsed);

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
    _latestEstimate = sample;
    _controller.add(sample);
  }

  /// Returns the exact centre line of the old recording-derived scenario.
  /// Exposed as a pure function so its keyframes cannot silently drift.
  static (double heartRate, double rmssd) stressTrajectoryAt(
    Duration elapsed,
  ) {
    final tSec = max(0, elapsed.inSeconds).toDouble();
    if (tSec <= _buildUpEndSec) {
      final fraction = tSec / _buildUpEndSec;
      return (
        baselineHeartRate + (buildUpHeartRate - baselineHeartRate) * fraction,
        baselineRmssd - (baselineRmssd - buildUpRmssd) * fraction,
      );
    }

    final fraction = ((tSec - _buildUpEndSec) / (_spikeEndSec - _buildUpEndSec))
        .clamp(0.0, 1.0);
    return (
      buildUpHeartRate + (peakHeartRate - buildUpHeartRate) * fraction,
      buildUpRmssd - (buildUpRmssd - peakRmssd) * fraction,
    );
  }

  /// Switches from the stress recording into the original gradual recovery
  /// once the adaptive meditation has started.
  void startRelaxationScenario() {
    final latest = _latestEstimate;
    _relaxationStartHr = latest?.heartRate.toDouble() ?? peakHeartRate;
    _relaxationStartHrv = latest?.rmssd ?? peakRmssd;
    _relaxationActive = true;
    _clock
      ..reset()
      ..start();
  }

  (double heartRate, double rmssd) _relaxationValues(double tSec) {
    final fraction = (tSec / _relaxationDurationSec).clamp(0.0, 1.0);
    final eased = fraction * (2.0 - fraction);
    return (
      _relaxationStartHr + (_relaxationTargetHr - _relaxationStartHr) * eased,
      _relaxationStartHrv +
          (_relaxationTargetHrv - _relaxationStartHrv) * eased,
    );
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
