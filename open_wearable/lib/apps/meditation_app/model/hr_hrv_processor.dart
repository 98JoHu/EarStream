import 'measurement.dart' show HeartRateSample;
import 'dart:async';
import 'dart:math';

/// Mirrors the Heart Tracker page's PpgFilter pipeline (see
/// apps/heart_tracker/model/ppg_filter.dart): adaptive channel selection,
/// ambient-light cancellation, accelerometer-referenced motion cancellation,
/// motion-aware outlier suppression, DC-block + band-pass filtering, bounded
/// normalization, then a windowed (10s buffer, ~1Hz) peak-based HR/HRV
/// estimate with quality gating. Kept as a separate copy (not an import) so
/// the meditation app doesn't depend on the heart_tracker app.
///
/// Unlike the Heart Tracker page, this has no gyroscope and no optical
/// temperature input, so the in-ear temperature gate is simply omitted.
///
/// NOTE: assumes the accelerometer stream reports m/s^2 (gravity ~9.81) —
/// same assumption the heart_tracker pipeline makes. If this device's
/// accelerometer reports g-units or raw counts instead, the motion
/// thresholds below will be miscalibrated.
///
/// NOTE: heart_tracker_page.dart validates this pipeline with both PPG and
/// accelerometer streamed at 50Hz. This app streams PPG at 200Hz and the
/// accelerometer at 100Hz instead, so every fixed per-sample smoothing
/// constant below (EMA alphas, window/tap-history sizes) has been
/// re-tuned for those rates rather than copied as-is from the 50Hz
/// reference — see the per-class comments below.
class HrHrvProcessor {
  final double sampleFreq;
  final int timestampExponent;

  static const double _minBeatIntervalSec = 0.25;
  static const double _maxBeatIntervalSec = 2.0;

  final _AdaptiveOpticalChannelSelector _channelSelector =
      _AdaptiveOpticalChannelSelector();
  final _AmbientLightCanceler _ambientCanceler = _AmbientLightCanceler();
  final _MotionNoiseSuppressor _motionSuppressor = _MotionNoiseSuppressor();
  final _MultiReferenceMotionCanceler _imuCanceler =
      _MultiReferenceMotionCanceler();
  late final _HighPassFilter _dcBlockFilter;
  late final _BandPassFilter _bandPassFilter;
  final _BoundedSignalNormalizer _normalizer = _BoundedSignalNormalizer();

  final List<_ConditionedSample> _buffer = [];
  late final double _ticksPerSecond;
  late final double _ticksToMilliseconds;
  late final double _windowDurationTicks;
  late final double _minimumWindowTicks;
  late final double _evaluationPeriodTicks;
  double _lastEvaluationTick = double.negativeInfinity;

  double _hrEstimate = 75.0;
  double _hrCovariance = 1.0;
  final double _hrProcessNoise = 0.02;
  final double _hrMeasurementNoise = 5.0;

  double _hrvEstimateMs = 35.0;
  final double _hrvSmoothingAlpha = 0.18;

  DateTime? _firstSampleTime;
  DateTime? _lastEmitTime;
  static const Duration _warmupDuration = Duration(seconds: 10);
  static const Duration _emitInterval = Duration(seconds: 3);

  final StreamController<HeartRateSample> _metricStreamController =
      StreamController<HeartRateSample>.broadcast();

  Stream<HeartRateSample> get biometricStream => _metricStreamController.stream;

  HrHrvProcessor({
    required this.sampleFreq,
    required this.timestampExponent,
  }) {
    _dcBlockFilter = _HighPassFilter(cutoffFreq: 0.12, sampleFreq: sampleFreq);
    _bandPassFilter = _BandPassFilter(
      sampleFreq: sampleFreq,
      lowCut: 0.45,
      highCut: 5.5,
    );

    _ticksPerSecond = pow(10, -timestampExponent).toDouble();
    _ticksToMilliseconds = pow(10, timestampExponent + 3).toDouble();
    _windowDurationTicks = 10.0 * _ticksPerSecond;
    _minimumWindowTicks = 4.0 * _ticksPerSecond;
    _evaluationPeriodTicks = max(1.0, _ticksPerSecond);
  }

  /// Feeds a raw accelerometer sample (m/s^2). Used only for motion
  /// cancellation/gating, not for HR/HRV itself.
  void processAccelerometerSample(int timestamp, double x, double y, double z) {
    final magnitude = sqrt((x * x) + (y * y) + (z * z));
    _motionSuppressor.updateMotionMagnitude(magnitude);
    _imuCanceler.updateMotion(x: x, y: y, z: z);
  }

