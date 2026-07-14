import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../model/measurement.dart';
import '../../model/activity_tracker.dart' show ActivityLevel;

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
                  onPressed: () => {},
                  icon: const Icon(Icons.psychology),
                  label: const Text("Simulate Stress"),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => {},
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
                    listenable: measurement.rmssd,
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
            // HeartRateChart
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
