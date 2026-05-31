import 'package:flutter/material.dart';
import 'drawer_page.dart';

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
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("Outlook Calendar Integration"),
    );
  }
}