  void processPpgSample(
    int timestamp,
    double red,
    double ir,
    double green,
    double ambient,
  ) {
    _firstSampleTime ??= DateTime.now();

    final selectedOpticalSignal =
        _channelSelector.select(green: green, red: red, ir: ir);
    final ambientCanceled = _ambientCanceler.filter(
      green: selectedOpticalSignal,
      ambient: ambient,
    );
    final motionLevel = _motionSuppressor.motionLevel;
    final imuCleaned =
        _imuCanceler.filter(ambientCanceled, motionLevel: motionLevel);
    final motionSuppressed = _motionSuppressor.filter(imuCleaned);
    final dcBlocked = _dcBlockFilter.filter(motionSuppressed);
    final bandPassed = _bandPassFilter.filter(dcBlocked);
    final bounded = _normalizer.filter(bandPassed, motionLevel: motionLevel);

    _buffer.add(
      _ConditionedSample(
        timestamp: timestamp,
        signal: bounded,
        motionLevel: motionLevel,
      ),
    );
    _buffer.removeWhere(
      (sample) => sample.timestamp < timestamp - _windowDurationTicks,
    );

    if ((timestamp - _lastEvaluationTick) < _evaluationPeriodTicks) {
      return;
    }
    _lastEvaluationTick = timestamp.toDouble();

    _evaluateVitals(timestamp);
  }

  void dispose() {
    _metricStreamController.close();
  }

  void _evaluateVitals(int latestTimestamp) {
    if (_buffer.length < 20 ||
        (_buffer.last.timestamp - _buffer.first.timestamp) <
            _minimumWindowTicks) {
      return;
    }

    final recentQuality =
        _estimateRecentWaveformQualityScore(latestTimestamp: latestTimestamp);
    var qualityScore = recentQuality.score;
    final recentMotion = recentQuality.averageMotion;

    if (recentMotion >= 1.45) {
      return;
    }

    final effectiveSampleFreqHz = _estimateEffectiveSampleFreqHz();
    final peakEstimate = _estimateHeartRateByPeak(
      estimatedSampleFreqHz: effectiveSampleFreqHz,
    );
    final peaks = peakEstimate.peakTimestamps;
    final peakHeartRate = peakEstimate.heartRateBpm;

    final peakScore = (peaks.length / 8.0).clamp(0.0, 1.0);
    qualityScore = ((0.78 * qualityScore) + (0.22 * peakScore)).clamp(0.0, 1.0);

    final ibiTicks = <double>[];
    for (var i = 1; i < peaks.length; i++) {
      final interval = (peaks[i] - peaks[i - 1]).toDouble();
      final intervalSeconds = interval / _ticksPerSecond;
      if (interval > 0 &&
          intervalSeconds >= _minBeatIntervalSec &&
          intervalSeconds <= _maxBeatIntervalSec) {
        ibiTicks.add(interval);
      }
    }
    if (ibiTicks.length >= 2) {
      final robustIbiTicks = _removeIbiOutliers(ibiTicks);
      final meanIbiTicks =
          robustIbiTicks.reduce((a, b) => a + b) / robustIbiTicks.length;
      if (meanIbiTicks.isFinite && meanIbiTicks > 0) {
        final ibiVariation = _standardDeviation(robustIbiTicks) / meanIbiTicks;
        if (ibiVariation.isFinite) {
          final rhythmScore = (1.0 - (ibiVariation / 0.55)).clamp(0.0, 1.0);
          qualityScore =
              ((0.78 * qualityScore) + (0.22 * rhythmScore)).clamp(0.0, 1.0);
        }
      }
    }

    final classifiedQuality = _classifyQuality(qualityScore);
    if (classifiedQuality == _SignalQuality.bad ||
        classifiedQuality == _SignalQuality.unavailable) {
      return;
    }
    if (peakHeartRate == null) {
      return;
    }

    final smoothedHeartRate = _kalmanUpdateHeartRate(peakHeartRate);

    double? smoothedHrvMs;
    if (ibiTicks.length >= 2) {
      final robustIbiTicks = _removeIbiOutliers(ibiTicks);
      final rmssdTicks = _computeRmssd(robustIbiTicks);
      if (rmssdTicks != null && rmssdTicks.isFinite && rmssdTicks > 0) {
        final hrvMs = rmssdTicks * _ticksToMilliseconds;
        if (hrvMs.isFinite && hrvMs >= 5 && hrvMs <= 300) {
          smoothedHrvMs = _smoothHrv(hrvMs);
        }
      }
    }

    _maybeEmit(smoothedHeartRate, smoothedHrvMs);
  }

  void _maybeEmit(double heartRate, double? rmssd) {
    final firstSampleTime = _firstSampleTime;
    if (firstSampleTime == null ||
        DateTime.now().difference(firstSampleTime) < _warmupDuration) {
      return;
    }

    final now = DateTime.now();
    if (_lastEmitTime != null &&
        now.difference(_lastEmitTime!) < _emitInterval) {
      return;
    }
    _lastEmitTime = now;

    _metricStreamController.add(
      HeartRateSample(
        heartRate: heartRate.round(),
        rmssd: rmssd,
      ),
    );
  }

