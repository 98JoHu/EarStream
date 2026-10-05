import 'package:flutter/foundation.dart';

import '../configs/overall_config.dart';

/// A stretch of narration to synthesize, and the pause that should follow it.
@immutable
class NarrationPhrase {
  final String text;
  final Duration pause;

  const NarrationPhrase({required this.text, required this.pause});

  @override
  String toString() =>
      'NarrationPhrase(${pause.inMilliseconds}ms after: $text)';
}

/// Breaks narration into the pieces Kokoro is asked to speak, and decides how
/// long a pause belongs after each.
///
/// sherpa-onnx splits text itself, synthesizes each piece separately, and then
/// concatenates the audio with **no gap at all**. Its silence scaling runs on
/// each piece *before* that join, so it only ever stretches pauses that sit
/// inside one piece — a comma, say — and never the pause at the boundary
/// between two. The result is backwards: commas get stretched while sentence
/// endings run straight into the next sentence.
///
/// Deciding the pieces here means the pause at every boundary is ours to set:
/// a short one at an ellipsis, a longer one at a sentence ending.
///
/// It also keeps each piece short. Kokoro's style table has one row per token
/// length, and sherpa-onnx does not clamp the lookup — a piece longer than the
/// table calls `SHERPA_ONNX_EXIT(-1)` and takes the process down. Generated
/// segments reach 650 characters in a single sentence, so an explicit ceiling
/// is what keeps that unreachable.
List<NarrationPhrase> splitNarrationIntoPhrases(
  String text, {
  Duration phrasePause = OverallMeditationConfig.kokoroPhrasePause,
  Duration sentencePause = OverallMeditationConfig.kokoroSentencePause,
  int maxCharacters = OverallMeditationConfig.kokoroMaxPhraseCharacters,
}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];

  final phrases = <NarrationPhrase>[];
  final buffer = StringBuffer();

  void flush(Duration pause) {
    final piece = buffer.toString().trim();
    buffer.clear();
    if (piece.isEmpty) return;
    // Punctuation on its own is nothing to speak; the generator does write a
    // stray "... ..." now and then. Its pause still belongs in the narration,
    // so it is added to the phrase before it rather than handed to the engine.
    if (!_speakable.hasMatch(piece)) {
      if (phrases.isNotEmpty) {
        phrases[phrases.length - 1] = NarrationPhrase(
          text: phrases.last.text,
          pause: phrases.last.pause + pause,
        );
      }
      return;
    }
    for (final part in _capLength(piece, maxCharacters)) {
      phrases.add(NarrationPhrase(text: part, pause: phrasePause));
    }
    // Only the final part of a flushed stretch carries that boundary's pause;
    // anything the ceiling split off is mid-thought.
    phrases[phrases.length - 1] =
        NarrationPhrase(text: phrases.last.text, pause: pause);
  }

  for (var i = 0; i < normalized.length; i++) {
    final char = normalized[i];
    buffer.write(char);
    if (char != '.' && char != '!' && char != '?') continue;

    // Consume a run of terminators together, so "..." is one boundary rather
    // than three and "?!" does not split in the middle.
    var end = i;
    while (end + 1 < normalized.length &&
        const ['.', '!', '?'].contains(normalized[end + 1])) {
      end++;
      buffer.write(normalized[end]);
    }
    final isEllipsis = end > i && normalized[i] == '.';
    i = end;

    // A terminator mid-word (a decimal, an abbreviation) is not a boundary.
    final next = i + 1 < normalized.length ? normalized[i + 1] : ' ';
    if (next != ' ') continue;

    flush(isEllipsis ? phrasePause : sentencePause);
    i++; // skip the separating space
  }

  flush(Duration.zero);

  // Whatever the text ended on, no pause belongs after the last phrase: it
  // would just be dead air at the end of the narration.
  if (phrases.isNotEmpty) {
    phrases[phrases.length - 1] =
        NarrationPhrase(text: phrases.last.text, pause: Duration.zero);
  }
  return phrases;
}

/// Whether a piece holds anything the voice can actually pronounce.
final RegExp _speakable = RegExp(r'[A-Za-z0-9]');

/// Splits a phrase that is still too long, preferring commas, then words.
List<String> _capLength(String phrase, int maxCharacters) {
  if (phrase.length <= maxCharacters) return [phrase];

  final parts = <String>[];
  final buffer = StringBuffer();

  void take(String unit) {
    final candidate = buffer.isEmpty ? unit : '${buffer.toString()} $unit';
    if (candidate.trim().length <= maxCharacters) {
      buffer
        ..clear()
        ..write(candidate.trim());
      return;
    }
    if (buffer.isNotEmpty) {
      parts.add(buffer.toString());
      buffer.clear();
    }
    if (unit.length <= maxCharacters) {
      buffer.write(unit);
      return;
    }
    // A single run longer than the ceiling: cut it on whitespace-free bounds.
    for (var at = 0; at < unit.length; at += maxCharacters) {
      final slice = unit.substring(
        at,
        at + maxCharacters > unit.length ? unit.length : at + maxCharacters,
      );
      parts.add(slice);
    }
  }

  for (final clause in phrase.split(',')) {
    final trimmed = clause.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.length <= maxCharacters) {
      take(trimmed);
      continue;
    }
    for (final word in trimmed.split(' ')) {
      if (word.isNotEmpty) take(word);
    }
  }

  if (buffer.isNotEmpty) parts.add(buffer.toString());
  return parts.isEmpty ? [phrase] : parts;
}

/// Lays the synthesized clips end to end with the requested pauses between.
///
/// [pauseSamples] holds the silence to insert after the clip at the same index.
/// A `Float32List` starts zeroed, so the gaps need no filling.
Float32List joinPhraseAudio(
  List<Float32List> clips,
  List<int> pauseSamples,
) {
  var total = 0;
  for (var i = 0; i < clips.length; i++) {
    total += clips[i].length;
    if (i < pauseSamples.length) total += pauseSamples[i];
  }

  final joined = Float32List(total);
  var at = 0;
  for (var i = 0; i < clips.length; i++) {
    joined.setRange(at, at + clips[i].length, clips[i]);
    at += clips[i].length + (i < pauseSamples.length ? pauseSamples[i] : 0);
  }
  return joined;
}
