import 'package:flutter/material.dart';

class TimerView extends StatefulWidget {
  const TimerView({super.key});

  @override
  State<TimerView> createState() => _TimerViewState();
}

class _TimerViewState extends State<TimerView> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Timed Meditation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Schedule a meditation by delay or at a specific clock time.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Now'),
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => {},
                  child: const Text('After 5 min'),
                ),
                OutlinedButton(
                  onPressed: () => {},
                  child: const Text('After 10 min'),
                ),
                OutlinedButton(
                  onPressed: () => {},
                  child: const Text('After 30 min'),
                ),
                ElevatedButton.icon(
                  onPressed: () => {},
                  icon: const Icon(Icons.schedule),
                  label: const Text('Pick Time'),
                ),
              ],
            ),
            // TODO: Add List of scheduled sessions with options to edit or cancel
          ],
        ),
      ),
    );
  }
}