  void reset() {
    _firstSampleTime = null;
    _lastEmitTime = null;
    _buffer.clear();
    _channelSelector.reset();
    _ambientCanceler.reset();
    _motionSuppressor.reset();
    _imuCanceler.reset();
    _dcBlockFilter.reset();
    _bandPassFilter.reset();
    _normalizer.reset();
    _hrEstimate = 75.0;
    _hrCovariance = 1.0;
    _hrvEstimateMs = 35.0;
  }

  ({double score, double averageMotion}) _estimateRecentWaveformQualityScore({
    required int latestTimestamp,
  }) {
    final qualityWindowTicks = 3.0 * _ticksPerSecond;
    final recent = _buffer
        .where(
          (sample) => sample.timestamp >= latestTimestamp - qualityWindowTicks,
        )
        .toList(growable: false);
    final minimumSamples = max(8, (sampleFreq * 1.2).round());
    if (recent.length < minimumSamples) {
      return (score: 0.0, averageMotion: 0.0);
    }

    final filteredValues =
        recent.map((sample) => sample.signal).toList(growable: false);
    final meanFilteredAbs =
        filteredValues.map((value) => value.abs()).reduce((a, b) => a + b) /
            filteredValues.length;
    if (!meanFilteredAbs.isFinite || meanFilteredAbs <= 1e-6) {
      return (score: 0.0, averageMotion: 0.0);
    }

    final minFiltered = filteredValues.reduce(min);
    final maxFiltered = filteredValues.reduce(max);
    final rangeFiltered = maxFiltered - minFiltered;
    final stdFiltered = _standardDeviation(filteredValues);

    final averageMotion =
        recent.map((sample) => sample.motionLevel).reduce((a, b) => a + b) /
            recent.length;
    final rangeScore = ((rangeFiltered - 0.08) / 0.95).clamp(0.0, 1.0);
    final stdScore = ((stdFiltered - 0.025) / 0.30).clamp(0.0, 1.0);
    final motionScore = (1.0 - (averageMotion / 2.2)).clamp(0.0, 1.0);

    var score = ((0.45 * rangeScore) + (0.35 * stdScore) + (0.20 * motionScore))
        .clamp(0.0, 1.0);

    if (averageMotion >= 1.45) {
      score = min(score, 0.10);
    } else if (averageMotion >= 1.12) {
      score = min(score, 0.24);
    } else if (averageMotion >= 0.88) {
      score = min(score, 0.45);
    }

    return (score: score, averageMotion: averageMotion);
  }

  _SignalQuality _classifyQuality(double score) {
    if (!score.isFinite || score <= 0) {
      return _SignalQuality.unavailable;
    }
    if (score < 0.30) {
      return _SignalQuality.bad;
    }
    if (score < 0.62) {
      return _SignalQuality.fair;
    }
    return _SignalQuality.good;
  }

  double _estimateEffectiveSampleFreqHz() {
    if (_buffer.length < 2) {
      return sampleFreq;
    }
    final durationTicks =
        (_buffer.last.timestamp - _buffer.first.timestamp).toDouble();
    if (durationTicks <= 0) {
      return sampleFreq;
    }
    final estimated = ((_buffer.length - 1) * _ticksPerSecond) / durationTicks;
    if (!estimated.isFinite || estimated < 5 || estimated > 200) {
      return sampleFreq;
    }
    return estimated;
  }

  ({double? heartRateBpm, List<int> peakTimestamps}) _estimateHeartRateByPeak({
    required double estimatedSampleFreqHz,
  }) {
    if (_buffer.length < 8) {
      return (heartRateBpm: null, peakTimestamps: const []);
    }

    final signal =
        _buffer.map((sample) => sample.signal).toList(growable: false);
    final mean = signal.reduce((a, b) => a + b) / signal.length;
    final centered =
        signal.map((value) => value - mean).toList(growable: false);

    final signalStd = _standardDeviation(centered);
    if (!signalStd.isFinite || signalStd < 1e-4) {
      return (heartRateBpm: null, peakTimestamps: const []);
    }

    final safeSampleFreq =
        estimatedSampleFreqHz.isFinite && estimatedSampleFreqHz > 0
            ? estimatedSampleFreqHz
            : sampleFreq;
    final minPeakDistanceSamples =
        max(1, (safeSampleFreq * _minBeatIntervalSec * 0.85).round());
    final amplitudeThreshold = max(0.04, signalStd * 0.35);

    final peakIndices = <int>[];
    for (var i = 1; i < centered.length - 1; i++) {
      final current = centered[i];
      if (!current.isFinite || current < amplitudeThreshold) {
        continue;
      }
      final isLocalMaximum =
          current >= centered[i - 1] && current > centered[i + 1];
      if (!isLocalMaximum) {
        continue;
      }

      if (peakIndices.isNotEmpty &&
          (i - peakIndices.last) < minPeakDistanceSamples) {
        if (current > centered[peakIndices.last]) {
          peakIndices[peakIndices.length - 1] = i;
        }
        continue;
      }
      peakIndices.add(i);
    }

    final peaks = peakIndices
        .map((index) => _buffer[index].timestamp)
        .toList(growable: false);

    return _estimateHeartRateFromPeakTimestamps(peaks);
  }

