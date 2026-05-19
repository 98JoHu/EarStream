// ignore_for_file: require_trailing_commas

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/storage/saved_meditation_transcripts.dart';
import '../shared/earstream_style.dart';

/// Screen that lists all meditation transcripts saved from simulated-stress
/// (Biosignal-Adaptive demo) sessions.
class SavedMeditationsScreen extends StatefulWidget {
  const SavedMeditationsScreen({super.key});

  @override
  State<SavedMeditationsScreen> createState() => _SavedMeditationsScreenState();
}

class _SavedMeditationsScreenState extends State<SavedMeditationsScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await SavedMeditationTranscripts.instance.load();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _delete(String id) async {
    await SavedMeditationTranscripts.instance.deleteTranscript(id);
    if (mounted) setState(() {});
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Saved Meditations?'),
        content: const Text(
          'This will permanently delete all saved meditation transcripts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SavedMeditationTranscripts.instance.clearAll();
      if (mounted) setState(() {});
    }
  }

  void _openDetail(SavedMeditationTranscript transcript) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MeditationDetailScreen(transcript: transcript),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transcripts = SavedMeditationTranscripts.instance.transcripts;

    return Scaffold(
      appBar: EarStreamStyle.appBar(
        context,
        title: 'Saved Meditations',
        actions: transcripts.isEmpty
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Clear all',
                  onPressed: _confirmClearAll,
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : transcripts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.library_books_outlined,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withOpacity(0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No saved meditations yet',
                          style: EarStreamStyle.pageHeadline(context),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Meditations generated during a Simulated Stress session are automatically saved here.',
                          style: EarStreamStyle.supportingText(context),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 16),
                  itemCount: transcripts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final t = transcripts[index];
                    final dateLabel =
                        DateFormat('MMM d, yyyy – HH:mm').format(t.timestamp);
                    final preview = t.segments.isNotEmpty
                        ? t.segments.first
                        : '';
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.self_improvement_outlined),
                        title: Text(
                          dateLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${t.segments.length} segment${t.segments.length == 1 ? '' : 's'}',
                              style: EarStreamStyle.labelText(context),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20),
                              tooltip: 'Delete',
                              onPressed: () => _delete(t.id),
                            ),
                          ],
                        ),
                        onTap: () => _openDetail(t),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Detail view for a single saved meditation transcript.
class _MeditationDetailScreen extends StatelessWidget {
  final SavedMeditationTranscript transcript;

  const _MeditationDetailScreen({required this.transcript});

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMMM d, yyyy – HH:mm')
        .format(transcript.timestamp);

    return Scaffold(
      appBar: EarStreamStyle.appBar(context, title: dateLabel),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: transcript.segments.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (index == 0) ...[
                  Text(
                    'Welcome',
                    style: EarStreamStyle.sectionTitle(context),
                  ),
                  const SizedBox(height: 6),
                ] else if (index == transcript.segments.length - 1) ...[
                  Text(
                    'Closing',
                    style: EarStreamStyle.sectionTitle(context),
                  ),
                  const SizedBox(height: 6),
                ] else ...[
                  Text(
                    'Segment $index',
                    style: EarStreamStyle.sectionTitle(context),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  transcript.segments[index],
                  style: EarStreamStyle.supportingText(context),
                ),
                if (index < transcript.segments.length - 1)
                  const Divider(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}
