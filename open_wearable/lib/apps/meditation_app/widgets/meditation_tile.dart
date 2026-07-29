import 'package:flutter/material.dart';
import '../model/meditation.dart';
import 'emojis.dart';

enum MoodRating {
  veryRelaxed(
    label: "Very Relaxed",
    emoji: AppEmojis.veryRelaxed,
  ),
  relaxed(
    label: "Relaxed",
    emoji: AppEmojis.relaxed,
  ),
  neutral(
    label: "Neutral",
    emoji: AppEmojis.neutral,
  ),
  stressed(
    label: "Stressed",
    emoji: AppEmojis.stressed,
  );

  final String label;
  final String emoji;

  const MoodRating({
    required this.label,
    required this.emoji,
  });
}

class MeditationTile extends StatelessWidget {
  final ValueNotifier<Meditation?> meditationNotifier;
  final VoidCallback? onMeditationComplete;

  const MeditationTile({
    super.key,
    required this.meditationNotifier,
    this.onMeditationComplete,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: meditationNotifier,
      builder: (context, meditationOrNull, child) {
        final meditation = meditationOrNull;
        if (meditation == null) {
          return const SizedBox.shrink();
        }

        // Listen to phase directly (not just meditation.phase.value) so the
        // tile actually rebuilds when the session transitions to finished,
        // instead of getting stuck on whatever phase it first rendered.
        return ValueListenableBuilder<MeditationPhase>(
          valueListenable: meditation.phase,
          builder: (context, phase, child) {
            if (phase == MeditationPhase.finished) {
              return _FinishedMoodCheck(
                onMoodSelected: () {
                  meditation.stop();
                  onMeditationComplete?.call();
                },
              );
            }

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
                      switch (phase) {
                        MeditationPhase.preparing => const _PreparingMessage(),
                        MeditationPhase.welcome => const _WelcomeMessage(),
                        MeditationPhase.segment =>
                          _SegmentProgress(progress: meditation.progress),
                        MeditationPhase.completion =>
                          const _CompletionMessage(),
                        MeditationPhase.finished => const SizedBox.shrink(),
                      },
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: meditation.isPaused,
                        builder: (context, isPaused, child) {
                          return ElevatedButton.icon(
                            onPressed: () {
                              isPaused
                                  ? meditation.resume()
                                  : meditation.pause();
                            },
                            icon: isPaused
                                ? const Icon(Icons.play_arrow)
                                : const Icon(Icons.pause),
                            label: isPaused
                                ? const Text("Resume")
                                : const Text("Pause"),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          meditation.stop();
                          onMeditationComplete?.call();
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
          },
        );
      },
    );
  }
}

class _FinishedMoodCheck extends StatelessWidget {
  final VoidCallback? onMoodSelected;

  const _FinishedMoodCheck({this.onMoodSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.celebration,
                  color: Colors.green,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Great job!',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Text(
            'Your body has calmed down. Well done completing your meditation session!',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),
          Text(
            'How do you feel right now?',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final mood in MoodRating.values) _buildMoodButton(mood),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoodButton(MoodRating mood) {
    return InkWell(
      onTap: () {
        // TODO: Implement logic to handle mood rating selection and stress reduction tracking
        // Stop meditation session
        onMoodSelected?.call();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(mood.emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 4),
            Text(
              mood.label,
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreparingMessage extends StatelessWidget {
  const _PreparingMessage();

  @override
  Widget build(BuildContext context) {
    return const Text(
      "Preparing your meditation session...",
      style: TextStyle(fontSize: 16),
    );
  }
}

class _WelcomeMessage extends StatelessWidget {
  const _WelcomeMessage();

  @override
  Widget build(BuildContext context) {
    return const Text(
      "Welcome to your meditation session.",
      style: TextStyle(fontSize: 16),
    );
  }
}

class _CompletionMessage extends StatelessWidget {
  const _CompletionMessage();

  @override
  Widget build(BuildContext context) {
    return const Text(
      "Congratulations! You've completed your meditation session.",
      style: TextStyle(fontSize: 16),
    );
  }
}

class _SegmentProgress extends StatelessWidget {
  final ValueNotifier<SessionProgress?> progress;

  const _SegmentProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SessionProgress?>(
      valueListenable: progress,
      builder: (context, progress, child) {
        if (progress == null) {
          return const SizedBox.shrink();
        }

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
    );
  }
}
