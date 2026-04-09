import 'package:flutter/material.dart';

class SnoozeDialog extends StatelessWidget {
  final VoidCallback onSnooze10Min;
  final VoidCallback onSnooze30Min;
  final VoidCallback onSnooze1Hour;
  final VoidCallback onSnoozeToday;

  const SnoozeDialog({
    Key? key,
    required this.onSnooze10Min,
    required this.onSnooze30Min,
    required this.onSnooze1Hour,
    required this.onSnoozeToday,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text(
        'Remind me later',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1F2937),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'When would you like to be reminded?',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 20),
          _SnoozeButton(
            label: 'In 10 minutes',
            icon: Icons.access_time,
            onTap: () {
              Navigator.of(context).pop();
              onSnooze10Min();
            },
          ),
          const SizedBox(height: 12),
          _SnoozeButton(
            label: 'In 30 minutes',
            icon: Icons.schedule,
            onTap: () {
              Navigator.of(context).pop();
              onSnooze30Min();
            },
          ),
          const SizedBox(height: 12),
          _SnoozeButton(
            label: 'In 1 hour',
            icon: Icons.timer,
            onTap: () {
              Navigator.of(context).pop();
              onSnooze1Hour();
            },
          ),
          const SizedBox(height: 12),
          _SnoozeButton(
            label: 'Don\'t ask today',
            icon: Icons.calendar_today,
            onTap: () {
              Navigator.of(context).pop();
              onSnoozeToday();
            },
          ),
        ],
      ),
    );
  }
}

class _SnoozeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SnoozeButton({
    Key? key,
    required this.label,
    required this.icon,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFF6366F1),
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
