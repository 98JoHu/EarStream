import 'dart:math';
import 'dart:async';

import 'package:logger/logger.dart';
import 'package:open_wearable/apps/meditation/model/band_pass_filter_meditation.dart';

Logger _logger = Logger();

/// PPG Filter for Meditation App
/// This is a copy of the Heart Tracker's PPG filter, modified for meditation-specific needs.
/// Separated to avoid dependencies on other apps.
class PpgFilterMeditation {
  final Stream<(int, double)> inputStream;
  final double sampleFreq;

  final double _minProminence = 0.1;
  final int _minPeakDistanceMs = 300; // e.g., 200 BPM max

  double _hrEstimate = 75.0;
  double _p = 1.0;
  final double _q = 0.01;  // process noise
  final double _r = 4.0;
  
  int timestampExponent;   // measurement noise

  Stream<(int, double)>? _filteredStream;
  
  // Stream controller for RR intervals (inter-beat intervals)
  final StreamController<List<double>> _rrIntervalController = StreamController<List<double>>.broadcast();

  PpgFilterMeditation({
    required this.inputStream,
    required this.sampleFreq,
    required this.timestampExponent,
  });

  Stream<(int, double)> get filteredStream {
    final filter = BandPassFilterMeditation(
      sampleFreq: sampleFreq,
      lowCut: 0.5,
      highCut: 4,
    );
    
    if (_filteredStream == null) {
      _logger.d("Creating filtered stream");
      _filteredStream = inputStream.map((event) {
        final (timestamp, rawValue) = event;
        final filteredValue = filter.filter(rawValue);
        return (timestamp, filteredValue);
      }).asBroadcastStream();
    } else {
      _logger.d("Using existing filtered stream");
    }

    return _filteredStream!;
  }
  
  /// Stream of RR intervals (inter-beat intervals) in milliseconds
  /// These are the actual time differences between detected heart beats
  Stream<List<double>> get rrIntervalStream => _rrIntervalController.stream;

  double _kalmanUpdate(double measurement) {
    if (measurement.isNaN || measurement.isInfinite) return _hrEstimate;

    _p += _q;
    final k = _p / (_p + _r);
    _hrEstimate += k * (measurement - _hrEstimate);
    _p *= (1 - k);
    return _hrEstimate;
  }

  List<(int, double)> smoothBuffer(List<(int, double)> raw, {int radius = 2}) {
    final smoothed = <(int, double)>[];
    for (int i = 0; i < raw.length; i++) {
      int start = max(0, i - radius);
      int end = min(raw.length - 1, i + radius);
      final avg = raw.sublist(start, end + 1).map((e) => e.$2).reduce((a, b) => a + b) / (end - start + 1);
      smoothed.add((raw[i].$1, avg));
    }
    return smoothed;
  }

  List<int> detectPeaks(List<(int, double)> buffer) {
    buffer = smoothBuffer(buffer, radius: 4);
    final peakTimestamps = <int>[];

    for (int i = 1; i < buffer.length - 1; i++) {
      final (tPrev, vPrev) = buffer[i - 1];
      final (tCurr, vCurr) = buffer[i];
      final (tNext, vNext) = buffer[i + 1];

      // Skip too-close peaks
      final lastPeak = peakTimestamps.isNotEmpty ? peakTimestamps.last : 0;
      if (tCurr - lastPeak < _minPeakDistanceMs) continue;

      // Simple 3-point peak
      if (vCurr > vPrev && vCurr > vNext &&
          (vCurr - vPrev) > _minProminence &&
          (vCurr - vNext) > _minProminence) {
        peakTimestamps.add(tCurr);
      }
    }

    return peakTimestamps;
  }

  Stream<double> get heartRateStream async* {
    int timestampFactor = pow(10, -timestampExponent).toInt();
    int windowDurationMs = 8 * timestampFactor; // 8 seconds
    final List<(int, double)> buffer = [];

    await for (final (timestamp, value) in filteredStream) {
      buffer.add((timestamp, value));

      buffer.removeWhere((event) => event.$1 < timestamp - windowDurationMs);

      if ((buffer.last.$1 - buffer.first.$1) < windowDurationMs / 2) {
        // Reduced logging - only log every 2 seconds instead of every data point
        // _logger.d("waiting to fill buffer, time difference: ${buffer.last.$1 - buffer.first.$1}");
        continue;
      }

      List<int> peakTimestamps = detectPeaks(buffer);

      // Need at least 2 peaks to compute HR
      if (peakTimestamps.length < 2) {
        // _logger.w("not enough peaks ${peakTimestamps.length}, in buffer of size ${buffer.length}");
        continue;
      }

      final ibiList = <double>[];
      for (int i = 1; i < peakTimestamps.length; i++) {
        // Peak timestamps are in microseconds (timestampExponent=-6)
        // Convert to milliseconds: divide by 1000
        final ibiInMicroseconds = (peakTimestamps[i] - peakTimestamps[i - 1]).toDouble();
        final ibiInMs = ibiInMicroseconds / 1000.0;
        ibiList.add(ibiInMs);
      }
      
      // Debug logging for first few intervals
      if (ibiList.isNotEmpty && (ibiList.first > 5000 || ibiList.first < 300)) {
        _logger.w('Suspicious RR intervals detected: ${ibiList.take(3).toList()}ms, timestampFactor=$timestampFactor, timestampExponent=$timestampExponent');
      }
      
      // Publish RR intervals for HRV analysis (in milliseconds)
      if (ibiList.isNotEmpty) {
        _rrIntervalController.add(ibiList);
      }

      final avgIbi = ibiList.reduce((a, b) => a + b) / ibiList.length;
      if (avgIbi <= 0 || avgIbi.isNaN || avgIbi.isInfinite) {
        _logger.w("unexpected avgIbi: $avgIbi");
        continue;
      }

      // avgIbi is now in milliseconds, so HR = 60000 / avgIbi
      final hr = 60000.0 / avgIbi;
      final smoothedHr = _kalmanUpdate(hr);

      if (smoothedHr > 30 && smoothedHr < 220) {
        yield smoothedHr;
      }

      // Optional: clear buffer for independent windows
      buffer.clear();
    }
  }
}
