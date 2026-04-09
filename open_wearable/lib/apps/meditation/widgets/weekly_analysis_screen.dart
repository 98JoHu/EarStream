import 'package:flutter/material.dart';
import '../model/mood_entry.dart';
import 'package:intl/intl.dart';

/// Weekly meditation analysis and mood tracking screen
class WeeklyAnalysisScreen extends StatefulWidget {
  const WeeklyAnalysisScreen({super.key});

  @override
  State<WeeklyAnalysisScreen> createState() => _WeeklyAnalysisScreenState();
}

class _WeeklyAnalysisScreenState extends State<WeeklyAnalysisScreen> {
  Map<String, dynamic>? _weeklySummary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final summary = await MoodHistory.getWeeklySummary();
    setState(() {
      _weeklySummary = summary;
      _isLoading = false;
    });
  }

  Future<void> _confirmClearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text(
          'This will permanently delete all meditation sessions and mood entries. This action cannot be undone.\n\nThis is useful for testing with new users.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _clearAllData();
    }
  }

  Future<void> _clearAllData() async {
    setState(() => _isLoading = true);
    
    try {
      await MoodHistory.clearAll();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All meditation data cleared'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing data: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Analysis'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear all data',
            onPressed: _confirmClearAllData,
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
            ),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _weeklySummary == null || _weeklySummary!['totalSessions'] == 0
                  ? _buildEmptyState()
                  : _buildAnalysisContent(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insights,
              size: 80,
              color: Colors.indigo.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Data Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Complete a meditation session and rate your mood to see your weekly insights here!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisContent() {
    final totalSessions = _weeklySummary!['totalSessions'] as int;
    final avgReduction = _weeklySummary!['averageStressReduction'] as double;
    final mostCommonMood = _weeklySummary!['mostCommonMood'] as MoodRating?;
    final avgDuration = _weeklySummary!['averageDuration'] as Duration;
    final entries = _weeklySummary!['entries'] as List<MoodEntry>;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80), // Extra bottom padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Your Week in Meditation',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Last 7 Days',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Summary Cards
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    icon: Icons.self_improvement,
                    label: 'Sessions',
                    value: '$totalSessions',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    icon: Icons.trending_down,
                    label: 'Avg Reduction',
                    value: '${avgReduction.toStringAsFixed(0)}%',
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    icon: Icons.timer,
                    label: 'Avg Duration',
                    value: '${avgDuration.inMinutes}m',
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMoodCard(mostCommonMood),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Daily Breakdown
            const Text(
              'Daily Breakdown',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 12),
            ...entries.reversed.map((entry) => _buildEntryCard(entry)),

            const SizedBox(height: 24),

            // Insights
            _buildInsights(entries, avgReduction, mostCommonMood),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodCard(MoodRating? mood) {
    if (mood == null) {
      return _buildSummaryCard(
        icon: Icons.sentiment_neutral,
        label: 'Most Common',
        value: '😐',
        color: Colors.grey,
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              _getMoodEmoji(mood),
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(height: 8),
            Text(
              _getMoodText(mood),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Most Common',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryCard(MoodEntry entry) {
    final time = DateFormat('h:mm a').format(entry.timestamp);
    final duration = '${entry.sessionDuration.inMinutes}m ${entry.sessionDuration.inSeconds % 60}s';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Date
            Container(
              width: 60,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('MMM').format(entry.timestamp),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  Text(
                    DateFormat('d').format(entry.timestamp),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        entry.moodEmoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        entry.moodText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$duration • ${entry.stressReduction.toStringAsFixed(0)}% reduction',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsights(List<MoodEntry> entries, double avgReduction, MoodRating? mostCommonMood) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  'Weekly Insights',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInsightItem(
              _getPerformanceInsight(avgReduction),
              Icons.trending_up,
              Colors.green,
            ),
            const SizedBox(height: 12),
            _buildInsightItem(
              _getMoodInsight(mostCommonMood),
              Icons.sentiment_satisfied_alt,
              Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildInsightItem(
              _getConsistencyInsight(entries.length),
              Icons.calendar_today,
              Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightItem(String text, IconData icon, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
      ],
    );
  }

  String _getPerformanceInsight(double avgReduction) {
    if (avgReduction >= 20) {
      return 'Excellent! Your meditations are reducing stress by ${avgReduction.toStringAsFixed(0)}% on average. Keep it up!';
    } else if (avgReduction >= 10) {
      return 'Great progress! You\'re seeing ${avgReduction.toStringAsFixed(0)}% stress reduction. Try longer sessions for even better results.';
    } else {
      return 'You\'re making progress with ${avgReduction.toStringAsFixed(0)}% reduction. Consistency is key - keep practicing!';
    }
  }

  String _getMoodInsight(MoodRating? mood) {
    if (mood == MoodRating.veryRelaxed || mood == MoodRating.relaxed) {
      return 'You\'re feeling relaxed after most sessions - meditation is working well for you!';
    } else if (mood == MoodRating.neutral) {
      return 'You\'re feeling neutral after sessions. Try adjusting the meditation length or environment sounds.';
    } else {
      return 'If you\'re still feeling stressed after sessions, try meditating when you\'re less overwhelmed, or extend session length.';
    }
  }

  String _getConsistencyInsight(int sessionCount) {
    if (sessionCount >= 5) {
      return 'Amazing consistency! ${sessionCount} sessions this week. Your mindfulness practice is strong.';
    } else if (sessionCount >= 3) {
      return 'Good job! ${sessionCount} sessions this week. Try to maintain this rhythm.';
    } else {
      return '${sessionCount} session${sessionCount == 1 ? '' : 's'} this week. Try to meditate more regularly for best results.';
    }
  }

  String _getMoodEmoji(MoodRating mood) {
    switch (mood) {
      case MoodRating.veryRelaxed:
        return '😌';
      case MoodRating.relaxed:
        return '😊';
      case MoodRating.neutral:
        return '😐';
      case MoodRating.stressed:
        return '😟';
    }
  }

  String _getMoodText(MoodRating mood) {
    switch (mood) {
      case MoodRating.veryRelaxed:
        return 'Very Relaxed';
      case MoodRating.relaxed:
        return 'Relaxed';
      case MoodRating.neutral:
        return 'Neutral';
      case MoodRating.stressed:
        return 'Stressed';
    }
  }
}


