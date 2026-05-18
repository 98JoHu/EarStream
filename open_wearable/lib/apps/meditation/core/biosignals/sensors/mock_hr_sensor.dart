import 'dart:async';
import 'dart:math';
import 'hr_sensor_interface.dart';

/// Mock sensor that simulates realistic HR/HRV data for testing without hardware.
///
/// Usage:
/// ```dart
/// final sensor = MockHrSensor();
/// sensor.hrStream.listen((hr) => print('HR: $hr BPM'));
/// sensor.hrvStream.listen((hrv) => print('HRV RMSSD: $hrv ms'));
///
/// // Simulate stress
/// sensor.simulateStress();
///
/// // Simulate relaxation
/// sensor.simulateRelaxation();
/// ```
class MockHrSensor implements HrSensorInterface {
  final StreamController<double> _hrController =
      StreamController<double>.broadcast();
  final StreamController<Map<String, double>> _hrvController =
      StreamController<Map<String, double>>.broadcast();

  Timer? _timer;
  double _currentHr = 75.0; // Baseline heart rate
  double _currentHrv = 120.0; // Baseline HRV (RMSSD) - realistic value
  double _targetHr = 75.0;
  double _targetHrv = 120.0;
  bool _isActive = false;

  final Random _random = Random();

  // ── Scripted stress scenario ─────────────────────────────────────────────
  // A deterministic 2-minute build-up used for video demos so the story arc
  // is always identical and controlled (no randomness, only tiny sinusoidal
  // breathing fluctuations).
  //
  // Phase 1 (0 – 90 s): slow ramp  HR 67 → 73,  HRV 62 → 46  (below thresholds)
  // Phase 2 (90 – 120 s): fast spike  HR 73 → 97,  HRV 46 → 12  (triggers stress ~t=97 s)
  // After 120 s: holds at peak until simulateRelaxation() / reset() is called.
  bool _scenarioActive = false;
  DateTime? _scenarioStartTime;
  void Function()? _onScenarioPeakReached;
  bool _scenarioPeakFired = false;
  // ── Ornstein-Uhlenbeck process for natural HR/HRV wandering ───────────────
  // Both pre-fill and live scenario use the same OU parameters so the chart
  // looks identical in character across all phases.
  //
  // The parameters are derived from the user's real resting PPG recording:
  //   • time constant τ = 30 s  →  α = exp(-1/30) ≈ 0.9672 per 1-second tick
  //   • steady-state std σ_hr  = 3.0 BPM  (matches Kalman-smoothed ±1.4 BPM
  //     measured from recording; 3 BPM gives visible but realistic wandering)
  //   • σ_step = σ * sqrt(1 - α²) ≈ 0.763 BPM per tick
  //
  // HRV uses a proportional 10 % steady-state band around the current target.
  double _hrOuState  = 0.0;
  double _hrvOuState = 0.0;
  // Box-Muller spare value
  double _gaussianSpare = 0.0;
  bool   _gaussianHasSpare = false;

  static const double _kOuAlpha    = 0.9672; // exp(-1/30)
  static const double _kOuSigmaStep = 0.763;  // σ_step for ±3 BPM steady-state

