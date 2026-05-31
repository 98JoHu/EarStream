import 'package:flutter/material.dart';
import 'drawer_page.dart';

class ProfilePage extends StatefulWidget implements DrawerPage {
  const ProfilePage({super.key});

  @override
  String get label => "Profile";

  @override
  IconData get icon => Icons.person_outline;

  @override
  IconData get selectedIcon => Icons.person;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("Profile Page"),
    );
  }
}
