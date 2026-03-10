import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetechapp/Screens/log_in.dart';

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  bool _obscureText = true;
  bool _isLoading   = false;

  final TextEditingController _nameController     = TextEditingController();
  final TextEditingController _emailController    = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _heightController   = TextEditingController();
  final TextEditingController _weightController   = TextEditingController();

  String? _selectedDiabetesType;
  String? _selectedActivityLevel;

  final List<String> _diabetesTypes = ['Mild', 'Severe'];

  final List<Map<String, dynamic>> _activityLevels = [
    {
      'value':    'Sedentary',
      'label':    'Sedentary',
      'icon':     Icons.weekend,
      'color':    const Color(0xFF9E9E9E),
      'desc':     'Little or no physical activity. Mostly sitting or lying down throughout the day.',
      'examples': '🛋️ Resting  •  📺 Watching TV  •  💻 Desk work with no movement',
    },
    {
      'value':    'Light',
      'label':    'Light',
      'icon':     Icons.directions_walk,
      'color':    const Color(0xFF42A546),
      'desc':     'Minimal movement with light physical tasks during the day.',
      'examples': '🏢 Office work  •  🚗 Driving  •  🧹 Light house chores',
    },
    {
      'value':    'Very Active',
      'label':    'Very Active',
      'icon':     Icons.directions_run,
      'color':    const Color(0xFFE53935),
      'desc':     'Extensive and rapid movements with high physical demands all day.',
      'examples': '🏃 Running  •  🏗️ Heavy labor  •  📦 Carrying heavy objects extensively',
    },
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  String? _validateInputs() {
    if (_nameController.text.trim().isEmpty)
      return 'Please enter your full name';
    if (_emailController.text.trim().isEmpty)
      return 'Please enter your email';
    if (!_emailController.text.trim().contains('@'))
      return 'Please enter a valid email';
    if (_passwordController.text.trim().length < 6)
      return 'Password must be at least 6 characters';
    if (_selectedDiabetesType == null)
      return 'Please select your diabetes type';
    if (_heightController.text.trim().isEmpty)
      return 'Please enter your height';
    if (_weightController.text.trim().isEmpty)
      return 'Please enter your weight';
    if (_selectedActivityLevel == null)
      return 'Please select your activity level';
    return null;
  }

  // ── Step 1: Validate → show disclaimer → then register ───────────────
  Future<void> _onRegisterTapped() async {
    // Validate first so the user fixes errors BEFORE seeing the disclaimer
    final validationError = _validateInputs();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }
    final agreed = await _showDisclaimerDialog();
    if (agreed == true) _registerUser();
  }

  // ── Disclaimer / notice dialog ────────────────────────────────────────
  Future<bool?> _showDisclaimerDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool isChecked = false;
        return StatefulBuilder(
          builder: (ctx, setS) => Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 36),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // Icon
                  Container(
                    width: 66, height: 66,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C6E49).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.health_and_safety_rounded,
                        color: Color(0xFF2C6E49), size: 36),
                  ),
                  const SizedBox(height: 12),

                  // Title
                  const Text(
                    'Before You Continue',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Please read and agree to the disclaimer\nbefore creating your DiabeTech account.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // Scrollable terms box
                  Container(
                    height: 215,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: const [
                            Icon(Icons.article_outlined,
                                size: 15, color: Color(0xFF2C6E49)),
                            SizedBox(width: 6),
                            Text('Terms & Disclaimer',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF2C6E49))),
                          ]),
                          const Divider(height: 14),

                          _termSection(
                            number: '1',
                            title: 'For Informational Purposes Only',
                            body:
                                'DiabeTech helps you track and monitor food intake related to '
                                'diabetes. All content provided is for general informational '
                                'purposes only and does NOT replace professional medical advice, '
                                'diagnosis, or treatment.',
                          ),
                          _termSection(
                            number: '2',
                            title: 'Your Personal Responsibility',
                            body:
                                'By creating an account, you fully acknowledge that any decision '
                                'or action you take based on information in this app is entirely '
                                'YOUR OWN RESPONSIBILITY. DiabeTech and its developers shall '
                                'NOT be held liable for any health outcomes, complications, or '
                                'consequences arising from your use of this application.',
                            highlight: true,
                          ),
                          _termSection(
                            number: '3',
                            title: 'Consult a Medical Professional',
                            body:
                                'Always consult your doctor, dietitian, or a qualified healthcare '
                                'provider before making changes to your diet, medication, or '
                                'lifestyle. Do not make medical decisions based solely on this app.',
                          ),
                          _termSection(
                            number: '4',
                            title: 'Data Privacy',
                            body:
                                'Your personal health data is stored securely. '
                                'We do not share your information with third parties '
                                'without your consent.',
                          ),

                          // Emergency warning
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: const [
                                Text('⚠️ ',
                                    style: TextStyle(fontSize: 13)),
                                Expanded(
                                  child: Text(
                                    'In a medical emergency, contact local emergency services '
                                    'immediately. Do NOT rely on this app in emergencies.',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600,
                                        height: 1.45),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Checkbox — must tick to enable I Agree
                  GestureDetector(
                    onTap: () => setS(() => isChecked = !isChecked),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: isChecked
                                ? const Color(0xFF2C6E49)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isChecked
                                  ? const Color(0xFF2C6E49)
                                  : Colors.grey.shade400,
                              width: 2,
                            ),
                          ),
                          child: isChecked
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 14)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'I have read and understood the Terms & Disclaimer. '
                            'I accept that I am fully responsible for my own '
                            'actions and decisions while using this app.',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.black87,
                                height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Action buttons
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 13),
                          side: BorderSide(
                              color: Colors.grey.shade400),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel',
                            style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isChecked
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF2C6E49)
                                        .withOpacity(0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  )
                                ]
                              : [],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isChecked
                                ? const Color(0xFF2C6E49)
                                : Colors.grey.shade300,
                            padding: const EdgeInsets.symmetric(
                                vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: isChecked
                              ? () => Navigator.pop(ctx, true)
                              : null,
                          child: Text(
                            'I Agree ✓',
                            style: TextStyle(
                                color: isChecked
                                    ? Colors.white
                                    : Colors.grey.shade500,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Helper: numbered term section ─────────────────────────────────────
  Widget _termSection({
    required String number,
    required String title,
    required String body,
    bool highlight = false,
  }) {
    final color = highlight ? Colors.orange.shade800 : const Color(0xFF2C6E49);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                color: highlight
                    ? Colors.orange.shade100
                    : const Color(0xFF2C6E49).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(number,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: color)),
            ),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: Text(body,
                style: TextStyle(
                    fontSize: 11,
                    color: highlight
                        ? Colors.orange.shade900
                        : Colors.black87,
                    height: 1.5,
                    fontWeight: highlight
                        ? FontWeight.w500
                        : FontWeight.normal)),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Actual Firebase registration (called after agreement) ──────
  Future<void> _registerUser() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      debugPrint('📝 Starting registration...');

      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email:    _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;
      if (user == null) throw Exception('User creation failed');
      debugPrint('✅ User created: ${user.uid}');

      await user.sendEmailVerification();
      await user.updateDisplayName(_nameController.text.trim());
      await user.reload();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'name':          _nameController.text.trim(),
        'email':         user.email,
        'role':          'user',
        'diabetesType':  _selectedDiabetesType,
        'height':        double.tryParse(_heightController.text.trim()) ?? 0.0,
        'weight':        double.tryParse(_weightController.text.trim()) ?? 0.0,
        'activityLevel': _selectedActivityLevel,
        'emailVerified': false,
        'createdAt':     FieldValue.serverTimestamp(),
        'uid':           user.uid,
      });

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '✅ Registration successful! Please verify your email before logging in.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Firebase Auth Error: ${e.code}');
      String msg;
      switch (e.code) {
        case 'weak-password':
          msg = 'The password is too weak'; break;
        case 'email-already-in-use':
          msg = 'An account already exists with this email'; break;
        case 'invalid-email':
          msg = 'Invalid email address'; break;
        default:
          msg = e.message ?? 'Registration failed';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (e) {
      debugPrint('❌ Unexpected error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Registration failed: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Activity level selector bottom sheet ─────────────────────────────
  void _showActivityPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 16),
            const Text('Select Activity Level',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Choose the level that best describes your daily routine',
              style: TextStyle(
                  color: Colors.grey.shade600, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ..._activityLevels.map((level) {
              final isSelected =
                  _selectedActivityLevel == level['value'];
              final color = level['color'] as Color;
              return GestureDetector(
                onTap: () {
                  setState(
                      () => _selectedActivityLevel = level['value']);
                  Navigator.pop(ctx);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withOpacity(0.1)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          isSelected ? color : Colors.grey.shade200,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(level['icon'] as IconData,
                          color: color, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(level['label'] as String,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isSelected
                                        ? color
                                        : Colors.black87)),
                            if (isSelected) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_circle,
                                  color: color, size: 16),
                            ],
                          ]),
                          const SizedBox(height: 3),
                          Text(level['desc'] as String,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  height: 1.3)),
                          const SizedBox(height: 4),
                          Text(level['examples'] as String,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: color.withOpacity(0.85),
                                  fontStyle: FontStyle.italic,
                                  height: 1.4)),
                        ],
                      ),
                    ),
                  ]),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedActivity = _selectedActivityLevel != null
        ? _activityLevels.firstWhere(
            (a) => a['value'] == _selectedActivityLevel)
        : null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'DiabeTech',
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          // Background
          SizedBox.expand(
            child: Image.asset('assets/images/ground.png',
                fit: BoxFit.cover),
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
                    height: 150, width: 150,
                    child: Image.asset(
                        'assets/images/DiabeTechLogo.png'),
                  ),
                  const SizedBox(height: 15),

                  const Text('Welcome',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.black)),
                  const SizedBox(height: 25),

                  // Full Name
                  _inputField(
                    controller: _nameController,
                    label: 'Full Name',
                    icon: Icons.person,
                    keyboardType: TextInputType.name,
                  ),

                  // Email
                  _inputField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                  ),

                  // Password
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 10),
                    child: TextFormField(
                      controller: _passwordController,
                      enabled: !_isLoading,
                      obscureText: _obscureText,
                      style: const TextStyle(color: Colors.black),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor:
                            const Color.fromRGBO(255, 255, 255, 0.9),
                        labelText: 'Password',
                        labelStyle:
                            const TextStyle(color: Colors.black),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.lock,
                            color: Colors.grey),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.black,
                          ),
                          onPressed: () => setState(
                              () => _obscureText = !_obscureText),
                        ),
                      ),
                    ),
                  ),

                  // Diabetes Type
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 10),
                    child: DropdownButtonFormField<String>(
                      value: _selectedDiabetesType,
                      onChanged: _isLoading
                          ? null
                          : (v) => setState(
                              () => _selectedDiabetesType = v),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor:
                            const Color.fromRGBO(255, 255, 255, 0.9),
                        labelText: 'Select Diabetes Type',
                        labelStyle:
                            const TextStyle(color: Colors.black),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.medical_services,
                            color: Colors.grey),
                      ),
                      dropdownColor: Colors.white,
                      items: _diabetesTypes
                          .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t,
                                  style: const TextStyle(
                                      color: Colors.black))))
                          .toList(),
                    ),
                  ),

                  // Height + Weight
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 10),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _heightController,
                          enabled: !_isLoading,
                          keyboardType: TextInputType.number,
                          style:
                              const TextStyle(color: Colors.black),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color.fromRGBO(
                                255, 255, 255, 0.9),
                            labelText: 'Height (cm)',
                            labelStyle: const TextStyle(
                                color: Colors.black),
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.height,
                                color: Colors.grey),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _weightController,
                          enabled: !_isLoading,
                          keyboardType: TextInputType.number,
                          style:
                              const TextStyle(color: Colors.black),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color.fromRGBO(
                                255, 255, 255, 0.9),
                            labelText: 'Weight (kg)',
                            labelStyle: const TextStyle(
                                color: Colors.black),
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(10)),
                            prefixIcon: const Icon(
                                Icons.monitor_weight,
                                color: Colors.grey),
                          ),
                        ),
                      ),
                    ]),
                  ),

                  // Activity Level Selector
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 10),
                    child: GestureDetector(
                      onTap:
                          _isLoading ? null : _showActivityPicker,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(
                              255, 255, 255, 0.9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selectedActivity != null
                                ? (selectedActivity['color'] as Color)
                                    .withOpacity(0.6)
                                : Colors.grey.shade400,
                            width:
                                selectedActivity != null ? 1.5 : 1,
                          ),
                        ),
                        child: selectedActivity == null
                            ? Row(children: [
                                const Icon(Icons.directions_run,
                                    color: Colors.grey, size: 22),
                                const SizedBox(width: 12),
                                Text('Select Activity Level',
                                    style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 16)),
                                const Spacer(),
                                Icon(Icons.keyboard_arrow_down,
                                    color: Colors.grey.shade500),
                              ])
                            : Row(children: [
                                Container(
                                  width: 38, height: 38,
                                  decoration: BoxDecoration(
                                    color: (selectedActivity['color']
                                            as Color)
                                        .withOpacity(0.12),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                      selectedActivity['icon']
                                          as IconData,
                                      color: selectedActivity['color']
                                          as Color,
                                      size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        selectedActivity['label']
                                            as String,
                                        style: TextStyle(
                                            fontWeight:
                                                FontWeight.bold,
                                            fontSize: 15,
                                            color: selectedActivity[
                                                    'color']
                                                as Color),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedActivity['desc']
                                            as String,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54),
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.keyboard_arrow_down,
                                    color: Colors.grey.shade500),
                              ]),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // ── REGISTER button → shows disclaimer first ───────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15),
                    child: InkWell(
                      onTap: _isLoading ? null : _onRegisterTapped,
                      child: Container(
                        height: 55,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: _isLoading
                              ? Colors.grey
                              : const Color(0xFF42A546),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24, height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3))
                              : const Text('REGISTER',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Already have account
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Already have an account? ',
                          style: TextStyle(
                              fontSize: 14, color: Colors.black)),
                      InkWell(
                        onTap: _isLoading
                            ? null
                            : () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const LoginScreen()),
                                ),
                        child: Text('Login',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _isLoading
                                    ? Colors.black12
                                    : Colors.black)),
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

  // ── Reusable input field ──────────────────────────────────────────────
  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 15, vertical: 10),
      child: TextField(
        controller: controller,
        enabled: !_isLoading,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color.fromRGBO(255, 255, 255, 0.9),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
          prefixIcon: Icon(icon, color: Colors.grey),
        ),
      ),
    );
  }
}