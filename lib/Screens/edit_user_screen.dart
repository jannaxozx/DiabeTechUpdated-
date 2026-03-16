import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Palette (matches admin_dashboard) ────────────────────────────────────────
const _bg       = Color(0xFFF4F7F5);
const _white    = Color(0xFFFFFFFF);
const _green    = Color(0xFF2C6E49);
const _greenLt  = Color(0xFF4A9B6F);
const _greenPal = Color(0xFFE8F5EE);
const _red      = Color(0xFFD64045);
const _redPal   = Color(0xFFFDECEC);
const _amber    = Color(0xFFF09D18);
const _amberPal = Color(0xFFFFF4E0);
const _blue     = Color(0xFF2979C6);
const _bluePal  = Color(0xFFE8F0FB);
const _grey1    = Color(0xFF1A2E22);
const _grey2    = Color(0xFF4D6357);
const _grey3    = Color(0xFF8FA898);
const _grey4    = Color(0xFFD5E2DA);
const _grey5    = Color(0xFFF0F5F2);

class EditUserScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> userData;

  const EditUserScreen({
    super.key,
    required this.userId,
    required this.userData,
  });

  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  String _role = 'user';
  bool   _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(
        text: widget.userData['name']?.toString()  ?? '');
    _emailCtrl = TextEditingController(
        text: widget.userData['email']?.toString() ?? '');
    _role = widget.userData['role']?.toString() ?? 'user';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (name.isEmpty) {
      _snack('Please enter a name', isError: true);
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      _snack('Please enter a valid email', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({
        'name':  name,
        'email': email,
        'role':  _role,
      });

      if (!mounted) return;
      _snack('User updated successfully');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to update: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? _red : _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Avatar initial + color based on current role
    final name    = _nameCtrl.text.isNotEmpty ? _nameCtrl.text : '?';
    final initial = name[0].toUpperCase();
    final isAdmin = _role == 'admin';

    return Scaffold(
      backgroundColor: _bg,
      // ── Same gradient AppBar as dashboard ──────────────────────────────
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_green, _greenLt],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit User',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            Text('Update user information',
                style: TextStyle(
                    color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [

          // ── Avatar card ──────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Column(children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: isAdmin ? _amberPal : _greenPal,
                child: Text(initial,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isAdmin ? _amber : _green)),
              ),
              const SizedBox(height: 10),
              Text(name,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _grey1)),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isAdmin ? _amberPal : _greenPal,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isAdmin
                          ? _amber.withOpacity(0.3)
                          : _green.withOpacity(0.3)),
                ),
                child: Text(
                  isAdmin ? '👑 Admin' : '👤 User',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isAdmin ? _amber : _green),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Form card ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account Information',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _grey2)),
                const SizedBox(height: 14),

                // Name field
                _label('Full Name'),
                const SizedBox(height: 6),
                _field(
                  controller: _nameCtrl,
                  hint: 'Enter full name',
                  icon: Icons.person_rounded,
                  onChanged: (_) => setState(() {}), // refresh avatar
                ),
                const SizedBox(height: 14),

                // Email field
                _label('Email Address'),
                const SizedBox(height: 6),
                _field(
                  controller: _emailCtrl,
                  hint: 'Enter email address',
                  icon: Icons.email_rounded,
                  keyboard: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),

                // Role dropdown
                _label('Role'),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: _grey5,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _grey4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _role,
                      isExpanded: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      borderRadius: BorderRadius.circular(12),
                      icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: _grey3),
                      style: const TextStyle(
                          color: _grey1,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                      items: [
                        DropdownMenuItem(
                          value: 'user',
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: _greenPal,
                                  borderRadius:
                                      BorderRadius.circular(8)),
                              child: const Icon(
                                  Icons.person_rounded,
                                  color: _green,
                                  size: 15),
                            ),
                            const SizedBox(width: 10),
                            const Text('User'),
                          ]),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: _amberPal,
                                  borderRadius:
                                      BorderRadius.circular(8)),
                              child: const Icon(
                                  Icons.admin_panel_settings_rounded,
                                  color: _amber,
                                  size: 15),
                            ),
                            const SizedBox(width: 10),
                            const Text('Admin'),
                          ]),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _role = v!),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Warning card (role change) ───────────────────────────────
          if (isAdmin)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _amberPal,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _amber.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: _amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(
                        Icons.tips_and_updates_rounded,
                        color: _amber,
                        size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'This user has Admin privileges. '
                      'Admins can manage users and food rules.',
                      style: TextStyle(
                          fontSize: 12,
                          color: _grey2,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          if (isAdmin) const SizedBox(height: 16),

          // ── Save button ──────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(
                _saving ? 'Saving...' : 'Save Changes',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _saving ? _grey4 : _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Cancel button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _grey2,
                side: const BorderSide(color: _grey4),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Cancel',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Shared widgets ───────────────────────────────────────────────────────

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _grey2));

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) =>
      TextField(
        controller: controller,
        enabled: !_saving,
        keyboardType: keyboard,
        onChanged: onChanged,
        style: const TextStyle(
            color: _grey1, fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _grey3, fontSize: 13),
          prefixIcon: Icon(icon, color: _green, size: 19),
          filled: true,
          fillColor: _saving ? _grey5 : _grey5,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _grey4)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _grey4)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: _green, width: 1.5)),
          disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _grey4)),
        ),
      );
}