  ({double? heartRateBpm, List<int> peakTimestamps})
      _estimateHeartRateFromPeakTimestamps(List<int> peaks) {
    if (peaks.length < 2) {
      return (heartRateBpm: null, peakTimestamps: peaks);
    }

    final intervalsSeconds = <double>[];
    for (var i = 1; i < peaks.length; i++) {
      final intervalSeconds =
          (peaks[i] - peaks[i - 1]).toDouble() / _ticksPerSecond;
      if (intervalSeconds >= _minBeatIntervalSec &&
          intervalSeconds <= _maxBeatIntervalSec) {
        intervalsSeconds.add(intervalSeconds);
      }
    }
    if (intervalsSeconds.isEmpty) {
      return (heartRateBpm: null, peakTimestamps: peaks);
    }

    intervalsSeconds.sort();
    final medianIntervalSeconds =
        intervalsSeconds[intervalsSeconds.length ~/ 2];
    final heartRate = 60.0 / medianIntervalSeconds;
    if (!heartRate.isFinite || heartRate < 30 || heartRate > 240) {
      return (heartRateBpm: null, peakTimestamps: peaks);
    }

    return (heartRateBpm: heartRate, peakTimestamps: peaks);
  }

  List<double> _removeIbiOutliers(List<double> ibiTicks) {
    if (ibiTicks.length < 3) {
      return ibiTicks;
    }

    final sorted = [...ibiTicks]..sort();
    final median = sorted[sorted.length ~/ 2];
    final low = median * 0.65;
    final high = median * 1.35;
    final filtered = ibiTicks
        .where((ibi) => ibi >= low && ibi <= high)
        .toList(growable: false);
    return filtered.length >= 2 ? filtered : ibiTicks;
  }

  double? _computeRmssd(List<double> ibiTicks) {
    if (ibiTicks.length < 2) {
      return null;
    }

    var sumSquared = 0.0;
    var count = 0;
    for (var i = 1; i < ibiTicks.length; i++) {
      final delta = ibiTicks[i] - ibiTicks[i - 1];
      sumSquared += delta * delta;
      count += 1;
    }

    if (count == 0) {
      return null;
    }
    return sqrt(sumSquared / count);
  }

  double _standardDeviation(List<double> values) {
    if (values.length < 2) {
      return 0;
    }
    final mean = values.reduce((a, b) => a + b) / values.length;
    var variance = 0.0;
    for (final value in values) {
      final diff = value - mean;
      variance += diff * diff;
    }
    variance /= values.length;
    return sqrt(variance);
  }

  double _kalmanUpdateHeartRate(double measurement) {
    if (!measurement.isFinite) {
      return _hrEstimate;
    }

    _hrCovariance += _hrProcessNoise;
    final gain = _hrCovariance / (_hrCovariance + _hrMeasurementNoise);
    _hrEstimate += gain * (measurement - _hrEstimate);
    _hrCovariance *= (1 - gain);
    return _hrEstimate;
  }

  double _smoothHrv(double measurementMs) {
    if (!measurementMs.isFinite || measurementMs <= 0) {
      return _hrvEstimateMs;
    }
    _hrvEstimateMs = (_hrvEstimateMs * (1.0 - _hrvSmoothingAlpha)) +
        (measurementMs * _hrvSmoothingAlpha);
    return _hrvEstimateMs;
  }
}

enum _SignalQuality { unavailable, bad, fair, good }

class _ConditionedSample {
  final int timestamp;
  final double signal;
  final double motionLevel;

  const _ConditionedSample({
    required this.timestamp,
    required this.signal,
    required this.motionLevel,
  });
}

class _HighPassFilter {
  final double cutoffFreq;
  final double sampleFreq;

  late final double alpha;
  double? _lastInput;
  double? _lastOutput;

  _HighPassFilter({
    required this.cutoffFreq,
    required this.sampleFreq,
  }) {
    final dt = 1.0 / sampleFreq;
    final rc = 1.0 / (2 * pi * cutoffFreq);
    alpha = rc / (rc + dt);
  }

  void reset() {
    _lastInput = null;
    _lastOutput = null;
  }

