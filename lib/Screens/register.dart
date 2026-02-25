import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:diabetechapp/Screens/dashboard.dart'; // unused import removed
import 'package:diabetechapp/Screens/log_in.dart';

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  bool _obscureText = true;
  bool _isLoading = false;
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _selectedDiabetesType;

  final List<String> _diabetesTypes = [
    "Mild",
    "Moderate",
    "Severe",
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateInputs() {
    if (_nameController.text.trim().isEmpty) {
      return "Please enter your full name";
    }
    if (_emailController.text.trim().isEmpty) {
      return "Please enter your email";
    }
    if (!_emailController.text.trim().contains('@')) {
      return "Please enter a valid email";
    }
    if (_passwordController.text.trim().length < 6) {
      return "Password must be at least 6 characters";
    }
    if (_selectedDiabetesType == null) {
      return "Please select your diabetes type";
    }
    return null;
  }

  Future<void> _registerUser() async {
    // Validate inputs first
    final validationError = _validateInputs();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }

    // Prevent multiple submissions
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      debugPrint("📝 Starting registration...");
      
      // 1. Create user account
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;

      if (user == null) {
        throw Exception("User creation failed");
      }

      debugPrint("✅ User created: ${user.uid}");

      // 2. Send email verification
      await user.sendEmailVerification();
      debugPrint("✅ Email verification sent to ${user.email}");

      // 3. Update display name
      await user.updateDisplayName(_nameController.text.trim());
      await user.reload();
      
      debugPrint("✅ Display name updated");

      // 4. Save user data to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'name': _nameController.text.trim(),
        'email': user.email,
        'role': 'user',
        'diabetesType': _selectedDiabetesType,
        'emailVerified': false, // Track verification status
        'createdAt': FieldValue.serverTimestamp(),
        'uid': user.uid,
      });

      debugPrint("✅ User data saved to Firestore");

      // 5. Sign out user so they can verify email first
      await FirebaseAuth.instance.signOut();
      debugPrint("✅ User signed out after registration");

      if (!mounted) return;

      // 5. Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Registration successful! Please check your email and verify before logging in."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );

      // 6. Small delay to show success message
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // 7. Navigate back to Login page and clear all previous routes
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false, // This removes all previous routes
      );

      debugPrint("✅ Navigated to Login Screen");
      
    } on FirebaseAuthException catch (e) {
      debugPrint("❌ Firebase Auth Error: ${e.code} - ${e.message}");
      
      String errorMessage;
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'The password is too weak';
          break;
        case 'email-already-in-use':
          errorMessage = 'An account already exists with this email';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address';
          break;
        case 'operation-not-allowed':
          errorMessage = 'Email/password accounts are not enabled';
          break;
        default:
          errorMessage = e.message ?? 'Registration failed';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      debugPrint("❌ Unexpected error: $e");
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Registration failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "DiabeTech",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background image
          SizedBox.expand(
            child: Image.asset(
              "assets/images/ground.png",
              fit: BoxFit.cover,
            ),
          ),

          // Form
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 100, 16, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo
                  SizedBox(
                    height: 150,
                    width: 150,
                    child: Image.asset("assets/images/DiabeTechLogo.png"),
                  ),
                  const SizedBox(height: 15),

                  const Text(
                    "Welcome",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Name input
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    child: TextField(
                      controller: _nameController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.name,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Color.fromRGBO(255, 255, 255, 0.9),
                        labelText: 'Full Name',
                        labelStyle: const TextStyle(color: Colors.black),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.person, color: Colors.grey),
                      ),
                    ),
                  ),

                  // Email input
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    child: TextField(
                      controller: _emailController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Color.fromRGBO(255, 255, 255, 0.9),
                        labelText: 'Email',
                        labelStyle: const TextStyle(color: Colors.black),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.email, color: Colors.grey),
                      ),
                    ),
                  ),

                  // Password input
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    child: TextFormField(
                      controller: _passwordController,
                      enabled: !_isLoading,
                      obscureText: _obscureText,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Color.fromRGBO(255, 255, 255, 0.9),
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: Colors.black),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.lock, color: Colors.grey),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText ? Icons.visibility_off : Icons.visibility,
                            color: Colors.black,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureText = !_obscureText;
                            });
                          },
                        ),
                      ),
                    ),
                  ),

                  // Diabetes type dropdown
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    child: DropdownButtonFormField<String>(
                      value: _selectedDiabetesType,
                      onChanged: _isLoading ? null : (value) {
                        setState(() {
                          _selectedDiabetesType = value;
                        });
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Color.fromRGBO(255, 255, 255, 0.9),
                        labelText: 'Select Diabetes Type',
                        labelStyle: const TextStyle(color: Colors.black),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.medical_services, color: Colors.grey),
                      ),
                      dropdownColor: Colors.white,
                      items: _diabetesTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(
                            type,
                            style: const TextStyle(color: Colors.black),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Register button with loading indicator
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: InkWell(
                      onTap: _isLoading ? null : _registerUser,
                      child: Container(
                        height: 55,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: _isLoading ? Colors.grey : const Color(0xFF42A546),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Text(
                                  "REGISTER",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Already have account?
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Already have an account? ",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                        ),
                      ),
                      InkWell(
                        onTap: _isLoading
                            ? null
                            : () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => const LoginScreen()),
                                );
                              },
                        child: Text(
                          "Login",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _isLoading ? Colors.grey : Colors.black,
                          ),
                        ),
                      ),
                    ],
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