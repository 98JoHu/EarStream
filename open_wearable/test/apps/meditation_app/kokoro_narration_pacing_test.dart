// Covers how narration is broken into synthesis pieces and where the pauses go.
//
// sherpa-onnx joins its own pieces with no gap and scales silence only inside
// a piece, so commas were being stretched while sentence endings ran straight
// into the next sentence. Deciding the pieces here is what puts that right, and
// it is also what keeps any one piece clear of the token ceiling that would
// otherwise exit the process.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/apps/meditation_app/configs/overall_config.dart';
import 'package:open_wearable/apps/meditation_app/model/kokoro_narration_pacing.dart';

void main() {
  const phrasePause = OverallMeditationConfig.kokoroPhrasePause;
  const sentencePause = OverallMeditationConfig.kokoroSentencePause;

  group('phrase splitting', () {
    test('a sentence ending gets the longer pause', () {
      final phrases = splitNarrationIntoPhrases(
        'Settle into the chair. Let your shoulders drop.',
      );

      expect(phrases.map((p) => p.text), [
        'Settle into the chair.',
        'Let your shoulders drop.',
      ]);
      expect(phrases.first.pause, sentencePause);
      // Nothing follows the last phrase.
      expect(phrases.last.pause, Duration.zero);
    });

    test('an ellipsis is one boundary and gets the shorter pause', () {
      final phrases = splitNarrationIntoPhrases(
        'Breathe in slowly... and let it go.',
      );

      expect(phrases.map((p) => p.text), [
        'Breathe in slowly...',
        'and let it go.',
      ]);
      expect(phrases.first.pause, phrasePause);
      expect(phrasePause, lessThan(sentencePause));
    });

    test('commas stay inside a phrase, where the voice paces them itself', () {
      final phrases = splitNarrationIntoPhrases(
        'Feel the ground beneath you, stable and wide.',
      );

      expect(phrases, hasLength(1));
      expect(phrases.single.text, contains(','));
    });

    test('a terminator inside a word is not a boundary', () {
      final phrases = splitNarrationIntoPhrases('Hold for 1.5 breaths now.');
      expect(phrases, hasLength(1));
      expect(phrases.single.text, 'Hold for 1.5 breaths now.');
    });

    test('punctuation alone is never sent to the engine', () {
      // The generator occasionally emits a stray run of dots as its own
      // sentence. There is nothing to pronounce, so it becomes extra pause on
      // the phrase before it instead of an empty synthesis call.
      final phrases = splitNarrationIntoPhrases(
        'Breathe in. ... Breathe out.',
      );

      expect(phrases.map((p) => p.text), ['Breathe in.', 'Breathe out.']);
      expect(phrases.first.pause, sentencePause + phrasePause);
    });

    test('text with nothing speakable yields nothing', () {
      expect(splitNarrationIntoPhrases('... ...'), isEmpty);
    });

    test('whitespace is normalised and empty input yields nothing', () {
      expect(
        splitNarrationIntoPhrases('  Breathe   in.\n\n  Breathe out.  ')
            .map((p) => p.text),
        ['Breathe in.', 'Breathe out.'],
      );
      expect(splitNarrationIntoPhrases('   '), isEmpty);
    });

    test('a real generated segment keeps every piece under the ceiling', () {
      const segment =
          'Feel the ground beneath you, stable and wide... imagine a quiet '
          'beach at sunrise... breathe in slowly through your nose, drawing in '
          'the cool, salty air... and let the out-breath flow softly, longer '
          'than the in-breath, like a wave receding... feel your body settle a '
          'little more with each breath.';

      final phrases = splitNarrationIntoPhrases(segment);
      expect(phrases.length, greaterThan(1));
      for (final phrase in phrases) {
        expect(
          phrase.text.length,
          lessThanOrEqualTo(OverallMeditationConfig.kokoroMaxPhraseCharacters),
        );
      }
      // Nothing is dropped on the way through.
      final rejoined =
          phrases.map((p) => p.text).join(' ').replaceAll(RegExp(r'\s+'), ' ');
      expect(rejoined, segment.replaceAll(RegExp(r'\s+'), ' '));
    });

    test('one long sentence is still cut below the ceiling', () {
      // Generated segments reach 650 characters in a single sentence. Handing
      // that to Kokoro whole calls SHERPA_ONNX_EXIT and kills the app.
      final long =
          '${List.filled(80, 'breathe deeply and slowly').join(', ')}.';
      expect(long.length, greaterThan(650));

      final phrases = splitNarrationIntoPhrases(long);
      for (final phrase in phrases) {
        expect(
          phrase.text.length,
          lessThanOrEqualTo(OverallMeditationConfig.kokoroMaxPhraseCharacters),
        );
      }
    });

    test('a single unbroken run is cut rather than passed through', () {
      final runOn = 'a' * 900;
      final phrases = splitNarrationIntoPhrases(runOn);
      expect(phrases.length, greaterThan(1));
      for (final phrase in phrases) {
        expect(
          phrase.text.length,
          lessThanOrEqualTo(OverallMeditationConfig.kokoroMaxPhraseCharacters),
        );
      }
    });

    test('only the final piece of a split stretch carries its pause', () {
      // A phrase cut by the ceiling is mid-thought, so the boundary pause
      // belongs after the last part of it, not inside.
      final phrases = splitNarrationIntoPhrases(
        '${List.filled(30, 'steady breathing').join(', ')}. Now rest.',
        maxCharacters: 60,
      );
      final beforeSentenceEnd =
          phrases.takeWhile((p) => !p.text.endsWith('Now rest.')).toList();
      expect(beforeSentenceEnd.length, greaterThan(1));
      expect(beforeSentenceEnd.last.pause, sentencePause);
      for (final earlier
          in beforeSentenceEnd.take(beforeSentenceEnd.length - 1)) {
        expect(earlier.pause, phrasePause);
      }
    });
  });

  group('joining the audio', () {
    test('clips are laid end to end with silence between them', () {
      final joined = joinPhraseAudio(
        [
          Float32List.fromList([1, 1]),
          Float32List.fromList([2, 2]),
        ],
        [3, 0],
      );

      expect(joined.length, 2 + 3 + 2);
      expect(joined.sublist(0, 2), [1, 1]);
      // The gap is silence, not a repeat or a click.
      expect(joined.sublist(2, 5), [0, 0, 0]);
      expect(joined.sublist(5), [2, 2]);
    });

    test('a missing pause entry simply means no gap', () {
      final joined = joinPhraseAudio(
        [
          Float32List.fromList([1]),
          Float32List.fromList([2]),
        ],
        const [],
      );
      expect(joined, [1, 2]);
    });

    test('a single clip comes back unchanged', () {
      final joined = joinPhraseAudio(
        [
          Float32List.fromList([5, 6]),
        ],
        [0],
      );
      expect(joined, [5, 6]);
    });
  });
}