  double filter(double x) {
    if (_lastInput == null) {
      _lastInput = x;
      _lastOutput = 0.0;
      return 0.0;
    }

    final y = alpha * ((_lastOutput ?? 0.0) + x - (_lastInput ?? 0.0));
    _lastInput = x;
    _lastOutput = y;
    return y;
  }
}

class _BandPassFilter {
  final double sampleFreq;
  final double lowCut;
  final double highCut;

  late final double a0, a1, a2, b1, b2;
  double x1 = 0, x2 = 0;
  double y1 = 0, y2 = 0;
  bool _isFirstSample = true;

  _BandPassFilter({
    required this.sampleFreq,
    required this.lowCut,
    required this.highCut,
  }) {
    final centerFreq = sqrt(lowCut * highCut);
    final bandwidth = highCut - lowCut;
    final q = centerFreq / bandwidth;

    final omega = 2 * pi * centerFreq / sampleFreq;
    final alpha = sin(omega) / (2 * q);

    final cosOmega = cos(omega);
    final norm = 1 + alpha;

    a0 = alpha / norm;
    a1 = 0;
    a2 = -alpha / norm;
    b1 = -2 * cosOmega / norm;
    b2 = (1 - alpha) / norm;
  }

  void reset() {
    x1 = 0;
    x2 = 0;
    y1 = 0;
    y2 = 0;
    _isFirstSample = true;
  }

  double filter(double x) {
    // Pre-warm filter state on the first sample to avoid a step-function
    // transient: a band-pass filter has zero DC gain, so y1=y2=0 is correct,
    // but seeding x1=x2=firstSample eliminates the large initial ringing that
    // otherwise produces false peaks and a spuriously high HR for ~30 seconds.
    if (_isFirstSample) {
      _isFirstSample = false;
      x1 = x;
      x2 = x;
    }
    final y = a0 * x + a1 * x1 + a2 * x2 - b1 * y1 - b2 * y2;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
    return y;
  }
}

class _AdaptiveOpticalChannelSelector {
  static const double _meanAlpha = 0.005;
  static const double _energyAlpha = 0.02;

  bool _isInitialized = false;
  double _meanGreen = 0;
  double _meanRed = 0;
  double _meanIr = 0;
  double _energyGreen = 0;
  double _energyRed = 0;
  double _energyIr = 0;

  double select({
    required double green,
    required double red,
    required double ir,
  }) {
    if (!_isInitialized) {
      _isInitialized = true;
      _meanGreen = green;
      _meanRed = red;
      _meanIr = ir;
    } else {
      _meanGreen = _ema(_meanGreen, green, _meanAlpha);
      _meanRed = _ema(_meanRed, red, _meanAlpha);
      _meanIr = _ema(_meanIr, ir, _meanAlpha);
    }

    _energyGreen = _ema(_energyGreen, (green - _meanGreen).abs(), _energyAlpha);
    _energyRed = _ema(_energyRed, (red - _meanRed).abs(), _energyAlpha);
    _energyIr = _ema(_energyIr, (ir - _meanIr).abs(), _energyAlpha);

    final strongestAltEnergy = max(_energyRed, _energyIr);
    final greenLikelyMissing =
        green.abs() < 1e-6 && (red.abs() > 1e-3 || ir.abs() > 1e-3);
    final greenWeakComparedToAlternatives =
        strongestAltEnergy > 1e-6 && _energyGreen < (strongestAltEnergy * 0.35);
    if (greenLikelyMissing || greenWeakComparedToAlternatives) {
      final preferRed = _energyRed >= _energyIr;
      final fallback = preferRed ? red : ir;
      if (fallback.isFinite) {
        return fallback;
      }
    }

    if (green.isFinite) {
      return green;
    }
    if (red.isFinite && ir.isFinite) {
      return red.abs() >= ir.abs() ? red : ir;
    }
    if (red.isFinite) {
      return red;
    }
    if (ir.isFinite) {
      return ir;
    }
    return 0;
  }

  void reset() {
    _isInitialized = false;
    _meanGreen = 0;
    _meanRed = 0;
    _meanIr = 0;
    _energyGreen = 0;
    _energyRed = 0;
    _energyIr = 0;
  }

  double _ema(double state, double value, double alpha) {
    return (state * (1.0 - alpha)) + (value * alpha);
  }
}

class _AmbientLightCanceler {
  bool _isInitialized = false;
  double _meanGreen = 0;
  double _meanAmbient = 0;
  double _ambientVariance = 1.0;
  double _greenAmbientCovariance = 0.0;
  double _ambientGain = 0.65;

