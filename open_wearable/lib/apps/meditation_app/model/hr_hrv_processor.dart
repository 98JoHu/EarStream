import 'measurement.dart' show HeartRateSample;
import 'band_pass_filter.dart';
import 'dart:async';
import 'dart:math';

class HrHrvProcessor {
  // Filters
  final KalmanFilter _kalmanFilter = KalmanFilter(q: 0.01, r: 4.0);
  final MovingAverageFilter _movingAverageFilter = MovingAverageFilter();
  late final BandPassFilter _bandPassFilter;
  late final SlidingWindowPeakDetector _peakDetector;
  final List<(double, DateTime)> _ibiRollingHistory = [];
  static const Duration _hrvWindowDuration = Duration(minutes: 5);
  static const Duration _warmupDuration = Duration(seconds: 10);
  DateTime? _firstSampleTime;

  // timestamp exponent for converting timestamps to milliseconds
  final int timestampExponent;

  // Expose a biometric stream for external listeners
  final StreamController<HeartRateSample> _metricStreamController =
      StreamController<HeartRateSample>.broadcast();

  Stream<HeartRateSample> get biometricStream => _metricStreamController.stream;

  HrHrvProcessor(
      {required double sampleFreq, required this.timestampExponent}) {
    _bandPassFilter = BandPassFilter(
      sampleFreq: sampleFreq,
      lowCut: 0.5,
      highCut: 4.0,
    );
    _peakDetector = SlidingWindowPeakDetector(
      windowDurationSeconds: 8,
      minInterPeakDistanceMs: 300,
      timestampExponent: timestampExponent,
    );
  }

  void processPpgSample(int timestamp, double green, double ambient) {
    _firstSampleTime ??= DateTime.now();

    final cleanSignal = -(green - ambient);
    final filteredValue = _bandPassFilter.filter(cleanSignal);
    final smoothedValue = _movingAverageFilter.next(filteredValue);
    final int? peakTimestamp =
        _peakDetector.processSample(timestamp, smoothedValue);
    if (peakTimestamp == null) return;
    final peaks = _peakDetector.activePeaks;
    if (peaks.length < 2) return;

    final ibiList = <double>[];

    for (var i = 1; i < peaks.length; i++) {
      final double ibi = (peaks[i] - peaks[i - 1]) *
          pow(10, timestampExponent + 3).toDouble(); // Convert to milliseconds

      // Physiological plausibility check: Ignore IBIs that are too short or too long
      if (ibi < 300 || ibi > 2000) {
        continue;
      }
      ibiList.add(ibi);
    }

    if (ibiList.isEmpty) return;

    final averageIbiMs = ibiList.reduce((a, b) => a + b) / ibiList.length;
    if (averageIbiMs <= 0 || averageIbiMs.isNaN || averageIbiMs.isInfinite) {
      return;
    }
    final double heartRate =
        60000.0 / averageIbiMs; // Convert to beats per minute
    final smoothedHeartRate = _kalmanFilter.update(heartRate);

    final now = DateTime.now();
    final double latestIbi = (peaks.last - peaks[peaks.length - 2]) *
        pow(10, timestampExponent + 3).toDouble(); // convert to milliseconds
    if (latestIbi >= 300 && latestIbi <= 2000) {
      _ibiRollingHistory.add((latestIbi, now));
    }

    // Remove old IBIs outside the 5-minute window
    _ibiRollingHistory.removeWhere(
      (ibiEntry) => now.difference(ibiEntry.$2) > _hrvWindowDuration,
    );

    // For the first 10 seconds allow filters to stabilize
    if (DateTime.now().difference(_firstSampleTime!).inSeconds <
        _warmupDuration.inSeconds) {
      return;
    }

    double? hrvScore;

    // Calculate RMSSD (Root Mean Square of Successive Differences)
    if (_ibiRollingHistory.isNotEmpty) {
      final oldestRecordTime = _ibiRollingHistory.first.$2;

      if (now.difference(oldestRecordTime) >= const Duration(minutes: 1)) {
        double sumOfSquaredDifferences = 0.0;
        int count = 0;

        for (int i = 1; i < _ibiRollingHistory.length; i++) {
          double diff = _ibiRollingHistory[i].$1 - _ibiRollingHistory[i - 1].$1;
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

    _metricStreamController.add(sample);
  }

  void dispose() {
    _metricStreamController.close();
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
