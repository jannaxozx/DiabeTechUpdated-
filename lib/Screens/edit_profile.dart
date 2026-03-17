import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:diabetechapp/supabase_config.dart';
import 'package:diabetechapp/Screens/log_in.dart';

// ── Palette — identical to dashboard ────────────────────────────────────────
const _ep_bg       = Color(0xFFF4F7F5);
const _ep_white    = Color(0xFFFFFFFF);
const _ep_green    = Color(0xFF2C6E49);
const _ep_greenLt  = Color(0xFF4A9B6F);
const _ep_greenPal = Color(0xFFE8F5EE);
const _ep_red      = Color(0xFFD64045);
const _ep_redPal   = Color(0xFFFDECEC);
const _ep_amber    = Color(0xFFF09D18);
const _ep_amberPal = Color(0xFFFFF4E0);
const _ep_blue     = Color(0xFF2979C6);
const _ep_bluePal  = Color(0xFFE8F0FB);
const _ep_teal     = Color(0xFF0D8A7C);
const _ep_tealPal  = Color(0xFFE3F5F3);
const _ep_grey1    = Color(0xFF1A2E22);
const _ep_grey2    = Color(0xFF4D6357);
const _ep_grey3    = Color(0xFF8FA898);
const _ep_grey4    = Color(0xFFD5E2DA);
const _ep_grey5    = Color(0xFFF0F5F2);

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _auth      = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _nameController   = TextEditingController();
  final _ageController    = TextEditingController();
  final _typeController   = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  File?      _imageFile;
  Uint8List? _webImage;
  String?    _pickedExtension;
  String?    _existingPhotoUrl;
  bool       _isUploading = false;
  String?    _selectedActivityLevel;

  final List<Map<String, dynamic>> _activityLevels = [
    {
      'value': 'Sedentary', 'label': 'Sedentary',
      'icon': Icons.weekend,
      'color': const Color(0xFF9E9E9E),
      'desc': 'Little or no physical activity.',
      'examples': '🛋️ Resting  •  📺 Watching TV  •  💻 Desk work with no movement',
    },
    {
      'value': 'Light', 'label': 'Light',
      'icon': Icons.directions_walk,
      'color': _ep_green,
      'desc': 'Minimal movement with light physical tasks.',
      'examples': '🏢 Office work  •  🚗 Driving  •  🧹 Light house chores',
    },
    {
      'value': 'Very Active', 'label': 'Very Active',
      'icon': Icons.directions_run,
      'color': _ep_red,
      'desc': 'Extensive and rapid movements with high physical demands.',
      'examples': '🏃 Running  •  🏗️ Heavy labor  •  📦 Carrying heavy objects extensively',
    },
  ];

  @override
  void initState() { super.initState(); _loadUserData(); }

  @override
  void dispose() {
    _nameController.dispose(); _ageController.dispose();
    _typeController.dispose(); _heightController.dispose();
    _weightController.dispose(); super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        _nameController.text = user.displayName ?? '';
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          _ageController.text    = (data['age'] ?? '').toString();
          _typeController.text   = data['diabetesType'] ?? '';
          _heightController.text = (data['height'] ?? '').toString();
          _weightController.text = (data['weight'] ?? '').toString();
          _existingPhotoUrl      = data['photoUrl'] ?? data['profilePictureUrl'] ?? '';
          _selectedActivityLevel = data['activityLevel']?.toString();
          if (mounted) setState(() {});
        }
      }
    } catch (e) { debugPrint('Error loading user data: $e'); }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked != null) {
        String ext = 'jpg';
        try {
          final e = kIsWeb ? p.extension(picked.name) : p.extension(picked.path);
          if (e.isNotEmpty) ext = e.replaceFirst('.', '');
        } catch (_) {}
        _pickedExtension = ext.toLowerCase();
        if (kIsWeb) {
          final bytes = await picked.readAsBytes();
          setState(() { _webImage = bytes; _imageFile = null; });
        } else {
          setState(() { _imageFile = File(picked.path); _webImage = null; });
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Image selected! Tap Save to upload.'),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error picking image: $e'), backgroundColor: _ep_red,
      ));
    }
  }

  String _mimeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      default: return 'image/jpeg';
    }
  }

  Future<Map<String, String>?> _uploadProfileImage(String uid) async {
    try {
      final client   = SupabaseConfig.client;
      const bucket   = 'profile_images';
      final ext      = (_pickedExtension ?? 'jpg').toLowerCase();
      final fileName = 'profile_${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final ct       = _mimeForExt(ext);
      final bytes    = kIsWeb ? _webImage : (_imageFile != null ? await _imageFile!.readAsBytes() : null);
      if (bytes == null) return null;
      await client.storage.from(bucket).uploadBinary(fileName, bytes,
          fileOptions: FileOptions(contentType: ct, upsert: true));
      final url = client.storage.from(bucket).getPublicUrl(fileName);
      return {'path': fileName, 'url': url};
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: _ep_red));
      return null;
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    final name = _nameController.text.trim();
    if (user == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No user logged in'), backgroundColor: _ep_red)); return; }
    if (name.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Please enter your name'), backgroundColor: _ep_amber)); return; }
    setState(() => _isUploading = true);
    try {
      String? photoUrl = _existingPhotoUrl, photoPath;
      if (_imageFile != null || _webImage != null) {
        final up = await _uploadProfileImage(user.uid);
        if (up != null) { photoUrl = up['url']; photoPath = up['path']; }
        else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Image upload failed, saving other data...'), backgroundColor: _ep_amber));
      }
      await user.updateDisplayName(name);
      if (photoUrl != null && photoUrl.isNotEmpty) { try { await user.updatePhotoURL(photoUrl); } catch (_) {} }
      final data = <String, dynamic>{
        'name': name, 'age': int.tryParse(_ageController.text) ?? 0,
        'diabetesType': _typeController.text.trim(),
        'height': double.tryParse(_heightController.text.trim()) ?? 0.0,
        'weight': double.tryParse(_weightController.text.trim()) ?? 0.0,
        'activityLevel': _selectedActivityLevel ?? '',
      };
      if (photoUrl != null && photoUrl.isNotEmpty) data['photoUrl'] = photoUrl;
      if (photoPath != null) data['photoPath'] = photoPath;
      await _firestore.collection('users').doc(user.uid).set(data, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Profile updated successfully!'), backgroundColor: _ep_green));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e'), backgroundColor: _ep_red));
    } finally { if (mounted) setState(() => _isUploading = false); }
  }

  void _showActivityPicker() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(color: _ep_white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _ep_grey4, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 16),
          const Text('Select Activity Level', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ep_grey1)),
          const SizedBox(height: 4),
          const Text('Choose the level that best describes your daily routine', style: TextStyle(color: _ep_grey3, fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ..._activityLevels.map((level) {
            final isSelected = _selectedActivityLevel == level['value'];
            final color = level['color'] as Color;
            return GestureDetector(
              onTap: () { setState(() => _selectedActivityLevel = level['value'] as String); Navigator.pop(ctx); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? color.withOpacity(0.07) : _ep_grey5,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isSelected ? color : _ep_grey4, width: isSelected ? 1.5 : 1),
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.12) : _ep_grey4, borderRadius: BorderRadius.circular(12)),
                    child: Icon(level['icon'] as IconData, color: isSelected ? color : _ep_grey3, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(level['label'] as String, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: isSelected ? color : _ep_grey1)),
                      if (isSelected) ...[const SizedBox(width: 6), Icon(Icons.check_circle_rounded, color: color, size: 15)],
                    ]),
                    const SizedBox(height: 3),
                    Text(level['desc'] as String, style: const TextStyle(fontSize: 11, color: _ep_grey3, height: 1.3)),
                    const SizedBox(height: 3),
                    Text(level['examples'] as String, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8), fontStyle: FontStyle.italic, height: 1.3)),
                  ])),
                ]),
              ),
            );
          }).toList(),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selAct = _selectedActivityLevel != null
        ? _activityLevels.firstWhere((a) => a['value'] == _selectedActivityLevel, orElse: () => <String, dynamic>{})
        : <String, dynamic>{};

    return Scaffold(
      backgroundColor: _ep_bg,
      body: Column(children: [
        // ── Gradient header ───────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF2C6E49), Color(0xFF4A9B6F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 20),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              ),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Edit Profile', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
                Text('Update your personal information', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
            ]),
          )),
        ),

        // ── Body ─────────────────────────────────────────────────────
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [

            // Avatar card
            _card(Column(children: [
              const SizedBox(height: 4),
              Center(child: Stack(children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _ep_green, width: 3),
                    boxShadow: [BoxShadow(color: _ep_green.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: ClipOval(child: _buildProfileImage()),
                ),
                Positioned(bottom: 0, right: 0,
                  child: GestureDetector(
                    onTap: _isUploading ? null : _pickImage,
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: _isUploading ? _ep_grey3 : _ep_green,
                        shape: BoxShape.circle,
                        border: Border.all(color: _ep_white, width: 2),
                      ),
                      child: Icon(_isUploading ? Icons.hourglass_empty : Icons.edit_rounded, color: Colors.white, size: 15),
                    ),
                  )),
              ])),
              const SizedBox(height: 12),
              _isUploading
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: _ep_bluePal, borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: _ep_blue)),
                        SizedBox(width: 8),
                        Text('Uploading...', style: TextStyle(fontSize: 11, color: _ep_blue, fontWeight: FontWeight.w600)),
                      ]))
                  : const Text('Tap the pencil to change photo', style: TextStyle(fontSize: 11, color: _ep_grey3)),
              const SizedBox(height: 4),
            ])),
            const SizedBox(height: 14),

            // Personal info card
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _cardTitle('Personal Information', Icons.person_rounded, _ep_blue, _ep_bluePal),
              const SizedBox(height: 14),
              _field(Icons.person_rounded, 'Full Name*', _nameController),
              const SizedBox(height: 12),
              _field(Icons.cake_rounded, 'Age', _ageController, keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              _field(Icons.monitor_heart_rounded, 'Diabetes Type (e.g. Mild, Severe)', _typeController),
            ])),
            const SizedBox(height: 14),

            // Body measurements card
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _cardTitle('Body Measurements', Icons.straighten_rounded, _ep_teal, _ep_tealPal),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _field(Icons.height_rounded, 'Height (cm)', _heightController, keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _field(Icons.monitor_weight_rounded, 'Weight (kg)', _weightController, keyboardType: TextInputType.number)),
              ]),
            ])),
            const SizedBox(height: 14),

            // Activity level card
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _cardTitle('Activity Level', Icons.directions_run_rounded, const Color(0xFFF09D18), const Color(0xFFFFF4E0)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _isUploading ? null : _showActivityPicker,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _ep_grey5,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selAct.isNotEmpty ? (selAct['color'] as Color).withOpacity(0.5) : _ep_grey4,
                      width: selAct.isNotEmpty ? 1.5 : 1,
                    ),
                  ),
                  child: selAct.isEmpty
                      ? const Row(children: [
                          Icon(Icons.directions_run_rounded, color: _ep_grey3, size: 20),
                          SizedBox(width: 12),
                          Expanded(child: Text('Select Activity Level', style: TextStyle(color: _ep_grey3, fontSize: 14))),
                          Icon(Icons.keyboard_arrow_down_rounded, color: _ep_grey3, size: 20),
                        ])
                      : Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: (selAct['color'] as Color).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                            child: Icon(selAct['icon'] as IconData, color: selAct['color'] as Color, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(selAct['label'] as String, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: selAct['color'] as Color)),
                            const SizedBox(height: 2),
                            Text(selAct['desc'] as String, style: const TextStyle(fontSize: 11, color: _ep_grey3), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(selAct['examples'] as String, style: TextStyle(fontSize: 10, color: (selAct['color'] as Color).withOpacity(0.8), fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ])),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: _ep_grey3, size: 20),
                        ]),
                ),
              ),
            ])),
            const SizedBox(height: 22),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _saveProfile,
                icon: _isUploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, color: Colors.white, size: 18),
                label: Text(_isUploading ? 'Saving...' : 'Save Changes',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isUploading ? _ep_grey4 : _ep_green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Delete button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isUploading ? null : _deleteAccount,
                icon: const Icon(Icons.delete_forever_rounded, color: _ep_red, size: 18),
                label: const Text('Delete My Account', style: TextStyle(color: _ep_red, fontSize: 15, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _ep_red.withOpacity(0.5), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  backgroundColor: _ep_redPal,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ]),
        )),
      ]),
    );
  }

  // ── Shared UI helpers ─────────────────────────────────────────────────────

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _ep_white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: child,
      );

  Widget _cardTitle(String label, IconData icon, Color color, Color pal) =>
      Row(children: [
        Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: pal, borderRadius: BorderRadius.circular(9)), child: Icon(icon, color: color, size: 15)),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ep_grey1)),
      ]);

  Widget _field(IconData icon, String hint, TextEditingController ctrl, {TextInputType keyboardType = TextInputType.text}) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        enabled: !_isUploading,
        style: const TextStyle(color: _ep_grey1, fontSize: 14),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _isUploading ? _ep_grey4 : _ep_green, size: 18),
          hintText: hint,
          hintStyle: const TextStyle(color: _ep_grey3, fontSize: 13),
          filled: true,
          fillColor: _isUploading ? _ep_grey5 : _ep_white,
          contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ep_grey4)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ep_grey4)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ep_green, width: 1.5)),
          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _ep_grey4)),
        ),
      );

  // ── Logic helpers ──────────────────────────────────────────────────────────

  Widget _buildProfileImage() {
    if (_webImage != null) return Image.memory(_webImage!, width: 100, height: 100, fit: BoxFit.cover);
    if (_imageFile != null) return Image.file(_imageFile!, width: 100, height: 100, fit: BoxFit.cover);
    if (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty) {
      return Image.network(_existingPhotoUrl!, width: 100, height: 100, fit: BoxFit.cover,
          loadingBuilder: (_, child, p) => p == null ? child : Container(color: _ep_greenPal, child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _ep_green))),
          errorBuilder: (_, __, ___) => Container(color: _ep_greenPal, child: const Icon(Icons.person_rounded, size: 50, color: _ep_green)));
    }
    return Container(color: _ep_greenPal, child: const Icon(Icons.person_rounded, size: 50, color: _ep_green));
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: _ep_red, size: 26),
          SizedBox(width: 8),
          Text('Delete Account', style: TextStyle(color: _ep_red, fontWeight: FontWeight.w700)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Are you sure you want to permanently delete your account?', style: TextStyle(fontSize: 14, color: _ep_grey1)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _ep_redPal, borderRadius: BorderRadius.circular(10), border: Border.all(color: _ep_red.withOpacity(0.3))),
            child: const Text('⚠️ This will permanently delete your account and ALL your data (meal logs, scan history, profile). This cannot be undone.',
                style: TextStyle(fontSize: 12, color: _ep_red, height: 1.5)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: _ep_grey3))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _ep_red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Account', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _isUploading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final uid = user.uid;
      for (final sub in ['foodLogs', 'mealLogs', 'scannedFoods']) {
        final snap = await _firestore.collection('users').doc(uid).collection(sub).get();
        for (final doc in snap.docs) await doc.reference.delete();
      }
      await _firestore.collection('users').doc(uid).delete();
      await user.delete();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      if (e.code == 'requires-recent-login') {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Please log in again to confirm account deletion.'), backgroundColor: _ep_amber, duration: Duration(seconds: 4)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: ${e.message}'), backgroundColor: _ep_red));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Failed: $e'), backgroundColor: _ep_red));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
}