  double filter({
    required double green,
    required double ambient,
  }) {
    if (!_isInitialized) {
      _isInitialized = true;
      _meanGreen = green;
      _meanAmbient = ambient;
      return 0;
    }
    const meanAlpha = 0.005;
    const covarianceAlpha = 0.01;

    _meanGreen = (_meanGreen * (1.0 - meanAlpha)) + (green * meanAlpha);
    _meanAmbient = (_meanAmbient * (1.0 - meanAlpha)) + (ambient * meanAlpha);

    final centeredGreen = green - _meanGreen;
    final centeredAmbient = ambient - _meanAmbient;

    _ambientVariance = (_ambientVariance * (1.0 - covarianceAlpha)) +
        ((centeredAmbient * centeredAmbient) * covarianceAlpha);
    _greenAmbientCovariance =
        (_greenAmbientCovariance * (1.0 - covarianceAlpha)) +
            ((centeredGreen * centeredAmbient) * covarianceAlpha);

    if (_ambientVariance > 1e-6) {
      _ambientGain = (_greenAmbientCovariance / _ambientVariance).clamp(
        0.0,
        2.0,
      );
    }

    final cleaned = centeredGreen - (_ambientGain * centeredAmbient);
    return -cleaned;
  }

  void reset() {
    _isInitialized = false;
    _meanGreen = 0;
    _meanAmbient = 0;
    _ambientVariance = 1.0;
    _greenAmbientCovariance = 0.0;
    _ambientGain = 0.65;
  }
}

class _MultiReferenceMotionCanceler {
  final _PadasipStyleMultiInputNlmsCanceler _canceler =
      _PadasipStyleMultiInputNlmsCanceler(
    tapsPerAxis: 16,
  );

  bool _isInitialized = false;
  double _gravityX = 0;
  double _gravityY = 0;
  double _gravityZ = 0;
  double _dynamicX = 0;
  double _dynamicY = 0;
  double _dynamicZ = 0;
  double _referenceScaleX = 0.2;
  double _referenceScaleY = 0.2;
  double _referenceScaleZ = 0.2;

  void updateMotion({
    required double x,
    required double y,
    required double z,
  }) {
    if (!_isInitialized) {
      _isInitialized = true;
      _gravityX = x;
      _gravityY = y;
      _gravityZ = z;
      _dynamicX = 0;
      _dynamicY = 0;
      _dynamicZ = 0;
      _referenceScaleX = 0.2;
      _referenceScaleY = 0.2;
      _referenceScaleZ = 0.2;
      return;
    }

    const gravityAlpha = 0.0202;
    const dynamicAlpha = 0.0945;
    const scaleAlpha = 0.0305;

    _gravityX = (_gravityX * (1.0 - gravityAlpha)) + (x * gravityAlpha);
    _gravityY = (_gravityY * (1.0 - gravityAlpha)) + (y * gravityAlpha);
    _gravityZ = (_gravityZ * (1.0 - gravityAlpha)) + (z * gravityAlpha);

    final hpX = x - _gravityX;
    final hpY = y - _gravityY;
    final hpZ = z - _gravityZ;
    _referenceScaleX =
        (_referenceScaleX * (1.0 - scaleAlpha)) + (hpX.abs() * scaleAlpha);
    _referenceScaleY =
        (_referenceScaleY * (1.0 - scaleAlpha)) + (hpY.abs() * scaleAlpha);
    _referenceScaleZ =
        (_referenceScaleZ * (1.0 - scaleAlpha)) + (hpZ.abs() * scaleAlpha);

    final normalizedHpX = hpX / max(0.08, _referenceScaleX);
    final normalizedHpY = hpY / max(0.08, _referenceScaleY);
    final normalizedHpZ = hpZ / max(0.08, _referenceScaleZ);
    _dynamicX =
        (_dynamicX * (1.0 - dynamicAlpha)) + (normalizedHpX * dynamicAlpha);
    _dynamicY =
        (_dynamicY * (1.0 - dynamicAlpha)) + (normalizedHpY * dynamicAlpha);
    _dynamicZ =
        (_dynamicZ * (1.0 - dynamicAlpha)) + (normalizedHpZ * dynamicAlpha);
  }

  void reset() {
    _isInitialized = false;
    _gravityX = 0;
    _gravityY = 0;
    _gravityZ = 0;
    _dynamicX = 0;
    _dynamicY = 0;
    _dynamicZ = 0;
    _referenceScaleX = 0.2;
    _referenceScaleY = 0.2;
    _referenceScaleZ = 0.2;
    _canceler.reset();
  }

  double filter(
    double value, {
    required double motionLevel,
  }) {
    if (!_isInitialized) {
      return value;
    }
    return _canceler.filter(
      signal: value,
      referenceX: _dynamicX,
      referenceY: _dynamicY,
      referenceZ: _dynamicZ,
      motionLevel: motionLevel,
    );
  }
}

