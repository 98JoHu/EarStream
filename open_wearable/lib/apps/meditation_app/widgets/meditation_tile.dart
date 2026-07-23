import 'package:flutter/material.dart';
import '../model/meditation.dart';

class MeditationTile extends StatelessWidget {
  final ValueNotifier<Meditation?> meditation;
  final VoidCallback? onMeditationComplete;

  const MeditationTile({
    super.key,
    required this.meditation,
    this.onMeditationComplete,
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
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.self_improvement, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          "Meditating...",
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<SessionProgress?>(
                      valueListenable: meditation.value!.progress,
                      builder: (context, progress, child) {
                        if (progress == null) return const SizedBox.shrink();

                        final elapsedDuration = progress.segmentElapsed;

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.timer, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '${elapsedDuration.inMinutes.remainder(60).toString().padLeft(2, '0')}:${elapsedDuration.inSeconds.remainder(60).toString().padLeft(2, '0')}',
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Row(
                              children: [
                                const Icon(Icons.layers, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  'Segment ${progress.currentSegment} of ${progress.totalSegments}',
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => {
                        meditation.value!.isPaused
                            ? meditation.value!.resume()
                            : meditation.value!.pause(),
                      },
                      icon: meditation.value!.isPaused
                          ? const Icon(Icons.play_arrow)
                          : const Icon(Icons.pause),
                      label: meditation.value!.isPaused
                          ? const Text("Resume")
                          : const Text("Pause"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => {
                        meditation.value!.stop(),
                        meditation.value = null,
                        // Call the callback to notify that the meditation has completed
                        onMeditationComplete?.call(),
                      },
                      icon: const Icon(Icons.stop),
                      label: const Text("Stop"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          );
        }
      },
    );
  }
}
