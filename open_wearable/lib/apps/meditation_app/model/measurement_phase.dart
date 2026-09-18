import 'dart:async';

import 'package:flutter/material.dart';

import 'biometric_source.dart';
import 'bio_adaptive_session_config.dart';
import 'stress_detector.dart';
import 'user_account.dart';
import 'hr_hrv_processor.dart' show HeartRateSample;

typedef PhaseElapsed = Duration Function();

class PhaseContext {
  final BiometricSource source;
  final StressDetector detector;

  const PhaseContext({
    required this.source,
    required this.detector,
  });
}

sealed class MonitoringPhase {
  String get label;
  IconData get icon;
  Color get color;

  Duration? get duration;

  /// Timed phases may hold at 100% until the required sensor data is valid.
  bool get canAdvance => true;

  StreamSubscription<HeartRateSample>? activate(
    PhaseContext ctx,
    PhaseElapsed elapsed,
  );
}

class CalibrationPhase extends MonitoringPhase {
  @override
  final Duration duration;

  CalibrationPhase({this.duration = const Duration(seconds: 30)});

  @override
  String get label => "Calibration (${duration.inSeconds}s)";
  @override
  IconData get icon => Icons.settings_outlined;
  @override
  Color get color => Colors.orange;
  @override
  StreamSubscription<HeartRateSample>? activate(
    PhaseContext ctx,
    PhaseElapsed elapsed,
  ) {
    ctx.source.beginCalibration();
    return null;
  }
}

class BaselinePhase extends MonitoringPhase {
  final UserAccount userAccount;
  final BaselineComputationMode computationMode;
  @override
  final Duration duration;

  int _heartRateCount = 0;
  double _heartRateTotal = 0;
  int _rmssdCount = 0;
  double _rmssdTotal = 0;

  BaselinePhase({
    required this.userAccount,
    Duration? duration,
    this.computationMode = BaselineComputationMode.profileBlended,
  }) : duration = duration ?? const Duration(minutes: 5);

  @override
  bool get canAdvance =>
      computationMode == BaselineComputationMode.profileBlended ||
      (_heartRateCount > 0 && _rmssdCount > 0);

  @override
  String get label => "Monitoring \u00b7 Baseline Adjustment";
  @override
  IconData get icon => Icons.straighten_outlined;
  @override
  Color get color => Colors.blue;

  @override
  StreamSubscription<HeartRateSample> activate(
    PhaseContext ctx,
    PhaseElapsed elapsed,
  ) {
    ctx.source.beginMeasurement();
    if (computationMode == BaselineComputationMode.physiologicalOnly) {
      return ctx.source.biometrics.listen((data) {
        _heartRateTotal += data.heartRate;
        _heartRateCount++;
        userAccount.baselineHeartRate =
            (_heartRateTotal / _heartRateCount).round();

        if (data.rmssd != null) {
          _rmssdTotal += data.rmssd!;
          _rmssdCount++;
          userAccount.baselineRMSSD = _rmssdTotal / _rmssdCount;
        }
      });
    }

    final (baselineHeartRate, baselineRmssd) = userAccount.baselineBiometrics;

    return ctx.source.biometrics.listen((data) {
      final timeRatio =
          (elapsed().inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

      final studyWeight = timeRatio * 0.3;
      final measuredWeight = 1.0 - studyWeight;

      final dynamicHeartRate =
          (studyWeight * baselineHeartRate + measuredWeight * data.heartRate)
              .round();
      userAccount.baselineHeartRate = dynamicHeartRate;

      if (data.rmssd != null) {
        userAccount.baselineRMSSD =
            studyWeight * baselineRmssd + measuredWeight * data.rmssd!;
      }
    });
  }
}

class StressMonitoringPhase extends MonitoringPhase {
  @override
  String get label => "Monitoring";
  @override
  IconData get icon => Icons.monitor_heart;
  @override
  Color get color => const Color(0xFF4ECDC4);
  @override
  Duration? get duration => null;

  @override
  StreamSubscription<HeartRateSample> activate(
    PhaseContext ctx,
    PhaseElapsed elapsed,
  ) {
    ctx.source.beginMeasurement();
    return ctx.source.biometrics.listen((sample) {
      ctx.detector.onSample(
        sample,
        suppress: ctx.source.suppressStressDetection,
      );
    });
  }
}

class MonitoringPhaseController {
  final PhaseContext _ctx;
  final List<MonitoringPhase> _phases;

  late final ValueNotifier<MonitoringPhase> phase;
  final ValueNotifier<double?> progress = ValueNotifier(null);

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  StreamSubscription<HeartRateSample>? _phaseSub;
  int _index = 0;

  MonitoringPhaseController({
    required PhaseContext ctx,
    required List<MonitoringPhase> phases,
  })  : _ctx = ctx,
        _phases = phases {
    phase = ValueNotifier(_phases.first);
  }

  MonitoringPhase get current => _phases[_index];

  void start() {
    _index = 0;
    phase.value = current;
    _stopwatch
      ..reset()
      ..start();
    _activate();
    _startTicker();
  }

  void pause() {
    _stopwatch.stop();
    _ticker?.cancel();
    _phaseSub?.cancel();
  }

  void resume() {
    _stopwatch.start();
    _activate();
    if (current.duration != null) _startTicker();
  }

  void reset() {
    _ticker?.cancel();
    _phaseSub?.cancel();
    _stopwatch
      ..stop()
      ..reset();
    _index = 0;
    phase.value = current;
    progress.value = null;
  }

  void dispose() {
    _ticker?.cancel();
    _phaseSub?.cancel();
    phase.dispose();
    progress.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _tick() {
    final duration = current.duration;
    if (duration == null) {
      progress.value = null;
      return; // indefinite phase — nothing to time or advance
    }
    progress.value =
        (_stopwatch.elapsed.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0);
    if (_stopwatch.elapsed >= duration && current.canAdvance) {
      _advance();
    }
  }

  void _advance() {
    if (_index >= _phases.length - 1) return; // last phase; stay put
    _phaseSub?.cancel();
    _index++;
    phase.value = current;
    _stopwatch
      ..reset()
      ..start();
    _activate();

    // Once we reach an indefinite phase, the ticker has nothing left to do.
    if (current.duration == null) {
      _ticker?.cancel();
      progress.value = null;
    }
  }

  void _activate() {
    _phaseSub?.cancel();
    _phaseSub = current.activate(_ctx, () => _stopwatch.elapsed);
  }
}