/// Multi-input normalized LMS adaptive canceller adapted from the update rule
/// used in the open-source `padasip` NLMS implementation (MIT):
/// https://github.com/matousc89/padasip
class _PadasipStyleMultiInputNlmsCanceler {
  // filter() below runs once per PPG sample. heart_tracker's PpgFilter uses
  // baseMu=0.08/leakage=0.00025 at its validated 50Hz PPG rate; this app
  // streams PPG at 200Hz (4x), so these are the equivalent rates that give
  // the same real-time adaptation speed at 200Hz. _maxMu is an upper
  // saturation ceiling (already "as fast as possible"), so it doesn't need
  // rate-adjusting.
  static const double _baseMu = 0.0206;
  static const double _maxMu = 1.0;
  static const double _epsilon = 1e-6;
  static const double _leakage = 0.0000625;

  final int tapsPerAxis;
  late final List<double> _weights;
  late final List<double> _historyX;
  late final List<double> _historyY;
  late final List<double> _historyZ;
  late final List<double> _featureVector;

  bool _isInitialized = false;
  double _smoothedError = 0;

  _PadasipStyleMultiInputNlmsCanceler({
    required this.tapsPerAxis,
  }) {
    final length = max(3, tapsPerAxis * 3);
    _weights = List<double>.filled(length, 0, growable: false);
    _historyX = List<double>.filled(tapsPerAxis, 0, growable: false);
    _historyY = List<double>.filled(tapsPerAxis, 0, growable: false);
    _historyZ = List<double>.filled(tapsPerAxis, 0, growable: false);
    _featureVector = List<double>.filled(length, 0, growable: false);
  }

  void reset() {
    _isInitialized = false;
    for (var i = 0; i < _weights.length; i++) {
      _weights[i] = 0;
    }
    for (var i = 0; i < tapsPerAxis; i++) {
      _historyX[i] = 0;
      _historyY[i] = 0;
      _historyZ[i] = 0;
    }
    for (var i = 0; i < _featureVector.length; i++) {
      _featureVector[i] = 0;
    }
    _smoothedError = 0;
  }

  double filter({
    required double signal,
    required double referenceX,
    required double referenceY,
    required double referenceZ,
    required double motionLevel,
  }) {
    if (!signal.isFinite ||
        !referenceX.isFinite ||
        !referenceY.isFinite ||
        !referenceZ.isFinite) {
      return signal;
    }
    if (!_isInitialized) {
      _isInitialized = true;
      _smoothedError = signal;
    }

    _push(_historyX, referenceX);
    _push(_historyY, referenceY);
    _push(_historyZ, referenceZ);
    _composeFeatureVector();

    final predictedNoise = _dot(_weights, _featureVector);
    final error = signal - predictedNoise;
    final norm = _epsilon + _dot(_featureVector, _featureVector);

    final motionScale = (motionLevel / 1.6).clamp(0.0, 1.0);
    final mu = _baseMu + ((_maxMu - _baseMu) * motionScale);
    final step = (mu * error) / norm;

    for (var i = 0; i < _weights.length; i++) {
      final updatedWeight =
          ((1.0 - _leakage) * _weights[i]) + (step * _featureVector[i]);
      _weights[i] = updatedWeight.clamp(-4.0, 4.0);
    }

    // 0.22/0.11 at heart_tracker's validated 50Hz PPG rate; equivalent at
    // this app's 200Hz PPG rate.
    final smoothAlpha = motionLevel > 1.0 ? 0.0602 : 0.0287;
    _smoothedError =
        (_smoothedError * (1.0 - smoothAlpha)) + (error * smoothAlpha);
    return _smoothedError;
  }

  void _push(List<double> history, double sample) {
    for (var i = history.length - 1; i > 0; i--) {
      history[i] = history[i - 1];
    }
    history[0] = sample;
  }

  void _composeFeatureVector() {
    var index = 0;
    for (var i = 0; i < tapsPerAxis; i++) {
      _featureVector[index++] = _historyX[i];
    }
    for (var i = 0; i < tapsPerAxis; i++) {
      _featureVector[index++] = _historyY[i];
    }
    for (var i = 0; i < tapsPerAxis; i++) {
      _featureVector[index++] = _historyZ[i];
    }
  }

  double _dot(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }
}

class _MotionNoiseSuppressor {
  // filter() below runs once per PPG sample. heart_tracker's PpgFilter uses
  // a 25-sample window (500ms) and stepScale=5.5/baseAlpha=0.26 at its
  // validated 50Hz PPG rate. This app streams PPG at 200Hz (4x), so 100
  // samples covers the same 500ms, and stepScale/baseAlpha are the
  // equivalent rates that give the same real-time behavior at 200Hz.
  static const int _windowSize = 100;
  static const double _baseOutlierSigma = 3.0;
  static const double _baseStepScale = 1.375;
  static const double _baseAlpha = 0.0725;

