import 'package:flutter/material.dart';

class DemoView extends StatefulWidget {
  const DemoView({super.key});

  @override
  State<DemoView> createState() => _DemoViewState();
}

class _DemoViewState extends State<DemoView> {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  // TODO: Scale image accordingly
                  child: Image.asset(
                    "lib/apps/meditation_app/assets/ubicomp_logo.png",
                    width: 40,
                    height: 40,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    "ACM UbiComp 2026 Demo",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              "Welcome to EarStream! This demo lets you experience a closed-loop earable system for stress-adaptive meditation. Please choose between two demo modes to start your experience.",
              style: TextStyle(
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => {},
                icon: const Icon(Icons.monitor_heart_outlined),
                label: const Text('Biosignal-Adaptive Demo'),
                style: ElevatedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => {},
                icon: const Icon(Icons.account_circle_outlined),
                label: const Text('Personalized Meditation Only'),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
