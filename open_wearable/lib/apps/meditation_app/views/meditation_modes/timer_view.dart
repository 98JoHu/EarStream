import 'dart:async';
import 'package:flutter/material.dart';
import 'package:open_wearable/apps/meditation_app/model/user_account.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../model/measurement.dart';
import '../../model/meditation.dart' show ScheduledMeditation;
import '../../widgets/meditation_tile.dart';

class TimerView extends StatefulWidget {
  const TimerView({super.key});

  @override
  State<TimerView> createState() => _TimerViewState();
}

class _TimerViewState extends State<TimerView> {
  final List<ScheduledMeditation> _scheduledMeditations = [];
  Timer? _timer;
  final ValueNotifier<ScheduledMeditation?> _currentMeditation =
      ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkMeditations();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_currentMeditation.value != null) {
      _currentMeditation.value!.stop();
    }
    super.dispose();
  }

  void _checkMeditations() {
    final dueMeditations = _scheduledMeditations
        .where((meditation) => meditation.isDue())
        .toList();
    if (dueMeditations.isEmpty) return;

    for (final meditation in dueMeditations) {
      setState(() {
        _scheduledMeditations.remove(meditation);
        _currentMeditation.value = meditation;
      });
      _currentMeditation.value!.start();
    }
  }

  void _scheduleMeditation(UserAccount userAccount, DateTime time) {
    ScheduledMeditation scheduledMeditation = ScheduledMeditation(
      userAccount: userAccount,
      scheduledTime: time,
    );
    setState(() {
      _scheduledMeditations.add(scheduledMeditation);
      _scheduledMeditations
          .sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    });
  }

  @override
  Widget build(BuildContext context) {
    // TODO: access user account a different way
    final measurement = context.read<Measurement>();
    final userAccount = measurement.userAccount;

    return ValueListenableBuilder<ScheduledMeditation?>(
      valueListenable: _currentMeditation,
      builder: (context, currentMeditation, child) {
        if (currentMeditation != null) {
          return MeditationTile(meditation: _currentMeditation);
        } else {
          return SingleChildScrollView(
            child: Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Timed Meditation',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
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
                            onPressed: () {
                              ScheduledMeditation scheduledMeditation =
                                  ScheduledMeditation(
                                userAccount: userAccount,
                                scheduledTime: DateTime.now(),
                              );
                              setState(() {
                                _currentMeditation.value = scheduledMeditation;
                              });
                              scheduledMeditation.start();
                            },
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
                              onPressed: () => {
                                _scheduleMeditation(
                                  userAccount,
                                  DateTime.now().add(Duration(minutes: 5)),
                                ),
                              },
                              child: const Text('After 5 min'),
                            ),
                            OutlinedButton(
                              onPressed: () => {
                                _scheduleMeditation(
                                  userAccount,
                                  DateTime.now().add(Duration(minutes: 10)),
                                ),
                              },
                              child: const Text('After 10 min'),
                            ),
                            OutlinedButton(
                              onPressed: () => {
                                _scheduleMeditation(
                                  userAccount,
                                  DateTime.now().add(Duration(minutes: 30)),
                                ),
                              },
                              child: const Text('After 30 min'),
                            ),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (!mounted) return;
                                if (picked != null) {
                                  final now = DateTime.now();
                                  DateTime scheduledDateTime = DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                  if (scheduledDateTime.isBefore(now)) {
                                    scheduledDateTime = scheduledDateTime
                                        .add(Duration(days: 1));
                                  }
                                  _scheduleMeditation(
                                    userAccount,
                                    scheduledDateTime,
                                  );
                                }
                              },
                              icon: const Icon(Icons.schedule),
                              label: const Text('Pick Time'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_scheduledMeditations.isNotEmpty)
                  // TODO: Extract widget
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'Scheduled Meditations',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _scheduledMeditations.length,
                            itemBuilder: (context, index) {
                              final meditation = _scheduledMeditations[index];
                              return ListTile(
                                title: Text(
                                  'Scheduled at ${DateFormat('MM/dd/yyyy hh:mm').format(meditation.scheduledTime)}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.cancel),
                                  onPressed: () {
                                    setState(() {
                                      _scheduledMeditations.removeAt(index);
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
      },
    );
  }
}
