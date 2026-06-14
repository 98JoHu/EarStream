import 'package:flutter/material.dart';
import 'drawer_page.dart';

class SealCheckPage extends StatefulWidget implements DrawerPage {
  const SealCheckPage({super.key});

  @override
  String get label => "OpenEarable 2.0 Seal Check";

  @override
  IconData get icon => Icons.verified_outlined;

  @override
  IconData get selectedIcon => Icons.verified;

  @override
  State<SealCheckPage> createState() => _SealCheckPageState();
}

class _SealCheckPageState extends State<SealCheckPage> {
  bool _isMeasuring = false;

  Future<void> _startMeasurement() async {
    setState(() {
      _isMeasuring = true;
    });

    // TODO: Change to actual measurement logic
    await Future.delayed(const Duration(seconds: 3));

    setState(() {
      _isMeasuring = false;
    });
  }

  Future<void> _saveJson() async {
    // TODO: Implement JSON saving logic
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
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
        ],
      ),
    );
  }
}
