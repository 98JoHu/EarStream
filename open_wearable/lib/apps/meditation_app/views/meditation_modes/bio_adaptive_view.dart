import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../model/measurement.dart';
import '../../model/activity_tracker.dart' show ActivityLevel;
import '../../model/meditation.dart';

class BioAdaptiveView extends StatefulWidget {
  const BioAdaptiveView({super.key});

  @override
  State<BioAdaptiveView> createState() => _BioAdaptiveViewState();
}

class _BioAdaptiveViewState extends State<BioAdaptiveView> {
  bool hasStarted = false;

  @override
  Widget build(BuildContext context) {
    final measurement = context.read<Measurement>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasStarted) _buildBioAdaptiveContent(measurement),
        SizedBox(height: hasStarted ? 24 : 0),
        _MeditationTile(meditation: measurement.meditation),
        ElevatedButton.icon(
          onPressed: () => {
            setState(() {
              hasStarted = !hasStarted;
            }),
            hasStarted ? measurement.start() : measurement.stop(),
          },
          icon: Icon(hasStarted ? Icons.stop : Icons.play_arrow),
          label: Text(hasStarted ? "Stop EarStreAM" : "Start EarStreAM"),
        ),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => {
                    hasStarted ? measurement.simulateStress() : null,
                  },
                  icon: const Icon(Icons.psychology),
                  label: const Text("Simulate Stress"),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => {
                    hasStarted ? measurement.reset() : null,
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

  Widget _buildBioAdaptiveContent(Measurement measurement) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
            _MonitoringPhaseTile(listenable: measurement.monitoringPhase),
            const SizedBox(height: 16),
            _StressLevelTile(listenable: measurement.stressLevel),
            const SizedBox(height: 16),
            _ActivityLevelTile(listenable: measurement.activityLevel),
            const SizedBox(height: 16),
            // Inside your UI build tree:
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A), // Slate background
                borderRadius: BorderRadius.circular(16),
              ),
              child: HeartRateChart(
                heartRateStream:
                    measurement.heartRate, // Pass the heart rate stream here
                visibleWindow:
                    const Duration(seconds: 30), // Show 30s rolling chart
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeditationTile extends StatelessWidget {
  final ValueNotifier<Meditation?> meditation;
  const _MeditationTile({
    required this.meditation,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: meditation,
      builder: (context, value, child) {
        if (value == null) {
          return const SizedBox.shrink();
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.green.withValues(alpha: 0.1),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.self_improvement, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      "Meditation in Progress",
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => {
                      meditation.value!.pause(),
                    },
                    icon: const Icon(Icons.pause),
                    label: const Text("Pause"),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => {
                      meditation.value!.stop(),
                      meditation.value = null,
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text("Stop"),
                  ),
                ],
              ),
            ],
          );
        }
      },
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
              )
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
  final ValueNotifier<MonitoringPhase> listenable;
  const _MonitoringPhaseTile({
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
            color: value.color.withValues(alpha: 0.1),
            border: Border.all(color: value.color.withValues(alpha: 0.3)),
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

class HeartRateChart extends StatefulWidget {
  // Pass in the clean broadcast stream from your BiometricPipelineManager
  final Stream<int> heartRateStream;

  /// The duration of history to display on screen at once (e.g., last 30 seconds)
  final Duration visibleWindow;

  const HeartRateChart({
    super.key,
    required this.heartRateStream,
    this.visibleWindow = const Duration(seconds: 30),
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
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    final double latestX = _spots.last.x;
    final double minX =
        (latestX - widget.visibleWindow.inSeconds).clamp(0.0, double.infinity);
    final double maxX = latestX < widget.visibleWindow.inSeconds
        ? widget.visibleWindow.inSeconds.toDouble()
        : latestX;

    return AspectRatio(
      aspectRatio: 1.8,
      child: Padding(
        padding: const EdgeInsets.only(
            right: 18.0, left: 12.0, top: 24.0, bottom: 12.0),
        child: LineChart(
          LineChartData(
            // Axis boundaries: keeps the chart sliding smoothly to the right
            minX: minX,
            maxX: maxX,
            minY: 40, // Standard resting HR lower bound
            maxY: 160, // Standard active HR upper bound

            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.white.withOpacity(0.05),
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
                  getTitlesWidget: (value, meta) {
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        "${value.toInt()}s",
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        "${value.toInt()}",
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
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
                isCurved: true,
                curveSmoothness: 0.35,
                color: const Color(0xFFF43F5E), // Coral / Red pulse line
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(
                    show: false), // Hide dots for continuous line look

                // Subtle gradient fill under the line
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFF43F5E).withOpacity(0.3),
                      const Color(0xFFF43F5E).withOpacity(0.0),
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
