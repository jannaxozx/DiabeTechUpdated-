import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
  final FirebaseAuth _auth = FirebaseAuth.instance;

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

  // ---------------- Facebook Sign-In ----------------
  Future<void> _signInWithFacebook() async {
    try {
      setState(() => _isLoading = true);

      // Use native flow on mobile to avoid insecure web login blocks
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
        loginBehavior: kIsWeb
            ? LoginBehavior.webOnly // requires https in the browser
            : LoginBehavior.nativeWithFallback,
      );

      if (result.status == LoginStatus.success) {
        final AccessToken accessToken = result.accessToken!;
        final facebookAuthCredential =
            FacebookAuthProvider.credential(accessToken.tokenString);
        final userCredential =
            await FirebaseAuth.instance.signInWithCredential(facebookAuthCredential);
        final user = userCredential.user;

        if (user != null) {
          // Try to enrich user data from Facebook
          Map<String, dynamic>? fbData;
          try {
            fbData = await FacebookAuth.instance.getUserData(
              fields: "email,name,picture.width(200).height(200)",
            );
          } catch (_) {}

          final userRef =
              FirebaseFirestore.instance.collection("users").doc(user.uid);
          var userDoc = await userRef.get();

          if (!userDoc.exists) {
            await userRef.set({
              "email": user.email,
              "name": (fbData?['name'] as String?) ?? user.displayName ?? "",
              "photoUrl": (fbData?['picture']?['data']?['url'] as String?) ?? user.photoURL ?? "",
              "role": "user",
              "createdAt": Timestamp.now(),
            });
            // Re-read after creation to get fresh data
            userDoc = await userRef.get();
          }

          final role =
              (userDoc.data()?['role'] ?? 'user').toString().toLowerCase();

          _showSuccessToast("Signed in as $role via Facebook");

          if (!mounted) return;
          if (role == "admin") {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AdminDashboard()),
              (route) => false,
            );
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const Dashboard()),
              (route) => false,
            );
          }
        }
      } else if (result.status == LoginStatus.cancelled) {
        _showInfoToast("Facebook login cancelled");
      } else {
        _showErrorToast("Facebook login failed: ${result.message}");
      }
    } catch (e) {
      if (e is FirebaseAuthException &&
          e.code == 'account-exists-with-different-credential') {
        final pendingEmail = e.email;
        final methods = pendingEmail != null
            ? await FirebaseAuth.instance.fetchSignInMethodsForEmail(pendingEmail)
            : <String>[];
        final hint = methods.isNotEmpty ? 'Use ${methods.first} to sign in.' : 'Try another method.';
        _showErrorToast('Account exists with different sign-in method. $hint');
      } else {
        _showErrorToast("Error during Facebook login: $e");
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSuccessToast(String message) {
    _showToast(message, const Color(0xFF2E7D32));
  }

  void _showErrorToast(String message) {
    _showToast(message, const Color(0xFFB00020));
  }

  void _showInfoToast(String message) {
    _showToast(message, const Color(0xFF1565C0));
  }

  void _showToast(String message, Color backgroundColor) {
  final overlay = Overlay.of(context);
    final OverlayEntry entry = OverlayEntry(
      builder: (context) {
        final size = MediaQuery.of(context).size;
        return Positioned(
          top: 20,
          right: 20,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(maxWidth: size.width * 0.6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 2)),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        );
      },
    );
  overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2)).then((_) {
      if (entry.mounted) entry.remove();
    });
  }

  void _showFacebookLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Continue with Facebook'),
          content: const Text('A secure Facebook dialog will open to complete sign-in.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _signInWithFacebook();
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  // ---------------- Facebook Button (polished UI) ----------------
  Widget _buildFacebookButton() {
    return InkWell(
      onTap: _showFacebookLoginDialog,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 50,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1877F2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: Image.asset("assets/images/Facebook1.png", fit: BoxFit.contain),
            ),
            const SizedBox(width: 10),
            const Text(
              "Continue with Facebook",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
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

                // Forgot Password
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
                              builder: (_) => const PasswordResetScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "Forgot Password?",
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black),
                        ),
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
                            : const Text(
                                "LOGIN",
                                style: TextStyle(
                                    fontSize: 16, color: Colors.white),
                              ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Row(
                    children: const [
                      Expanded(child: Divider(color: Colors.black, thickness: 2)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          "or continue with",
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.black, thickness: 2)),
                    ],
                  ),
                ),

                const SizedBox(height: 15),

                // Facebook Button (polished UI + modal)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: _buildFacebookButton(),
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
