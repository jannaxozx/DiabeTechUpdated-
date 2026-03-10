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

  File?     _imageFile;
  Uint8List? _webImage;
  String?   _pickedExtension;
  String?   _existingPhotoUrl;
  bool      _isUploading = false;

  String? _selectedActivityLevel;

  // Activity level data: value, label, icon, color, description, examples
  final List<Map<String, dynamic>> _activityLevels = [
    {
      'value':    'Sedentary',
      'label':    'Sedentary',
      'icon':     Icons.weekend,
      'color':    const Color(0xFF9E9E9E),
      'desc':     'Little or no physical activity.',
      'examples': '🛋️ Resting  •  📺 Watching TV  •  💻 Desk work with no movement',
    },
    {
      'value':    'Light',
      'label':    'Light',
      'icon':     Icons.directions_walk,
      'color':    const Color(0xFF42A546),
      'desc':     'Minimal movement with light physical tasks.',
      'examples': '🏢 Office work  •  🚗 Driving  •  🧹 Light house chores',
    },
    {
      'value':    'Moderate',
      'label':    'Moderate',
      'icon':     Icons.fitness_center,
      'color':    const Color(0xFF2196F3),
      'desc':     'Regular movement involving some physical effort.',
      'examples': '📦 Carrying heavy objects  •  🚶 Brisk walking  •  🏋️ Light exercise',
    },
    {
      'value':    'Very Active',
      'label':    'Very Active',
      'icon':     Icons.directions_run,
      'color':    const Color(0xFFE53935),
      'desc':     'Extensive and rapid movements with high physical demands.',
      'examples': '🏃 Running  •  🏗️ Heavy labor  •  📦 Carrying heavy objects extensively',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _typeController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        _nameController.text = user.displayName ?? '';
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          _ageController.text    = (data['age']    ?? '').toString();
          _typeController.text   = data['diabetesType'] ?? '';
          _heightController.text = (data['height'] ?? '').toString();
          _weightController.text = (data['weight'] ?? '').toString();
          _existingPhotoUrl      = data['photoUrl'] ??
              data['profilePictureUrl'] ?? '';
          _selectedActivityLevel = data['activityLevel']?.toString();
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85);
      if (picked != null) {
        String ext = 'jpg';
        try {
          final e = kIsWeb
              ? p.extension(picked.name)
              : p.extension(picked.path);
          if (e.isNotEmpty) ext = e.replaceFirst('.', '');
        } catch (_) {}
        _pickedExtension = ext.toLowerCase();
        if (kIsWeb) {
          final bytes = await picked.readAsBytes();
          setState(() { _webImage = bytes; _imageFile = null; });
        } else {
          setState(() {
            _imageFile = File(picked.path); _webImage = null;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Image selected! Click Save to upload.'),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error picking image: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  String _mimeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':  return 'image/png';
      case 'webp': return 'image/webp';
      default:     return 'image/jpeg';
    }
  }

  Future<Map<String, String>?> _uploadProfileImage(String uid) async {
    try {
      final client      = SupabaseConfig.client;
      const bucket      = 'profile_images';
      final ext         = (_pickedExtension ?? 'jpg').toLowerCase();
      final fileName    = 'profile_${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final contentType = _mimeForExt(ext);

      final imageBytes = kIsWeb
          ? _webImage
          : (_imageFile != null ? await _imageFile!.readAsBytes() : null);
      if (imageBytes == null) return null;

      await client.storage.from(bucket).uploadBinary(
        fileName, imageBytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );

      final url = client.storage.from(bucket).getPublicUrl(fileName);
      return {'path': fileName, 'url': url};
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
      return null;
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    final name = _nameController.text.trim();

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No user logged in'), backgroundColor: Colors.red,
      ));
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('⚠️ Please enter your name'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _isUploading = true);
    try {
      String? photoUrl  = _existingPhotoUrl;
      String? photoPath;

      if (_imageFile != null || _webImage != null) {
        final uploaded = await _uploadProfileImage(user.uid);
        if (uploaded != null) {
          photoUrl  = uploaded['url'];
          photoPath = uploaded['path'];
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('⚠️ Image upload failed, saving other data...'),
              backgroundColor: Colors.orange,
            ));
          }
        }
      }

      await user.updateDisplayName(name);
      if (photoUrl != null && photoUrl.isNotEmpty) {
        try { await user.updatePhotoURL(photoUrl); } catch (_) {}
      }

      final data = <String, dynamic>{
        'name':          name,
        'age':           int.tryParse(_ageController.text) ?? 0,
        'diabetesType':  _typeController.text.trim(),
        'height':        double.tryParse(_heightController.text.trim()) ?? 0.0,
        'weight':        double.tryParse(_weightController.text.trim()) ?? 0.0,
        'activityLevel': _selectedActivityLevel ?? '',
      };
      if (photoUrl  != null && photoUrl.isNotEmpty) data['photoUrl'] = photoUrl;
      if (photoPath != null) data['photoPath'] = photoPath;

      await _firestore.collection('users').doc(user.uid).set(
            data, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Profile updated successfully!'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Activity picker bottom sheet ──────────────────────────────────
  void _showActivityPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
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
                  setState(() =>
                      _selectedActivityLevel = level['value'] as String);
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
                        borderRadius: BorderRadius.circular(12),
                      ),
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
            (a) => a['value'] == _selectedActivityLevel,
            orElse: () => <String, dynamic>{})
        : <String, dynamic>{};

    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C6E49),
        title: const Text('Edit Profile',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            // ── Avatar ──────────────────────────────────────────────
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.grey.shade200,
                    child: _buildProfileImage(),
                  ),
                  Positioned(
                    bottom: 0, right: 4,
                    child: InkWell(
                      onTap: _isUploading ? null : _pickImage,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isUploading
                              ? Colors.grey
                              : const Color(0xFF2C6E49),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          _isUploading
                              ? Icons.hourglass_empty
                              : Icons.edit,
                          color: Colors.white, size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_isUploading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Uploading...',
                    style: TextStyle(color: Colors.blue, fontSize: 12)),
              ),
            const SizedBox(height: 25),

            // ── Form card ────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(2, 3))
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Full Name
                  _buildTextField(
                    controller: _nameController,
                    label: 'Full Name*',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 15),

                  // Age
                  _buildTextField(
                    controller: _ageController,
                    label: 'Age',
                    icon: Icons.calendar_today,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 15),

                  // Diabetes Type
                  _buildTextField(
                    controller: _typeController,
                    label: 'Diabetes Type (e.g., Mild, Severe)',
                    icon: Icons.favorite,
                  ),
                  const SizedBox(height: 15),

                  // ── Height + Weight side by side ─────────────────
                  Row(children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _heightController,
                        label: 'Height (cm)',
                        icon: Icons.height,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _weightController,
                        label: 'Weight (kg)',
                        icon: Icons.monitor_weight,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 15),

                  // ── Activity Level selector ───────────────────────
                  const Text('Activity Level',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _isUploading ? null : _showActivityPicker,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedActivity.isNotEmpty
                              ? (selectedActivity['color'] as Color)
                                  .withOpacity(0.6)
                              : const Color(0xFF2C6E49),
                          width: selectedActivity.isNotEmpty ? 1.5 : 1,
                        ),
                      ),
                      child: selectedActivity.isEmpty
                          ? Row(children: [
                              const Icon(Icons.directions_run,
                                  color: Colors.grey, size: 22),
                              const SizedBox(width: 12),
                              Text('Select Activity Level',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 15)),
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
                                    selectedActivity['icon'] as IconData,
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
                                      selectedActivity['label'] as String,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: selectedActivity[
                                              'color'] as Color),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      selectedActivity['desc'] as String,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      selectedActivity['examples']
                                          as String,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: (selectedActivity[
                                                  'color'] as Color)
                                              .withOpacity(0.8),
                                          fontStyle: FontStyle.italic),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.keyboard_arrow_down,
                                  color: Colors.grey.shade500),
                            ]),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // ── Save button ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isUploading
                      ? Colors.grey
                      : const Color(0xFF2C6E49),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 5,
                ),
                icon: _isUploading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, color: Colors.white),
                label: Text(
                  _isUploading ? 'Saving...' : 'Save Changes',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Delete Account button ────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isUploading ? null : _deleteAccount,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text(
                  'Delete My Account',
                  style: TextStyle(color: Colors.red, fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }


  // ── Delete own account ────────────────────────────────────────────────
  Future<void> _deleteAccount() async {
    // Step 1: Confirm
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
          SizedBox(width: 8),
          Text('Delete Account',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to permanently delete your account?',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Text(
                '⚠️ This will permanently delete your account and ALL your data '
                '(meal logs, scan history, profile). This cannot be undone.',
                style: TextStyle(
                    fontSize: 12, color: Colors.red, height: 1.5),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete My Account',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // Step 2: Delete everything
    setState(() => _isUploading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final uid = user.uid;

      // Delete Firestore sub-collections
      for (final sub in ['foodLogs', 'mealLogs', 'scannedFoods']) {
        final snap = await _firestore
            .collection('users')
            .doc(uid)
            .collection(sub)
            .get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
      }

      // Delete Firestore user document
      await _firestore.collection('users').doc(uid).delete();

      // Delete Firebase Auth account directly
      await user.delete();

      // Sign out to clear any local session
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Force navigate to login and clear entire navigation stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      if (e.code == 'requires-recent-login') {
        // Session too old — sign out and force re-login first
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        // Show message on login screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please log in again to confirm account deletion.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _buildProfileImage() {
    if (_webImage != null) {
      return ClipOval(child: Image.memory(
          _webImage!, width: 110, height: 110, fit: BoxFit.cover));
    }
    if (_imageFile != null) {
      return ClipOval(child: Image.file(
          _imageFile!, width: 110, height: 110, fit: BoxFit.cover));
    }
    if (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          _existingPhotoUrl!,
          width: 110, height: 110, fit: BoxFit.cover,
          loadingBuilder: (_, child, p) =>
              p == null ? child : const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.person, size: 60, color: Colors.grey),
        ),
      );
    }
    return const Icon(Icons.person, size: 60, color: Colors.grey);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: !_isUploading,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF2C6E49)),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black54),
        filled: true,
        fillColor: Colors.grey.shade50,
        enabledBorder: OutlineInputBorder(
          borderSide:
              const BorderSide(color: Color(0xFF2C6E49), width: 1.0),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide:
              const BorderSide(color: Color(0xFF2C6E49), width: 2.0),
          borderRadius: BorderRadius.circular(12),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide:
              BorderSide(color: Colors.grey.shade300, width: 1.0),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}