  /// Polar form of Box-Muller transform — returns standard-normal samples.
  double _nextGaussian() {
    if (_gaussianHasSpare) {
      _gaussianHasSpare = false;
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
    _gaussianHasSpare = true;
    return u * mul;
  }
  // ── Relaxation scenario (gradual calm-down during meditation) ─────────────
  bool _relaxationActive = false;
  DateTime? _relaxationStartTime;
  double _relaxationStartHr = 75.0;
  double _relaxationStartHrv = 42.0;
  static const double _kRelaxationTargetHr = 62.0;  // end-goal BPM (~12% below resting 71)
  static const double _kRelaxationTargetHrv = 90.0; // end-goal RMSSD ms
  static const int _kRelaxationDurationSec = 360;   // 6-minute ramp

  // Scenario baseline / peak constants (public so the screen can pre-seed UI)
  // Baseline derived from a real 110-second PPG recording (resting, not stressed):
  //   median HR = 71.4 BPM, median 8-beat rolling RMSSD = 79.8 ms
  static const double kScenarioBaseHr  = 71.0;
  static const double kScenarioBaseHrv = 80.0;
  static const double _kScenarioPeakHr  = 97.0;
  static const double _kScenarioPeakHrv = 12.0;

  /// Compute the scenario HR and HRV at the given elapsed seconds.
  /// Tiny sinusoidal breathing fluctuation (4 s cycle) adds realism without
  /// randomness – the same input always produces the same output.
  (double hr, double hrv) _scenarioValues(int tSec) {
    double hr, hrv;
    // Phase 1 ends at 50 ms HRV; Phase 2 continues from there to peak.
    // (Keeping end-values in named locals avoids any discontinuity.)
    // Phase 1 (0–90 s): HR 71→80, HRV 80→50  (neither threshold crossed yet)
    // Phase 2 (90–120 s): HR 80→97, HRV 50→12  (both thresholds crossed at ~100 s)
    const double phase1EndHr  = 80.0;
    const double phase1EndHrv = 50.0;
    if (tSec <= 90) {
      final frac = tSec / 90.0;
      hr  = kScenarioBaseHr + (phase1EndHr - kScenarioBaseHr) * frac; // 71 -> 80
      hrv = kScenarioBaseHrv - (kScenarioBaseHrv - phase1EndHrv) * frac; // 80 -> 50
    } else {
      final frac = ((tSec - 90) / 30.0).clamp(0.0, 1.0);
      hr  = phase1EndHr + (_kScenarioPeakHr - phase1EndHr) * frac; // 80 -> 97
      hrv = phase1EndHrv - (phase1EndHrv - _kScenarioPeakHrv) * frac; // 50 -> 12
    }
    // Same 80 s oscillation as the pre-fill — amplitude ±2 BPM matches the
    // ±1.4 BPM Kalman-smoothed variation measured from the real recording.
    // (Oscillation removed — OU process in the timer tick replaces it.)
    return (hr.clamp(40.0, 120.0), hrv.clamp(5.0, 200.0));
  }

  /// Start a scripted 2-minute stress scenario for video demos.
  ///
  /// The sensor immediately begins at a calm baseline and gradually builds to
  /// peak stress. [onPeakReached] is fired once after 120 s when the sensor
  /// has settled at its maximum stress values.
  void startStressScenario({void Function()? onPeakReached}) {
    _scenarioActive = true;
    _scenarioStartTime = DateTime.now();
    _onScenarioPeakReached = onPeakReached;
    _scenarioPeakFired = false;
    // Snap current values to scenario baseline so the chart starts clean.
    // Reset OU state so the wandering starts fresh at zero deviation.
    _currentHr  = kScenarioBaseHr;
    _currentHrv = kScenarioBaseHrv;
    _targetHr   = kScenarioBaseHr;
    _targetHrv  = kScenarioBaseHrv;
    _hrOuState  = 0.0;
    _hrvOuState = 0.0;
  }

  /// Stop the scripted scenario, reverting to target-based behaviour.
  void stopScenario() {
    _scenarioActive = false;
    _scenarioStartTime = null;
    _onScenarioPeakReached = null;
    _relaxationActive = false;
    _relaxationStartTime = null;
  }

  /// Begin a gradual 6-minute relaxation ramp from the current physiological
  /// state down to calm resting values. Call this when a meditation session
  /// starts so the chart shows a smooth, realistic recovery arc.
  void startRelaxationScenario() {
    stopScenario(); // cancels any active stress scenario first
    _relaxationActive = true;
    _relaxationStartTime = DateTime.now();
    _relaxationStartHr  = _currentHr;
    _relaxationStartHrv = _currentHrv;
  }

  // ── End scripted scenario ─────────────────────────────────────────────────

  /// Stream of heart rate values in BPM
  @override
  Stream<double> get hrStream => _hrController.stream;

  /// Stream of HRV metrics (SDNN, RMSSD, pNN50)
  @override
  Stream<Map<String, double>> get hrvStream => _hrvController.stream;

  // Stream of connection state (always connected for mock)
  @override
  Stream<bool> get isConnected => Stream.value(true).asBroadcastStream();

  /// Start generating mock data
  @override
  Future<void> start() async {
    if (_isActive) return;
    _isActive = true;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      double hr, rmssd;

      if (_scenarioActive && _scenarioStartTime != null) {
        // ── Scripted stress scenario: deterministic shape + random noise ───
        final tSec =
            DateTime.now().difference(_scenarioStartTime!).inSeconds;
        final (sHr, sHrv) = _scenarioValues(tSec);
        // OU process: mean-reverting random walk around the deterministic
        // trend.  Replicates the correlated slow wandering seen in real
        // Kalman-filtered HR data (τ=30 s, ±3 BPM steady-state).
        _hrOuState  = _kOuAlpha * _hrOuState  + _kOuSigmaStep * _nextGaussian();
        final hrvOuSigma = (sHrv * 0.025).clamp(0.5, 3.0); // 2.5 % of target
        _hrvOuState = _kOuAlpha * _hrvOuState + hrvOuSigma  * _nextGaussian();
        _currentHr  = (sHr  + _hrOuState ).clamp(40.0, 120.0);
        _currentHrv = (sHrv + _hrvOuState).clamp(5.0, 200.0);
        hr    = _currentHr;
        rmssd = _currentHrv;

        // Fire peak callback exactly once after 120 s
        if (tSec >= 120 && !_scenarioPeakFired) {
          _scenarioPeakFired = true;
          _onScenarioPeakReached?.call();
        }
      } else if (_relaxationActive && _relaxationStartTime != null) {
        // ── Gradual relaxation: smooth ramp from stress back to calm ───────
        final tSec =
            DateTime.now().difference(_relaxationStartTime!).inSeconds;
        final frac = (tSec / _kRelaxationDurationSec).clamp(0.0, 1.0);
        // Ease-out quadratic: fast initial drop, slower approach to target
        final ease = frac * (2.0 - frac);
        final baseHr  = _relaxationStartHr  +
            (_kRelaxationTargetHr  - _relaxationStartHr)  * ease;
        final baseHrv = _relaxationStartHrv +
            (_kRelaxationTargetHrv - _relaxationStartHrv) * ease;
        // Continue OU wandering around the relaxation ramp (OU state NOT
        // reset so the transition from stress is smooth).
        _hrOuState  = _kOuAlpha * _hrOuState  + _kOuSigmaStep * _nextGaussian();
        final relaxHrvOuSigma = (baseHrv * 0.025).clamp(0.5, 3.0);
        _hrvOuState = _kOuAlpha * _hrvOuState + relaxHrvOuSigma * _nextGaussian();
        _currentHr  = (baseHr  + _hrOuState ).clamp(40.0, 120.0);
        _currentHrv = (baseHrv + _hrvOuState).clamp(5.0, 200.0);
        hr    = _currentHr;
        rmssd = _currentHrv;
      } else {
        // ── Normal mode: exponential convergence toward target + noise ─────
        _currentHr += (_targetHr - _currentHr) * 0.95;
        _currentHrv += (_targetHrv - _currentHrv) * 0.95;

        final hrNoise = _random.nextDouble() * 4 - 2; // +/- 2 BPM
        final hrvNoise = _random.nextDouble() * 3 - 1.5; // +/- 1.5 ms
        hr = (_currentHr + hrNoise).clamp(50.0, 120.0);
        rmssd = (_currentHrv + hrvNoise).clamp(10.0, 200.0);
      }

      _hrController.add(hr);
      _hrvController.add({
        'HRV_SDNN': rmssd / 2.7,
        'HRV_RMSSD': rmssd,
        'HRV_pNN50': (rmssd / 3).clamp(0.0, 60.0),
      });
    });
  }

  /// Stop generating mock data
  @override
  void stop() {
    _isActive = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Simulate stress (increase HR, decrease HRV)
  /// Triggers stress detection: HR > 95 OR HRV < 15
  void simulateStress() {
    stopScenario(); // Cancel any running scenario first
    _targetHr = 100.0; // Well above 95 threshold
    _targetHrv = 12.0; // Below 15ms threshold - THIS TRIGGERS STRESS!
  }

  /// Simulate relaxation (decrease HR, increase HRV)
  /// Triggers relaxation detection: HR < 75 AND HRV > 30
  void simulateRelaxation() {
    stopScenario(); // Stop the stress scenario so target-based logic takes over
    _targetHr = 65.0; // Well below 75 threshold
    _targetHrv = 150.0; // High HRV indicates relaxation
  }

  /// Reset to baseline
  @override
  void reset() {
    stopScenario();
    _targetHr = 75.0; // Normal resting HR
    _targetHrv = 120.0; // Good HRV
  }

  /// Dispose resources
  @override
  void dispose() {
    stop();
    _hrController.close();
    _hrvController.close();
  }
}
