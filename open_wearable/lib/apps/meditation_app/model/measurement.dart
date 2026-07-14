import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'band_pass_filter.dart';
import 'dart:math';
import 'user_account.dart';
import 'dart:async';
import 'activity_tracker.dart';

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

  // PPG data stream: emits a tuple of (timestamp, value) where value is the sum of green and ambient channels (inverted).
  late final Stream<(int, double)> _ppgStream;
  late final ActivityTracker activityTracker;
  Stream<int> get heartRate =>
      biometricStream.map((biometrics) => biometrics.heartRate);
  Stream<double?> get rmssd =>
      biometricStream.map((biometrics) => biometrics.rmssd);
  ValueNotifier<StressLevel> stressLevel = ValueNotifier(StressLevel.relaxed);
  ValueNotifier<MonitoringPhase> monitoringPhase =
      ValueNotifier(MonitoringPhase.calibration);
  ValueNotifier<ActivityLevel> get activityLevel =>
      activityTracker.activityLevel;
  Timer? _monitoringPhaseTimer;

  // Filters
  final _bandPassFilter =
      BandPassFilter(lowCut: 0.5, highCut: 4.0, sampleFreq: 200.0);
  final _movingAverageFilter = MovingAverageFilter();
  late final _peakDetector = SlidingWindowPeakDetector(
    windowDurationSeconds: 8,
    minInterPeakDistanceMs: 300,
    timestampExponent: ppgSensor.timestampExponent,
  );
  final _kalmanFilter = KalmanFilter(q: 0.01, r: 4.0);
  final List<(double, DateTime)> _ibiRollingHistory = [];
  final Duration _hrvWindowDuration = const Duration(minutes: 5);

  Measurement({
    required this.ppgSensor,
    required this.accelerometerSensor,
    required this.gyroscopeSensor,
    required this.sensorConfigProvider,
    required this.userAccount,
  }) {
    _configureSensorForStreaming(
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

    final ppgStream = ppgSensor.sensorStream
        .map<PpgOpticalSample?>((data) {
          final values = _sensorValuesAsDoubles(data);
          if (values == null) {
            return null;
          }
          return _extractPpgOpticalSample(ppgSensor, data, values);
        })
        .where((sample) => sample != null)
        .cast<PpgOpticalSample>()
        .map<(int, double)>(
          (sample) => (sample.timestamp, -(sample.green + sample.ambient)),
        )
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

    _ppgStream = ppgStream;
    activityTracker = ActivityTracker(
      accelerometerStream: accelerometerStream,
      gyroscopeStream: gyroscopeStream,
      timestampExponentAccelerometer: accelerometerSensor.timestampExponent,
      timestampExponentGyroscope: gyroscopeSensor.timestampExponent,
    );
  }

  Stream<HeartRateSample> get biometricStream {
    final startTime = DateTime.now();

    return _ppgStream
        .map(
          (event) {
            final (timestamp, value) = event;
            final filteredValue = _bandPassFilter.filter(value);
            final smoothedValue = _movingAverageFilter.next(filteredValue);
            final int? peakTimestamp =
                _peakDetector.processSample(timestamp, smoothedValue);
            if (peakTimestamp == null) return null;
            final peaks = _peakDetector.activePeaks;
            if (peaks.length < 2) return null;

            final ibiList = <double>[];

            for (var i = 1; i < peaks.length; i++) {
              final double ibi = (peaks[i] - peaks[i - 1]) *
                  pow(10, ppgSensor.timestampExponent + 3)
                      .toDouble(); // Convert to milliseconds

              // Physiological plausibility check: Ignore IBIs that are too short or too long
              if (ibi < 300 || ibi > 2000) {
                continue;
              }
              ibiList.add(ibi);
            }

            if (ibiList.isEmpty) return null;

            final averageIbiMs =
                ibiList.reduce((a, b) => a + b) / ibiList.length;
            if (averageIbiMs <= 0 ||
                averageIbiMs.isNaN ||
                averageIbiMs.isInfinite) {
              return null;
            }
            final double heartRate =
                60000.0 / averageIbiMs; // Convert to beats per minute
            final smoothedHeartRate = _kalmanFilter.update(heartRate);

            final now = DateTime.now();
            final double latestIbi = (peaks.last - peaks[peaks.length - 2]) *
                pow(10, ppgSensor.timestampExponent + 3)
                    .toDouble(); // convert to milliseconds
            if (latestIbi >= 300 && latestIbi <= 2000) {
              _ibiRollingHistory.add((latestIbi, now));
            }

            // Remove old IBIs outside the 5-minute window
            _ibiRollingHistory.removeWhere(
              (ibiEntry) => now.difference(ibiEntry.$2) > _hrvWindowDuration,
            );

            // For the first 10 seconds allow filters to stabilize
            if (DateTime.now().difference(startTime).inSeconds < 10) {
              return null;
            }

            double? hrvScore;

            // Calculate RMSSD (Root Mean Square of Successive Differences)
            if (_ibiRollingHistory.isNotEmpty) {
              final oldestRecordTime = _ibiRollingHistory.first.$2;

              if (now.difference(oldestRecordTime) >=
                  const Duration(minutes: 1)) {
                double sumOfSquaredDifferences = 0.0;
                int count = 0;

                for (int i = 1; i < _ibiRollingHistory.length; i++) {
                  double diff =
                      _ibiRollingHistory[i].$1 - _ibiRollingHistory[i - 1].$1;
                  sumOfSquaredDifferences += diff * diff;
                  count++;
                }
                if (count > 0) {
                  hrvScore = sqrt(sumOfSquaredDifferences / count);
                }
              }
            }

            HeartRateSample sample = HeartRateSample(
              heartRate: smoothedHeartRate.round(),
              rmssd: hrvScore,
            );

            return sample;
          },
        )
        .where((data) => data != null)
        .cast<HeartRateSample>();
  }

  Future<void> start() async {
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
    // TODO: add more cleanup
  }

  void dispose() {
    // TODO: Clean up resources
  }

  StreamSubscription<HeartRateSample> adjustBaseline() {
    final (heartRateThreshold, rmssdThreshold) = userAccount.baselineBiometrics;
    final startTime = DateTime.now();

    final subscription = biometricStream.listen((data) {
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
    biometricStream.listen((data) {
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
        // TODO: Start meditation
      }
    });
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

class MovingAverageFilter {
  final int windowSize = 9;
  final List<double> _buffer = [];
  double _currentSum = 0.0;

  /// Process a single sample through the 9-sample moving average
  double next(double sample) {
    // Add the new sample to our window
    _buffer.add(sample);
    _currentSum += sample;

    // If the window exceeds 9 items, drop the oldest sample
    if (_buffer.length > windowSize) {
      _currentSum -= _buffer.removeAt(0);
    }

    // Return the average of the current window
    return _currentSum / _buffer.length;
  }
}

class SlidingWindowPeakDetector {
  late num windowDuration;
  late num minInterPeakDistance;
  final int timestampExponent;

  SlidingWindowPeakDetector({
    required int windowDurationSeconds,
    required int minInterPeakDistanceMs,
    required this.timestampExponent,
  }) {
    windowDuration = windowDurationSeconds * pow(10, -timestampExponent);
    minInterPeakDistance =
        minInterPeakDistanceMs * pow(10, -timestampExponent - 3);
  }

  // Stores the historical clean samples: Tuple of (timestampUs, value)
  final List<(int, double)> _history = [];
  final List<int> _peakTimestamps = [];

  /// Processes a single filtered/smoothed sample.
  /// Returns a valid peak timestamp (in microseconds) if a peak was just found, otherwise null.
  int? processSample(int timestamp, double value) {
    // 1. Add current sample to our tracking history
    _history.add((timestamp, value));

    // 2. Slide the window: Drop elements older than 8 seconds
    _history.removeWhere((sample) => sample.$1 < timestamp - windowDuration);

    // 3. We need at least 3 samples in history to evaluate a local maximum turning point
    if (_history.length < 3) return null;

    // Grab the last three sequential samples in our history buffer
    final idx = _history.length - 1;
    final (_, vPrev) = _history[idx - 2];
    final (tCurr, vCurr) = _history[idx - 1]; // We evaluate the middle point
    final (_, vNext) = _history[idx];

    // 4. Check if the middle point represents a mathematical local maximum peak
    if (vCurr > vPrev && vCurr >= vNext) {
      // 5. Enforce minimum inter-peak lockout distance constraint
      final lastPeak = _peakTimestamps.isNotEmpty ? _peakTimestamps.last : 0;
      if (tCurr - lastPeak >= minInterPeakDistance) {
        // Valid peak found! Record it and clean up peak history older than 8 seconds
        _peakTimestamps.add(tCurr);
        _peakTimestamps.removeWhere(
          (peakTime) => peakTime < timestamp - windowDuration,
        );

        return tCurr;
      }
    }
    return null;
  }

  /// Exposes the list of peak timestamps currently residing within the 8-second window
  List<int> get activePeaks => List.unmodifiable(_peakTimestamps);
}

class KalmanFilter {
  // Parameters
  final double q; // Process noise covariance
  final double r; // Measurement noise covariance

  KalmanFilter({required this.q, required this.r});

  // Filter State Variables
  double _x = 0.0; // Estimated true state value
  double _p = 1.0; // Estimation error covariance
  bool _isInitialized = false;

  /// Processes a single noisy sample and returns the smoothed estimate
  double update(double measurement) {
    // 1. Handle initialization on the very first sample
    if (!_isInitialized) {
      _x = measurement;
      _isInitialized = true;
      return _x;
    }

    // 2. PREDICT STEP
    // For a simple 1D system, the state prediction remains the same,
    // but our uncertainty grows by the process noise Q.
    _p = _p + q;

    // 3. UPDATE STEP
    // Calculate the Kalman Gain (K)
    double k = _p / (_p + r);

    // Correct the state estimate using the new measurement
    _x = _x + k * (measurement - _x);

    // Update the error covariance for the next loop
    _p = (1.0 - k) * _p;

    return _x;
  }
}