  final List<double> _history = [];

  bool _isInitialized = false;
  double _lastOutput = 0;
  double _gravityMagnitude = 9.81;
  double _motionLevel = 0;

  double get motionLevel => _motionLevel;

  void updateMotionMagnitude(double magnitude) {
    if (!_isInitialized) {
      _gravityMagnitude = magnitude;
      _motionLevel = 0;
      return;
    }

    // This runs once per accelerometer sample. heart_tracker's PpgFilter
    // uses 0.96/0.04 and 0.85/0.15 at its validated 50Hz accelerometer
    // rate; this app streams the accelerometer at 100Hz (2x), so these are
    // the equivalent rates for the same real-time behavior at 100Hz.
    _gravityMagnitude = (_gravityMagnitude * 0.9798) + (magnitude * 0.0202);
    final dynamicMagnitude = (magnitude - _gravityMagnitude).abs();
    final dynamicScale = max(0.08, _gravityMagnitude.abs() * 0.02);
    final normalizedDynamicMagnitude = dynamicMagnitude / dynamicScale;
    _motionLevel =
        ((_motionLevel * 0.922) + (normalizedDynamicMagnitude * 0.078)).clamp(
      0.0,
      8.0,
    );
  }

  void reset() {
    _isInitialized = false;
    _lastOutput = 0;
    _gravityMagnitude = 9.81;
    _motionLevel = 0;
    _history.clear();
  }

  double filter(double rawValue) {
    if (!_isInitialized) {
      _isInitialized = true;
      _lastOutput = rawValue;
      _history
        ..clear()
        ..addAll(List<double>.filled(_windowSize, rawValue));
      return rawValue;
    }

    if (_history.length >= _windowSize) {
      _history.removeAt(0);
    }
    _history.add(rawValue);

    final median = _medianOf(_history);
    final mad = _medianOf(_history.map((value) => (value - median).abs()));
    final sigma = max(1e-3, mad * 1.4826);

    final motionFactor = 1.0 + min(_motionLevel / 0.85, 2.8);
    final outlierSigma = _baseOutlierSigma / motionFactor;
    final minBound = median - (sigma * outlierSigma);
    final maxBound = median + (sigma * outlierSigma);
    final clipped = rawValue.clamp(minBound, maxBound).toDouble();

    final stepLimit = max(1e-3, (_baseStepScale * sigma) / motionFactor);
    final stepped = _lastOutput +
        (clipped - _lastOutput).clamp(-stepLimit, stepLimit).toDouble();

    // Floor 0.07 at heart_tracker's validated 50Hz PPG rate; equivalent at
    // this app's 200Hz PPG rate.
    final alpha = (_baseAlpha / motionFactor).clamp(0.018, _baseAlpha);
    final smoothed = _lastOutput + (alpha * (stepped - _lastOutput));
    _lastOutput = smoothed;
    return smoothed;
  }

  double _medianOf(Iterable<double> values) {
    final sorted = values.toList(growable: false)..sort();
    if (sorted.isEmpty) {
      return 0;
    }
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

class _BoundedSignalNormalizer {
  bool _isInitialized = false;
  double _center = 0;
  double _envelope = 0.25;
  double _lastOutput = 0;

  void reset() {
    _isInitialized = false;
    _center = 0;
    _envelope = 0.25;
    _lastOutput = 0;
  }

  double filter(
    double value, {
    required double motionLevel,
  }) {
    if (!_isInitialized) {
      _isInitialized = true;
      _center = value;
      _envelope = max(0.18, value.abs());
      _lastOutput = 0;
      return 0;
    }

    // heart_tracker's PpgFilter uses 0.01/0.02 at its validated 50Hz PPG
    // rate. This app streams PPG at 200Hz (4x), so these are the equivalent
    // alphas that give the same real-time EMA time constant at 200Hz.
    const centerAlpha = 0.0025;
    const envelopeAlpha = 0.005;

    _center = (_center * (1.0 - centerAlpha)) + (value * centerAlpha);
    final centered = value - _center;
    _envelope =
        (_envelope * (1.0 - envelopeAlpha)) + (centered.abs() * envelopeAlpha);

    final normalized = centered / max(0.12, _envelope);
    final maxAbs = motionLevel > 1.2 ? 1.15 : 1.45;
    final clipped = normalized.clamp(-maxAbs, maxAbs).toDouble();

    // 0.12/0.22 at heart_tracker's validated 50Hz PPG rate; equivalent at
    // this app's 200Hz PPG rate.
    final alpha = motionLevel > 1.2 ? 0.0315 : 0.0602;
    final smoothed = _lastOutput + (alpha * (clipped - _lastOutput));
    _lastOutput = smoothed;
    return smoothed;
  }
}
