import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../model/measurement.dart';
import '../../model/user_account.dart';
import '../../model/activity_tracker.dart' show ActivityLevel;
import '../../widgets/meditation_tile.dart';
import '../../widgets/api_warning.dart';

class BioAdaptiveView extends StatefulWidget {
  const BioAdaptiveView({super.key});

  @override
  State<BioAdaptiveView> createState() => _BioAdaptiveViewState();
}

class _BioAdaptiveViewState extends State<BioAdaptiveView> {
  EarstreamState _earstreamState = EarstreamState.idle;

  @override
  Widget build(BuildContext context) {
    final measurement = context.read<Measurement>();
    final UserAccount userAccount = context.read<UserAccount>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_earstreamState == EarstreamState.running)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: BioAdaptiveContent(measurement: measurement),
            ),
          ),
        if (_earstreamState == EarstreamState.running &&
            !userAccount.hasValidDeepseekKey) ...[
          SizedBox(height: 16),
          APIWarning(serviceName: "Deepseek"),
          SizedBox(height: 16),
        ],
        MeditationTile(meditation: measurement.meditation),
        ElevatedButton.icon(
          onPressed: () => {
            switch (measurement.state) {
              EarstreamState.idle => measurement.start(),
              EarstreamState.running => measurement.stop(),
              EarstreamState.stopped => measurement.resume(),
            },
            setState(() {
              _earstreamState = measurement.state;
            }),
          },
          icon: Icon(
            _earstreamState == EarstreamState.running
                ? Icons.stop
                : Icons.play_arrow,
          ),
          label: Text(
            _earstreamState == EarstreamState.running
                ? "Stop EarStreAM"
                : "Start EarStreAM",
          ),
        ),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => {
                    _earstreamState == EarstreamState.running
                        ? measurement.simulateStress()
                        : null,
                  },
                  icon: const Icon(Icons.psychology),
                  label: const Text("Simulate Stress"),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => {
                    _earstreamState == EarstreamState.running
                        ? measurement.reset()
                        : null,
                    setState(() {
                      _earstreamState = measurement.state;
                    }),
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text("Reset"),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class BioAdaptiveContent extends StatelessWidget {
  const BioAdaptiveContent({
    super.key,
    required this.measurement,
  });

  final Measurement measurement;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MeasurementTile(
                label: "Heart Rate",
                unit: "BPM",
                icon: Icons.favorite,
                iconColor: Colors.redAccent,
                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                listenable: measurement.heartRate,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _MeasurementTile(
                label: "RMSSD",
                unit: "ms",
                icon: Icons.air,
                iconColor: Colors.blueAccent,
                backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                listenable: measurement.rmssd
                    .where((value) => value != null)
                    .map((value) => value!.toStringAsFixed(1)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _MonitoringPhaseTile(
          monitoringPhase: measurement.monitoringPhase,
          progress: measurement.progress,
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: HeartRateChart(
            heartRateStream:
                measurement.heartRate, // Pass the heart rate stream here
            visibleWindow:
                const Duration(minutes: 1), // Show 1min rolling chart
          ),
        ),
        const SizedBox(height: 16),
        _StressLevelTile(listenable: measurement.stressLevel),
        const SizedBox(height: 16),
        _ActivityLevelTile(listenable: measurement.activityLevel),
      ],
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

  const _MeasurementTile({
    required this.label,
    required this.unit,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.listenable,
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
        Column(
          children: [
            Text(label),
            const SizedBox(height: 4),
            if (listenable != null)
              SizedBox(
                width: 80,
                height: 24,
                child: Center(
                  child: StreamBuilder(
                    stream: listenable,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      } else {
                        final value = snapshot.data;
                        return Text(
                          "$value $unit",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ActivityLevelTile extends StatelessWidget {
  final ValueNotifier<ActivityLevel> listenable;
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
  final ValueNotifier<StressLevel> listenable;
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
  final ValueNotifier<MonitoringPhase> monitoringPhase;
  final ValueNotifier<double?> progress;
  const _MonitoringPhaseTile({
    required this.monitoringPhase,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: monitoringPhase,
      builder: (_, value, child) {
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            vertical: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: value.color.withValues(alpha: 0.1),
            border: Border.all(color: value.color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
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
              ValueListenableBuilder<double?>(
                valueListenable: progress,
                builder: (context, progressValue, child) {
                  if (progressValue == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: LinearProgressIndicator(
                      value: progressValue,
                      color: value.color,
                      backgroundColor: value.color.withValues(alpha: 0.1),
                    ),
                  );
                },
              ),
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
