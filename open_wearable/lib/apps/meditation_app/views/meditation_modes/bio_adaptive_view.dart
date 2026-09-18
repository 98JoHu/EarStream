import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../configs/bio_adaptive_mode_config.dart';
import '../../model/measurement.dart';
import '../../model/bio_adaptive_session_config.dart';
import '../../model/meditation_analytics.dart';
import '../../model/measurement_phase.dart'
    show
        BaselinePhase,
        CalibrationPhase,
        MonitoringPhase,
        StressMonitoringPhase;
import '../../model/stress_detector.dart' show StressLevel;
import '../../model/user_account.dart';
import '../../model/activity_tracker.dart' show ActivityLevel;
import '../../widgets/meditation_tile.dart';
import '../../widgets/api_warning.dart';

enum EarstreamState { idle, running, paused }

class BioAdaptiveView extends StatefulWidget {
  final Sensor ppgSensor;
  final Sensor accelerometerSensor;
  final Sensor gyroscopeSensor;
  final SensorConfigurationProvider sensorConfigProvider;
  final UserAccount? userAccount;
  final BioAdaptiveSessionConfig sessionConfig;
  final MeditationAnalyticsStore? analyticsStore;
  const BioAdaptiveView({
    super.key,
    required this.ppgSensor,
    required this.accelerometerSensor,
    required this.gyroscopeSensor,
    required this.sensorConfigProvider,
    this.userAccount,
    this.sessionConfig = BioAdaptiveSessionConfig.standard,
    this.analyticsStore,
  });

  @override
  State<BioAdaptiveView> createState() => _BioAdaptiveViewState();
}

class _BioAdaptiveViewState extends State<BioAdaptiveView> {
  EarstreamState _earstreamState = EarstreamState.idle;
  Measurement? _measurement;

  void _startEarstream(UserAccount account) {
    _measurement?.dispose();
    final measurement = Measurement.live(
      ppgSensor: widget.ppgSensor,
      accelerometerSensor: widget.accelerometerSensor,
      gyroscopeSensor: widget.gyroscopeSensor,
      sensorConfigProvider: widget.sensorConfigProvider,
      userAccount: account,
      sessionConfig: widget.sessionConfig,
      analyticsStore: widget.analyticsStore,
    );
    setState(() {
      _measurement = measurement;
      _earstreamState = EarstreamState.running;
    });
    measurement.start();
  }

  void _pauseEarstream() {
    _measurement?.pause();
    setState(() {
      _earstreamState = EarstreamState.paused;
    });
  }

  void _resetEarstream() {
    _measurement?.dispose();
    setState(() {
      _measurement = null;
      _earstreamState = EarstreamState.idle;
    });
  }

  void _playRecordedStress(UserAccount account) {
    if (!widget.sessionConfig.allowStressSimulation) return;
    _measurement?.dispose();
    final measurement = Measurement.recordedStress(
      userAccount: account,
      restingActivityLevel: ActivityLevel.resting,
      sessionConfig: widget.sessionConfig,
    );
    setState(() {
      _measurement = measurement;
      _earstreamState = EarstreamState.running;
    });
    measurement.start();
  }

  void _resumeEarstream() {
    _measurement?.resume();
    setState(() {
      _earstreamState = EarstreamState.running;
    });
  }

  @override
  void dispose() {
    _measurement?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UserAccount userAccount =
        widget.userAccount ?? context.read<UserAccount>();
    final measurement = _measurement;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // TODO: write this more clean
        if (_earstreamState == EarstreamState.running && measurement != null)
          BioAdaptiveContent(measurement: measurement),
        if (_earstreamState == EarstreamState.running &&
            !userAccount.hasValidDeepseekKey) ...[
          SizedBox(height: 16),
          APIWarning(serviceName: "Deepseek"),
          SizedBox(height: 16),
        ],
        if (_earstreamState == EarstreamState.running &&
            !userAccount.hasValidSelectedTtsProvider) ...[
          APIWarning(serviceName: userAccount.ttsProvider.label),
          const SizedBox(height: 16),
        ],
        if (_earstreamState == EarstreamState.running && measurement != null)
          MeditationTile(
            meditationNotifier: measurement.meditation,
            onMeditationComplete: measurement.dismissMeditation,
          ),
        if (_earstreamState == EarstreamState.running)
          const SizedBox(height: 8),
        // Control Buttons
        BioAdaptiveControls(
          earstreamState: _earstreamState,
          onStart: () => _startEarstream(userAccount),
          onResume: _resumeEarstream,
          onPause: _pauseEarstream,
          onSimulateStress: () => _playRecordedStress(userAccount),
          onReset: _resetEarstream,
          showStressSimulation: widget.sessionConfig.allowStressSimulation,
        ),
      ],
    );
  }
}

class BioAdaptiveControls extends StatelessWidget {
  final EarstreamState earstreamState;
  final VoidCallback onStart;
  final VoidCallback onResume;
  final VoidCallback onPause;
  final VoidCallback onSimulateStress;
  final VoidCallback onReset;
  final bool showStressSimulation;

