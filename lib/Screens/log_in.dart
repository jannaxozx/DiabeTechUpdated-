import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;

  // ---------------- Login with Email + Role Check ----------------
  Future<void> _loginUser() async {
    setState(() => _isLoading = true);
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;
      if (user == null) throw Exception("User not found");

      // 🔑 Fetch role from Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      String role;
      if (userDoc.exists && userDoc.data() != null) {
        role = (userDoc.data() as Map<String, dynamic>)['role'] ?? "user";
      } else {
        // Default: normal user if no record exists
        role = "user";
        await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
          "email": user.email,
          "role": "user",
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Successful as $role")),
      );

      // 🔑 Redirect based on role
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
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Login failed")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ---------------- Google Sign-In with Role Check ----------------
  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      User? user = userCredential.user;
      if (user == null) throw Exception("Google Sign-In failed");

      DocumentReference userDoc =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      if (!(await userDoc.get()).exists) {
        await userDoc.set({
          'email': user.email,
          'role': 'user', // default role
        });
      }

      DocumentSnapshot snapshot = await userDoc.get();
      String role = (snapshot.data() as Map<String, dynamic>)['role'] ?? "user";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Signed in as $role")),
      );

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
        SnackBar(content: Text("Google Sign-In Failed: $e")),
      );
    }
  }

  // ---------------- Placeholder for Phone Sign-In ----------------
  Future<void> _signInWithPhone() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Phone Sign-In not implemented")),
    );
  }

  // ---------------- Social Button Widget ----------------
  Widget socialButton(String imagePath, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 50,
        width: 50,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Image.asset(imagePath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          SizedBox.expand(
            child: Image.asset(
              "assets/images/ground.png",
              fit: BoxFit.cover,
            ),
          ),

          // Form
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
                const SizedBox(height: 10),
                const Text("Welcome Back",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.black)),
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

                // Forgot password
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const PasswordResetScreen()),
                          );
                        },
                        child: const Text("Forgot Password?",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black)),
                      ),
                    ),
                  ],
                ),

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
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text("LOGIN",
                                style: TextStyle(
                                    fontSize: 16, color: Colors.white)),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // OR continue with
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Row(
                    children: const [
                      Expanded(
                          child: Divider(color: Colors.black, thickness: 2)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text("or continue with",
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                          child: Divider(color: Colors.black, thickness: 2)),
                    ],
                  ),
                ),

                const SizedBox(height: 15),

                // Social buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    socialButton("assets/images/GoogleLogo.png", _signInWithGoogle),
                    const SizedBox(width: 20),
                    socialButton("assets/images/PhoneLogo.png", _signInWithPhone),
                  ],
                ),

                const SizedBox(height: 20),

                // Not a member? Register Now
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
                          MaterialPageRoute(
                              builder: (context) => const Register()),
                        );
                      },
                      child: const Text("Register Now",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
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
