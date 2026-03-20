import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// Screens
import 'Screens/landing_page.dart';
import 'Screens/onboarding.dart';
import 'Screens/dashboard.dart';
import 'Screens/admin_dashboard.dart';
import 'Screens/admin_food_rules_screen.dart';
import 'Screens/admin_food_detail_screen.dart';

import 'supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await SupabaseConfig.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiabeTech',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.purple,
      ),
      home: const InitialScreen(),
    );
  }
}

class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  State<InitialScreen> createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  @override
  void initState() {
    super.initState();
    _startAppFlow();
  }

  Future<void> _startAppFlow() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

    if (!hasSeenOnboarding) {
      await prefs.setBool('hasSeenOnboarding', true);
      if (!mounted) return;
      _navigate(const OnboardScreen());
      return;
    }

    _checkAuthAndRole();
  }

  Future<void> _checkAuthAndRole() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;
      _navigate(const LandingPage());
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final role = snapshot.data()?['role'] ?? 'user';

      if (!mounted) return;

      if (role == 'admin') {
        _navigate(const AdminDashboard());
      } else {
        _navigate(const Dashboard());
      }
    } catch (e) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      _navigate(const LandingPage());
    }
  }

  void _navigate(Widget page) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}