  const BioAdaptiveControls({
    super.key,
    required this.earstreamState,
    required this.onStart,
    required this.onResume,
    required this.onPause,
    required this.onSimulateStress,
    required this.onReset,
    this.showStressSimulation = true,
  });

  @override
  Widget build(BuildContext context) {
    final isIdle = EarstreamState.idle == earstreamState;
    final isRunning = EarstreamState.running == earstreamState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          icon: Icon(
            isRunning ? Icons.pause : Icons.play_arrow,
          ),
          onPressed: () {
            switch (earstreamState) {
              case EarstreamState.idle:
                onStart();
                break;
              case EarstreamState.running:
                onPause();
                break;
              case EarstreamState.paused:
                onResume();
                break;
            }
          },
          label: Text(
            isIdle
                ? "Start EarStreAM"
                : isRunning
                    ? "Stop EarStreAM"
                    : "Resume EarStreAM",
          ),
        ),
        const SizedBox(height: 8),
        if (showStressSimulation)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isRunning ? onSimulateStress : null,
                    icon: const Icon(Icons.psychology),
                    label: const Text("Simulate Stress"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !isIdle ? onReset : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Reset"),
                  ),
                ),
              ],
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: !isIdle ? onReset : null,
            icon: const Icon(Icons.refresh),
            label: const Text("Reset"),
          ),
      ],
    );
  }
}

