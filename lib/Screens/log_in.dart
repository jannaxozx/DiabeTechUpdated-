import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'register.dart';
import 'ForgotPasswordScreen.dart';
import 'dashboard.dart';
import 'admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureText = true;
  bool _isLoading = false;
  bool _rememberMe = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  // ---------------- Email Login ----------------
  Future<void> _loginUser() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;
      if (user == null) throw Exception("User not found");

      final userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      // Ensure user has role
      if (!userDoc.exists) {
        await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
          "email": user.email,
          "role": "user",
          "createdAt": Timestamp.now(),
        });
      }

      String role =
          (userDoc.data()?['role'] ?? 'user').toString().toLowerCase();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Successful as $role")),
      );

      // Save remember me preference after successful login
      await _saveRemembered();

      // Navigate based on role
      if (role == "admin") {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ---------------- Remember me helpers ----------------
  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = prefs.getBool('rememberMe') ?? false;
    if (remembered) {
      setState(() {
        _rememberMe = true;
        _emailController.text = prefs.getString('savedEmail') ?? '';
        _passwordController.text = prefs.getString('savedPassword') ?? '';
      });
    }
  }

  Future<void> _saveRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool('rememberMe', true);
      await prefs.setString('savedEmail', _emailController.text.trim());
      await prefs.setString('savedPassword', _passwordController.text);
    } else {
      await prefs.remove('rememberMe');
      await prefs.remove('savedEmail');
      await prefs.remove('savedPassword');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          SizedBox.expand(
            child: Image.asset("assets/images/ground.png", fit: BoxFit.cover),
          ),

          // Login form
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 60),
                Center(
                  child: SizedBox(
                    height: 150,
                    width: 150,
                    child: Image.asset("assets/images/DiabeTechLogo.png"),
                  ),
                ),
                const SizedBox(height: 20),

                // Email
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      labelText: 'Email',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),

                // Password
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: TextFormField(
                    controller: _passwordController,
                    obscureText: _obscureText,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      labelText: 'Password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureText
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.black,
                        ),
                        onPressed: () =>
                            setState(() => _obscureText = !_obscureText),
                      ),
                    ),
                  ),
                ),

                // Remember me checkbox and Forgot Password
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left side - Remember Me
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _rememberMe,
                          onChanged: (val) =>
                              setState(() => _rememberMe = val ?? false),
                          title: const Text('Remember me'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    ),
                    
                    // Right side - Forgot Password
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PasswordResetScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "Forgot Password?",
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2C6E49),
                              decoration: TextDecoration.underline,
                              decorationColor: Color(0xFF2C6E49),
                              decorationThickness: 2.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Login button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: InkWell(
                    onTap: _isLoading ? null : _loginUser,
                    child: Container(
                      height: 55,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(66, 173, 70, 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text(
                                "LOGIN",
                                style: TextStyle(
                                    fontSize: 16, color: Colors.white),
                              ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: Colors.grey.shade300,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          "OR",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: Colors.grey.shade300,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Register link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Not a member?",
                        style: TextStyle(fontSize: 15, color: Colors.black)),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const Register()),
                        );
                      },
                      child: const Text(
                        "Register Now",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }
}