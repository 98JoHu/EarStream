import 'dart:math';

/// HRV Calculator
///
/// Computes RMSSD from RR intervals for on-device stress detection.
/// RMSSD (root mean square of successive differences) reflects
/// parasympathetic nervous system activity and is the sole HRV metric
/// used by EarStreAM.
class HrvCalculator {
  /// Compute RMSSD from RR intervals in milliseconds.
  ///
  /// Returns a map with:
  /// - HRV_RMSSD: Root mean square of successive differences (short-term HRV)
  Map<String, double> computeTimeHrv(List<double> rrIntervalsMs) {
    // Filter out NaN values
    final rr = rrIntervalsMs.where((x) => !x.isNaN).toList();

    // Default output
    final out = {'HRV_RMSSD': double.nan};

    if (rr.isEmpty) return out;
    if (rr.length == 1) return {'HRV_RMSSD': 0.0};

    // Compute successive differences
    final diffs = <double>[];
    for (int i = 1; i < rr.length; i++) {
      diffs.add(rr[i] - rr[i - 1]);
    }

    out['HRV_RMSSD'] = _rmssd(diffs);
    return out;
  }

  /// Root mean square of successive differences
  double _rmssd(List<double> diffs) {
    if (diffs.isEmpty) return double.nan;

    final squaredDiffs = diffs.map((x) => x * x);
    final meanSquared = squaredDiffs.reduce((a, b) => a + b) / diffs.length;

    return sqrt(meanSquared);
  }
}