class BioAdaptiveContent extends StatelessWidget {
  final Measurement measurement;
  const BioAdaptiveContent({
    super.key,
    required this.measurement,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MonitoringPhase>(
      valueListenable: measurement.monitoringPhase,
      builder: (context, phase, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MonitoringPhaseTile(
              phase: phase,
              progress: measurement.progress,
            ),
            const SizedBox(height: 8),
            if (phase is CalibrationPhase)
              const _CalibrationPanel()
            else
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _MeasurementTile(
                              key: ValueKey('heart-rate-${phase.runtimeType}'),
                              label: "Heart Rate",
                              unit: "BPM",
                              icon: Icons.favorite,
                              iconColor: Colors.redAccent,
                              backgroundColor:
                                  Colors.redAccent.withValues(alpha: 0.1),
                              listenable: measurement.heartRate,
                              initialData: phase is StressMonitoringPhase
                                  ? measurement.baselineHeartRate
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MeasurementTile(
                              key: ValueKey('rmssd-${phase.runtimeType}'),
                              label: "RMSSD",
                              unit: "ms",
                              icon: Icons.show_chart,
                              iconColor: Colors.blueAccent,
                              backgroundColor:
                                  Colors.blueAccent.withValues(alpha: 0.1),
                              listenable: measurement.rmssd
                                  .where((value) => value != null)
                                  .map((value) => value!.toStringAsFixed(1)),
                              initialData: phase is StressMonitoringPhase
                                  ? measurement.baselineRmssd
                                      ?.toStringAsFixed(1)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: HeartRateChart(
                          heartRateStream: measurement.heartRate,
                          visibleWindow:
                              BioAdaptiveModeConfig.chartVisibleWindow,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StressLevelTile(listenable: measurement.stressLevel),
                      const SizedBox(height: 8),
                      _ActivityLevelTile(listenable: measurement.activityLevel),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _CalibrationPanel extends StatelessWidget {
  const _CalibrationPanel();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.tune, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preparing the signal',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Warming the signal filters. Heart rate and RMSSD measurement begin after calibration.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeasurementTile extends StatelessWidget {
  final String label;
  final String unit;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Stream<dynamic>? listenable;
  final dynamic initialData;

  const _MeasurementTile({
    super.key,
    required this.label,
    required this.unit,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.listenable,
    this.initialData,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(icon, color: iconColor),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (listenable != null)
                SizedBox(
                  height: 24,
                  child: StreamBuilder(
                    stream: listenable,
                    initialData: initialData,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                "Loading...",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: iconColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1,
                                backgroundColor: backgroundColor,
                                color: iconColor,
                              ),
                            ),
                          ],
                        );
                      }
                      final value = snapshot.data;
                      return FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "$value $unit",
                          maxLines: 1,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityLevelTile extends StatelessWidget {
  final ValueListenable<ActivityLevel> listenable;
  const _ActivityLevelTile({
    required this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: listenable,
      builder: (_, value, child) {
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            vertical: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.blueGrey[50],
            border: Border.all(color: Colors.blueGrey[200]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(value.icon, color: Colors.blueGrey[700]),
              const SizedBox(width: 8),
              Text(
                value.label,
                style: TextStyle(
                  color: Colors.blueGrey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StressLevelTile extends StatelessWidget {
  final ValueListenable<StressLevel> listenable;
  const _StressLevelTile({
    required this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: listenable,
      builder: (context, value, child) {
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            vertical: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: value.backgroundColor,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(value.icon, color: value.color),
              const SizedBox(width: 8),
              Text(
                value.label,
                style: TextStyle(
                  color: value.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonitoringPhaseTile extends StatelessWidget {
  final MonitoringPhase phase;
  final ValueListenable<double?> progress;
  const _MonitoringPhaseTile({
    required this.phase,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: progress,
      builder: (context, progressValue, child) {
        final isWaitingForSignal = progressValue == 1.0 && !phase.canAdvance;
        final waitingMessage = switch (phase) {
          BaselinePhase(:final hasValidHeartRate, :final hasValidRmssd) =>
            switch ((hasValidHeartRate, hasValidRmssd)) {
              (false, false) => 'Waiting for valid heart-rate and RMSSD data.',
              (false, true) => 'Waiting for valid heart-rate data.',
              (true, false) => 'Waiting for valid RMSSD data.',
              (true, true) => '',
            },
          _ => 'Waiting for valid physiological data.',
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: phase.color.withValues(alpha: 0.1),
            border: Border.all(color: phase.color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(phase.icon, color: phase.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      phase.label,
                      style: TextStyle(
                        color: phase.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (progressValue != null)
                    SizedBox(
                      width: 96,
                      child: LinearProgressIndicator(
                        value: progressValue,
                        color: phase.color,
                        backgroundColor: phase.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              if (isWaitingForSignal) ...[
                const SizedBox(height: 8),
                Text(
                  '$waitingMessage Check the earbud fit and remain still; only measured values will be used.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: phase.color,
                      ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class HeartRateChart extends StatefulWidget {
  // Pass in the clean broadcast stream from your BiometricPipelineManager
  final Stream<int> heartRateStream;

  /// The duration of history to display on screen at once (e.g., last 3 minutes)
  final Duration visibleWindow;

  const HeartRateChart({
    super.key,
    required this.heartRateStream,
    this.visibleWindow = const Duration(minutes: 3),
  });

  @override
  State<HeartRateChart> createState() => _HeartRateChartState();
}

class _HeartRateChartState extends State<HeartRateChart> {
  StreamSubscription? _subscription;
  final List<FlSpot> _spots = [];

  // Track elapsed seconds relative to when the chart started
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _subscribeToStream();
  }

  void _subscribeToStream() {
    _subscription?.cancel();
    _subscription = widget.heartRateStream.listen((heartRate) {
      // Guard against zero/unwarmed data points
      if (heartRate <= 0) return;

      _startTime ??= DateTime.now();
      final elapsedSeconds =
          DateTime.now().difference(_startTime!).inMilliseconds / 1000.0;

      setState(() {
        // 1. Add the new data point (x: seconds, y: heart rate)
        _spots.add(FlSpot(elapsedSeconds, heartRate.toDouble()));

        // 2. Trim old data points that fall outside the rolling window frame
        final cutoffTime = elapsedSeconds - widget.visibleWindow.inSeconds;
        _spots.removeWhere((spot) => spot.x < cutoffTime);
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_spots.isEmpty) {
      return const Center(
        child: Text(
          "Waiting for pulse data...",
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      );
    }

    final double latestX = _spots.last.x;
    final double minX =
        (latestX - widget.visibleWindow.inSeconds).clamp(0.0, double.infinity);
    final double maxX = latestX < widget.visibleWindow.inSeconds
        ? widget.visibleWindow.inSeconds.toDouble()
        : latestX;

    // Adaptive Y bounds: fit the currently visible data instead of a fixed
    // 40-160 range, with a floor so a near-flat reading doesn't zoom in to
    // the point of looking noisy.
    final heartRates = _spots.map((spot) => spot.y);
    final dataMinY = heartRates.reduce((a, b) => a < b ? a : b);
    final dataMaxY = heartRates.reduce((a, b) => a > b ? a : b);
    final yPadding = ((dataMaxY - dataMinY) * 0.25).clamp(5.0, double.infinity);
    final minY = (dataMinY - yPadding).clamp(0.0, double.infinity);
    final maxY = dataMaxY + yPadding;

    // Wider, fixed tick spacing on the time axis instead of fl_chart's
    // default (which packs in a label every ~2s).
    final xAxisInterval = (widget.visibleWindow.inSeconds / 3).roundToDouble();

    return AspectRatio(
      aspectRatio: 1.8,
      child: Padding(
        padding: const EdgeInsets.only(
          right: 18.0,
          left: 12.0,
          top: 24.0,
          bottom: 12.0,
        ),
        child: LineChart(
          LineChartData(
            // Axis boundaries: keeps the chart sliding smoothly to the right
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,

            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.grey.shade200,
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: xAxisInterval,
                  getTitlesWidget: (value, meta) {
                    if (value == meta.max || value == meta.min) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        "${value.toInt()}s",
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: (maxY - minY) / 4,
                  getTitlesWidget: (value, meta) {
                    if (value == meta.max || value == meta.min) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        "${value.toInt()}",
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 11,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: _spots,
                isCurved: false,
                color: Colors.redAccent,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) =>
                      FlDotCirclePainter(
                    radius: 2,
                    color: Colors.redAccent,
                    strokeWidth: 1,
                    strokeColor: Colors.white,
                  ),
                ),

                // Subtle gradient fill under the line
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      Colors.redAccent.withValues(alpha: 0.1),
                      Colors.redAccent.withValues(alpha: 0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
