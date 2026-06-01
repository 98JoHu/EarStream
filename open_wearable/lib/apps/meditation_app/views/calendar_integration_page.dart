import 'package:flutter/material.dart';
import 'drawer_page.dart';
import '../widgets/status_field.dart';
import '../widgets/secret_field.dart';

class CalendarIntegrationPage extends StatefulWidget implements DrawerPage {
  const CalendarIntegrationPage({super.key});

  @override
  String get label => "Outlook Calendar Integration";

  @override
  IconData get icon => Icons.calendar_today_outlined;

  @override
  IconData get selectedIcon => Icons.calendar_today;

  @override
  State<CalendarIntegrationPage> createState() =>
      _CalendarIntegrationPageState();
}

class _CalendarIntegrationPageState extends State<CalendarIntegrationPage> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Outlook suppression token',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'EarStream polls Microsoft Graph to avoid firing stress prompts during meetings. Tokens are stored only on this device.',
                style: TextStyle(color: Colors.grey[700], height: 1.4),
              ),
              const SizedBox(height: 24),
              StatusField(
                neighbourWidget: const SecretField(
                  title: "Suppression Token",
                  description: "Enter your Outlook suppression token here.",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
