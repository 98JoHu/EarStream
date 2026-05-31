import 'package:flutter/material.dart';
import 'drawer_page.dart';

class ProfilePage extends DrawerPage {
  const ProfilePage({super.key});

  @override
  String get label => "Profile";

  @override
  IconData get icon => Icons.person_outline;

  @override
  IconData get selectedIcon => Icons.person;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("Profile Page"),
    );
  }
}
