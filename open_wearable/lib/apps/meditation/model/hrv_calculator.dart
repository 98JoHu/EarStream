import 'dart:math';

/// HRV Calculator - Enhanced version with more metrics
/// 
/// Computes comprehensive time-domain HRV metrics from RR intervals.
/// Inspired by pyHRV but implemented in pure Dart for on-device processing.
/// 
/// Usage:
/// ```dart
/// final calc = HrvCalculator();
/// final rrIntervals = [800.0, 820.0, 810.0, 805.0, 815.0]; // in ms
/// final hrv = calc.computeTimeHrv(rrIntervals);
/// 
/// print('SDNN: ${hrv['HRV_SDNN']}');
/// print('RMSSD: ${hrv['HRV_RMSSD']}');
/// print('pNN50: ${hrv['HRV_pNN50']}');
/// ```
class HrvCalculator {
  /// Compute comprehensive time-domain HRV metrics from RR intervals in milliseconds.
  /// 
  /// Returns a map with:
  /// - HRV_SDNN: Standard deviation of NN intervals (overall HRV)
  /// - HRV_RMSSD: Root mean square of successive differences (short-term HRV)
  /// - HRV_pNN50: Percentage of successive differences > 50ms (parasympathetic activity)
  /// - HRV_pNN20: Percentage of successive differences > 20ms (more sensitive)
  /// - HRV_MEAN: Mean RR interval
  /// - HRV_MEDIAN: Median RR interval
  /// - HRV_MIN: Minimum RR interval
  /// - HRV_MAX: Maximum RR interval
  /// - HRV_RANGE: Range of RR intervals (max - min)
  Map<String, double> computeTimeHrv(List<double> rrIntervalsMs) {
    // Filter out NaN values
    final rr = rrIntervalsMs.where((x) => !x.isNaN).toList();
    
    // Default output
    final out = {
      'HRV_SDNN': double.nan,
      'HRV_RMSSD': double.nan,
      'HRV_pNN50': double.nan,
      'HRV_pNN20': double.nan,
      'HRV_MEAN': double.nan,
      'HRV_MEDIAN': double.nan,
      'HRV_MIN': double.nan,
      'HRV_MAX': double.nan,
      'HRV_RANGE': double.nan,
    };
    
    // Edge cases
    if (rr.isEmpty) return out;
    
    if (rr.length == 1) {
      return {
        'HRV_SDNN': 0.0,
        'HRV_RMSSD': 0.0,
        'HRV_pNN50': 0.0,
        'HRV_pNN20': 0.0,
        'HRV_MEAN': rr[0],
        'HRV_MEDIAN': rr[0],
        'HRV_MIN': rr[0],
        'HRV_MAX': rr[0],
        'HRV_RANGE': 0.0,
      };
    }
    
    // Compute successive differences
    final diffs = <double>[];
    for (int i = 1; i < rr.length; i++) {
      diffs.add(rr[i] - rr[i - 1]);
    }
    
    // Basic statistics
    out['HRV_MEAN'] = _mean(rr);
    out['HRV_MEDIAN'] = _median(rr);
    out['HRV_MIN'] = rr.reduce((a, b) => a < b ? a : b);
    out['HRV_MAX'] = rr.reduce((a, b) => a > b ? a : b);
    out['HRV_RANGE'] = out['HRV_MAX']! - out['HRV_MIN']!;
    
    // SDNN: Standard deviation of RR intervals
    out['HRV_SDNN'] = _standardDeviation(rr);
    
    // RMSSD: Root mean square of successive differences
    out['HRV_RMSSD'] = _rmssd(diffs);
    
    // pNN50: Percentage of diffs > 50ms
    out['HRV_pNN50'] = _pnnX(diffs, 50.0);
    
    // pNN20: Percentage of diffs > 20ms
    out['HRV_pNN20'] = _pnnX(diffs, 20.0);
    
    return out;
  }
  
  /// Mean of values
  double _mean(List<double> values) {
    if (values.isEmpty) return double.nan;
    return values.reduce((a, b) => a + b) / values.length;
  }
  
  /// Median of values
  double _median(List<double> values) {
    if (values.isEmpty) return double.nan;
    
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    
    if (sorted.length % 2 == 1) {
      return sorted[middle];
    } else {
      return (sorted[middle - 1] + sorted[middle]) / 2.0;
    }
  }
  
  /// Standard deviation (population, not sample - ddof=0 in numpy)
  /// This measures the overall variability of ALL RR intervals
  double _standardDeviation(List<double> values) {
    if (values.isEmpty) return double.nan;
    if (values.length == 1) return 0.0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
        .map((x) => pow(x - mean, 2))
        .reduce((a, b) => a + b) / values.length;
    
    return sqrt(variance);
  }
  
  /// Root mean square of successive differences
  double _rmssd(List<double> diffs) {
    if (diffs.isEmpty) return double.nan;
    
    final squaredDiffs = diffs.map((x) => x * x);
    final meanSquared = squaredDiffs.reduce((a, b) => a + b) / diffs.length;
    
    return sqrt(meanSquared);
  }
  
  /// Percentage of successive differences > threshold
  double _pnnX(List<double> diffs, double threshold) {
    if (diffs.isEmpty) return 0.0;
    
    final count = diffs.where((x) => x.abs() > threshold).length;
    return 100.0 * count / diffs.length;
  }
}
