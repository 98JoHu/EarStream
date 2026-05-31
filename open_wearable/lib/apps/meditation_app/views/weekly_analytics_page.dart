import 'package:flutter/material.dart';
import 'drawer_page.dart';

class WeeklyAnalyticsPage extends DrawerPage {
  const WeeklyAnalyticsPage({super.key});

  @override
  String get label => "Weekly Analytics";

  @override
  IconData get icon => Icons.insights_outlined;

  @override
  IconData get selectedIcon => Icons.insights;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("Weekly Analytics"),
    );
  }
}
