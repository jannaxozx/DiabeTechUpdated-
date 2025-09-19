import 'package:diabetechapp/Screens/log_in.dart';
import 'package:diabetechapp/Screens/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Screens/dashboard.dart';
import 'Screens/admin_dashboard.dart';
import 'firebase_options.dart';
import 'package:diabetechapp/Screens/landing_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DiabeTech',
      theme: ThemeData(primarySwatch: Colors.purple),
      home: const InitialScreen(),
    );
  }
}

class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  _InitialScreenState createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  User? user;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  /// First time app open → show onboarding
  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool("hasSeenOnboarding") ?? false;

    if (!hasSeenOnboarding) {
      await prefs.setBool("hasSeenOnboarding", true);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const OnboardScreen()),
      );
    } else {
      _checkUser();
    }
  }

  /// Check if user is logged in → redirect
  Future<void> _checkUser() async {
    user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .get();

        String role = 'user';
        if (userDoc.exists && userDoc.data()?['role'] != null) {
          role = userDoc['role'];
        }

        if (!mounted) return;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (role == 'admin') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AdminDashboard()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const Dashboard()),
            );
          }
        });
      } catch (e) {
        // Firestore failed → sign out for safety
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LandingPage()),
        );
      }
    } else {
      // No user logged in → go to landing page
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LandingPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
