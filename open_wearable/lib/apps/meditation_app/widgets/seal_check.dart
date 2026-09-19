import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SealCheck extends StatefulWidget {
  final Wearable? wearable;
  final VoidCallback? onSealCheckCompleted;
  final bool showResponsePoints;
  const SealCheck({
    super.key,
    this.wearable,
    this.onSealCheckCompleted,
    this.showResponsePoints = false,
  });

  @override
  State<SealCheck> createState() => _SealCheckState();
}

class _SealCheckState extends State<SealCheck> {
  bool _isMeasuring = false;
  Map<String, dynamic>? _measurementResult;

  Future<void> _startMeasurement() async {
    final wearable = widget.wearable;
    if (wearable == null) return;
    if (!wearable.hasCapability<AudioResponseManager>()) {
      _showSnackBar(
        "This wearable doesn't support the seal check.",
        isError: true,
      );
      return;
    }
    final capability = wearable.requireCapability<AudioResponseManager>();
    setState(() {
      _isMeasuring = true;
    });

    try {
      final result = await capability.measureAudioResponse({});
      if (!mounted) return;
      setState(() {
        _measurementResult = result;
      });
      widget.onSealCheckCompleted?.call();
      _showSnackBar("Seal check completed successfully.");
    } catch (e) {
      if (mounted) {
        _showSnackBar("Seal check failed: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMeasuring = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Theme.of(context).colorScheme.error : Colors.green,
      ),
    );
  }

  Future<void> _saveJson() async {
    final result = _measurementResult;
    if (result == null) {
      _showSnackBar("No measurement result to save.", isError: true);
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/seal_check_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonEncode(result));

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Seal Check Result',
        ),
      );
    } catch (e) {
      if (mounted) {
        _showSnackBar("Could not share the seal check: $e", isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.wearable == null) {
      return const Center(
        child: Text("No wearable connected"),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isMeasuring ? null : _startMeasurement,
                icon: const Icon(Icons.play_arrow),
                label: Text(_isMeasuring ? "Measuring..." : "Measure"),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isMeasuring ? null : _saveJson,
                icon: const Icon(Icons.download),
                label: const Text("Save JSON"),
              ),
            ),
          ],
        ),
        if (_measurementResult != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SealCheckResult(result: _measurementResult!),
              ),
            ),
          ),
        ],
        if (widget.showResponsePoints && _measurementResult != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ResponsePointsDisplay(result: _measurementResult!),
          ),
        ],
      ],
    );
  }
}

class SealCheckResult extends StatelessWidget {
  final Map<String, dynamic> result;

  const SealCheckResult({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final metrics = <(String label, String value)>[
      ("Version", result['version']?.toString() ?? "-1"),
      ("Quality", result['quality']?.toString() ?? "-1"),
      ("Mean Magnitude", result['mean_magnitude']?.toString() ?? "-1.0"),
      ("Number of Peaks", result['num_peaks']?.toString() ?? "-1"),
    ];

    return Wrap(
      runSpacing: 8.0,
      spacing: 16.0,
      children: metrics
          .map(
            (metric) => _buildMetricColumn(label: metric.$1, value: metric.$2),
          )
          .toList(),
    );
  }

  Widget _buildMetricColumn({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }
}

class ResponsePointsDisplay extends StatelessWidget {
  final Map<String, dynamic> result;

  const ResponsePointsDisplay({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final points = (result['points'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map(
          (m) => {
            'frequency_hz': (m['frequency_hz'] as num?)?.toDouble(),
            'frequency_raw_q12_4': (m['frequency_raw_q12_4'] as num?)?.toInt(),
            'magnitude': (m['magnitude'] as num?)?.toDouble(),
          },
        )
        .where((m) => m['frequency_hz'] != null && m['magnitude'] != null)
        .toList();

    points.sort((a, b) => (a['frequency_hz']!).compareTo(b['frequency_hz']!));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Response points',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...points.map((p) {
              final f = p['frequency_hz']!;
              final mag = p['magnitude']!;
              final raw = p['frequency_raw_q12_4'] as int?;

              final subtitle = raw == null
                  ? 'magnitude (uint16 units)'
                  : 'freq raw (Q12.4): $raw • magnitude (uint16 units)';

              return ListTile(
                dense: true,
                title: Text('${f.toStringAsFixed(2)} Hz'),
                trailing: Text(mag.toStringAsFixed(0)),
                subtitle: Text(subtitle),
              );
            }),
          ],
        ),
      ),
    );
  }
}
