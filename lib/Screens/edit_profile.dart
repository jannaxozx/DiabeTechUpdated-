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

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _typeController = TextEditingController();

  File? _imageFile;
  Uint8List? _webImage;
  String? _pickedExtension;
  String? _existingPhotoUrl;
  bool _isUploading = false;

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
          _ageController.text = (data['age'] ?? '').toString();
          _typeController.text = data['diabetesType'] ?? '';
          _existingPhotoUrl = data['photoUrl'] ?? '';
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
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (picked != null) {
        String ext = 'jpg';
        try {
          final e = kIsWeb ? p.extension(picked.name) : p.extension(picked.path);
          if (e.isNotEmpty) ext = e.replaceFirst('.', '');
        } catch (_) {}
        _pickedExtension = ext.toLowerCase();

        if (kIsWeb) {
          final bytes = await picked.readAsBytes();
          setState(() {
            _webImage = bytes;
            _imageFile = null;
          });
        } else {
          setState(() {
            _imageFile = File(picked.path);
            _webImage = null;
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Image selected! Click Save to upload.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _mimeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<Map<String, String>?> _uploadProfileImage(String uid) async {
    try {
      final client = SupabaseConfig.client;
      const bucket = 'profile_images'; // ✅ FIXED: Changed from PROFILE_IMAGES to profile_images
      final ext = (_pickedExtension ?? 'jpg').toLowerCase();
      final fileName = 'profile_${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final contentType = _mimeForExt(ext);

      debugPrint('Uploading to bucket: $bucket');
      debugPrint('File name: $fileName');
      debugPrint('Content type: $contentType');

      if (kIsWeb) {
        if (_webImage == null) return null;
        await client.storage.from(bucket).uploadBinary(
              fileName,
              _webImage!,
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: true,
              ),
            );
      } else {
        if (_imageFile == null) return null;
        final bytes = await _imageFile!.readAsBytes();
        await client.storage.from(bucket).uploadBinary(
              fileName,
              bytes,
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: true,
              ),
            );
      }

      // Get public URL (since bucket is public)
      final url = client.storage.from(bucket).getPublicUrl(fileName);
      debugPrint('Upload successful! URL: $url');

      return {'path': fileName, 'url': url};
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    final name = _nameController.text.trim();

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No user logged in'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please enter your name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      String? photoUrl = _existingPhotoUrl;
      String? photoPath;

      // Upload new image if selected
      if (_imageFile != null || _webImage != null) {
        final uploaded = await _uploadProfileImage(user.uid);
        if (uploaded != null) {
          photoUrl = uploaded['url'];
          photoPath = uploaded['path'];
        } else {
          // Upload failed, but continue saving other data
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Image upload failed, but saving other data...'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      // Update Firebase Auth
      await user.updateDisplayName(name);
      if (photoUrl != null && photoUrl.isNotEmpty) {
        try {
          await user.updatePhotoURL(photoUrl);
        } catch (e) {
          debugPrint('Error updating photo URL in Auth: $e');
        }
      }

      // Update Firestore
      final data = {
        'name': name,
        'age': int.tryParse(_ageController.text) ?? 0,
        'diabetesType': _typeController.text.trim(),
      };
      if (photoUrl != null && photoUrl.isNotEmpty) {
        data['photoUrl'] = photoUrl;
      }
      if (photoPath != null) {
        data['photoPath'] = photoPath;
      }

      await _firestore.collection('users').doc(user.uid).set(
            data,
            SetOptions(merge: true),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C6E49),
        title: const Text("Edit Profile", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.grey.shade200,
                    child: _buildProfileImage(),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 4,
                    child: InkWell(
                      onTap: _isUploading ? null : _pickImage,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isUploading ? Colors.grey : const Color(0xFF2C6E49),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          _isUploading ? Icons.hourglass_empty : Icons.edit,
                          color: Colors.white,
                          size: 20,
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
                child: Text(
                  'Uploading...',
                  style: TextStyle(color: Colors.blue, fontSize: 12),
                ),
              ),

            const SizedBox(height: 25),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(2, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildTextField(
                    controller: _nameController,
                    label: "Full Name*",
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 15),
                  _buildTextField(
                    controller: _ageController,
                    label: "Age",
                    icon: Icons.calendar_today,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 15),
                  _buildTextField(
                    controller: _typeController,
                    label: "Diabetes Type (e.g., Type 1, Type 2)",
                    icon: Icons.favorite,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isUploading ? Colors.grey : const Color(0xFF2C6E49),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 5,
                ),
                icon: _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save, color: Colors.white),
                label: Text(
                  _isUploading ? 'Saving...' : 'Save Changes',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileImage() {
    if (_webImage != null) {
      return ClipOval(
        child: Image.memory(
          _webImage!,
          width: 110,
          height: 110,
          fit: BoxFit.cover,
        ),
      );
    }

    if (_imageFile != null) {
      return ClipOval(
        child: Image.file(
          _imageFile!,
          width: 110,
          height: 110,
          fit: BoxFit.cover,
        ),
      );
    }

    if (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          _existingPhotoUrl!,
          width: 110,
          height: 110,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          },
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
          borderSide: const BorderSide(color: Color(0xFF2C6E49), width: 1.0),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF2C6E49), width: 2.0),
          borderRadius: BorderRadius.circular(12),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}