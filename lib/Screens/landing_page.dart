import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetechapp/Screens/log_in.dart';       // Login Screen
import 'package:diabetechapp/Screens/dashboard.dart';    // User dashboard
import 'package:diabetechapp/Screens/admin_dashboard.dart'; // Admin dashboard

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _checkUser();
  }

  Future<void> _checkUser() async {
    User? user = _auth.currentUser;

    if (user != null) {
      try {
        // Fetch user document
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!userDoc.exists) {
          // Default to user if no doc exists
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const Dashboard()),
          );
          return;
        }

        // Get role safely
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
        String role = data['role'] ?? 'user';

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
      } catch (e) {
        debugPrint("Error checking user: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.asset(
            "assets/images/landing.png",
            fit: BoxFit.cover,
          ),

          // Dark overlay
          Container(color: Colors.black.withOpacity(0.3)),

          // Content
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Image.asset(
                    "assets/images/DiabeTechLogo.png",
                    height: 120,
                  ),
                  const SizedBox(height: 40),

                  const Text(
                    "Welcome to DiabeTech",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Single Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Login",
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
