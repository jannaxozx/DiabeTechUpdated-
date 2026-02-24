import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'admin_food_rules_screen.dart';
import 'admin_food_detail_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:diabetechapp/Screens/user_food_log_screen.dart';
import 'package:diabetechapp/health/do_dont_foods_screen.dart';
import 'landing_page.dart';
import 'edit_user_screen.dart';
import 'admin_reports.dart';
import '../supabase_config.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  String searchQuery = "";
  String _selectedUserDiabetesType = 'All';

  final TextEditingController nameController = TextEditingController();
  final TextEditingController portionController = TextEditingController();
  final TextEditingController caloriesController = TextEditingController();
  final TextEditingController carbsController = TextEditingController();
  final TextEditingController proteinController = TextEditingController();
  final TextEditingController fatController = TextEditingController();

  String category = "Do";
  File? _selectedImage;
  Uint8List? _webImage;

  bool _isUploading = false;
  String _uploadStatus = '';

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _verifyAdminStatus();
  }

  Future<void> _verifyAdminStatus() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        debugPrint('❌ No user logged in');
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        debugPrint('❌ User document does not exist');
        return;
      }

      final role = userDoc.data()?['role'];
      debugPrint('✅ Current user role: $role');
      debugPrint('✅ User ID: ${currentUser.uid}');
      debugPrint('✅ User email: ${currentUser.email}');

      if (role != 'admin') {
        debugPrint('⚠️ WARNING: User is not an admin!');
      } else {
        debugPrint('✅ Admin verified successfully');
      }
    } catch (e) {
      debugPrint('❌ Error verifying admin status: $e');
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    portionController.dispose();
    caloriesController.dispose();
    carbsController.dispose();
    proteinController.dispose();
    fatController.dispose();
    super.dispose();
  }

  void _updateStatus(String status) {
    debugPrint('STATUS: $status');
    if (mounted) {
      setState(() => _uploadStatus = status);
    }
  }

  String _extractSupabasePath(String url, {String bucket = 'food_images'}) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final pubIndex = segments.indexOf('public');
      if (pubIndex != -1 && pubIndex + 2 < segments.length) {
        final fileSegments = segments.sublist(pubIndex + 2);
        return fileSegments.join('/');
      }
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : url.split('/').last;
    } catch (e) {
      return url.split('/').last;
    }
  }

  void _clearForm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear Form"),
        content: const Text("Are you sure you want to clear all fields?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              nameController.clear();
              portionController.clear();
              caloriesController.clear();
              carbsController.clear();
              proteinController.clear();
              fatController.clear();
              setState(() {
                _selectedImage = null;
                _webImage = null;
                category = "Do";
                _uploadStatus = '';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("✅ Form cleared"))
              );
            },
            child: const Text("Clear", style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LandingPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Logout failed: $e")));
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Logout"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _logout(context);
            },
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    if (kIsWeb) {
      try {
        final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
        if (result != null && result.files.single.bytes != null) {
          setState(() {
            _webImage = result.files.single.bytes;
            _selectedImage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Image selected successfully"))
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not pick image: $e")));
      }
    } else {
      try {
        final picked = await _imagePicker.pickImage(source: ImageSource.gallery, maxWidth: 1600);
        if (picked != null) {
          setState(() {
            _selectedImage = File(picked.path);
            _webImage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Image selected successfully"))
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not pick image: $e")));
      }
    }
  }

  Future<String?> _uploadImageToStorage() async {
    if (!kIsWeb && _selectedImage == null) {
      debugPrint('Skipping image upload - no mobile image');
      return '';
    }
    if (kIsWeb && _webImage == null) {
      debugPrint('Skipping image upload - no web image');
      return '';
    }

    try {
      _updateStatus('Uploading image to Supabase...');
      final fileName = "food_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final bucket = 'food_images';
      final client = SupabaseConfig.client;

      if (kIsWeb) {
        debugPrint('Uploading web image to Supabase...');
        await client.storage.from(bucket).uploadBinary(
          fileName,
          _webImage!,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
      } else {
        debugPrint('Uploading mobile image to Supabase...');
        final bytes = await _selectedImage!.readAsBytes();
        await client.storage.from(bucket).uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
      }

      _updateStatus('Image uploaded!');
      return fileName;
    } catch (e) {
      debugPrint('Image upload error: $e');
      if (!mounted) return null;

      String errorMsg = 'Image upload failed: $e';
      if (e.toString().toLowerCase().contains('permission') || 
          e.toString().toLowerCase().contains('unauthorized')) {
        errorMsg = '❌ Storage permission denied. Check Supabase Storage RLS/policies!';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red, duration: const Duration(seconds: 5))
        );
      }
      return null;
    }
  }

  Future<void> _addFood() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please enter a food name"))
      );
      return;
    }

    if (portionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please enter portion size"))
      );
      return;
    }

    bool hasImage = (kIsWeb && _webImage != null) || (!kIsWeb && _selectedImage != null);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Add Food"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Name: $name", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("Category: $category"),
            Text("Portion: ${portionController.text.trim()}"),
            if (caloriesController.text.trim().isNotEmpty)
              Text("Calories: ${caloriesController.text.trim()}"),
            if (carbsController.text.trim().isNotEmpty)
              Text("Carbs: ${carbsController.text.trim()}g"),
            if (proteinController.text.trim().isNotEmpty)
              Text("Protein: ${proteinController.text.trim()}g"),
            if (fatController.text.trim().isNotEmpty)
              Text("Fat: ${fatController.text.trim()}g"),
            const SizedBox(height: 8),
            Text(
              hasImage ? "✅ With image" : "⚠️ No image",
              style: TextStyle(
                color: hasImage ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text("Add this food to the database?"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!hasImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Adding food without image"),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        )
      );
    }

    if (mounted) setState(() => _isUploading = true);
    _updateStatus('Starting...');

    try {
      String imageUrl = '';
      String imagePath = '';

      if (hasImage) {
        _updateStatus('Uploading image...');
        final path = await _uploadImageToStorage();

        if (path == null) {
          final continueWithout = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Image Upload Failed"),
              content: const Text("Image upload failed. Continue adding food without image?"),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text("Continue"),
                ),
              ],
            ),
          );

          if (continueWithout != true) {
            if (mounted) setState(() => _isUploading = false);
            return;
          }
        } else {
          imagePath = path;
          try {
            final signed = await SupabaseConfig.client.storage
                .from('food_images')
                .createSignedUrl(imagePath, 60 * 60 * 24 * 7); // 7 days
            imageUrl = signed;
          } catch (e) {
            debugPrint('Failed to create signed URL: $e');
            imageUrl = '';
          }
        }
      }

      _updateStatus('Checking admin permissions...');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Not logged in');
      }

      debugPrint('Current user ID: ${currentUser.uid}');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Timeout checking admin status');
            },
          );

      if (!userDoc.exists) {
        throw Exception('User document not found');
      }

      final role = userDoc.data()?['role'] ?? '';
      debugPrint('User role: $role');

      if (role != 'admin') {
        throw Exception('You are not an admin. Your role: $role');
      }

      _updateStatus('Saving to database...');
      debugPrint('Adding food to Firestore...');

      await FirebaseFirestore.instance.collection('food_rules').add({
        'name': name,
        'category': category,
        'portionSize': portionController.text.trim(),
        'calories': double.tryParse(caloriesController.text.trim()) ?? 0.0,
        'carbs': double.tryParse(carbsController.text.trim()) ?? 0.0,
        'protein': double.tryParse(proteinController.text.trim()) ?? 0.0,
        'fat': double.tryParse(fatController.text.trim()) ?? 0.0,
        'imageUrl': imageUrl,
        'imagePath': imagePath,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Database write timeout - Check Firestore rules!');
        },
      );

      debugPrint('Food added successfully');
      _updateStatus('Success!');

      if (!mounted) return;

      nameController.clear();
      portionController.clear();
      caloriesController.clear();
      carbsController.clear();
      proteinController.clear();
      fatController.clear();

      if (mounted) {
        setState(() {
          _selectedImage = null;
          _webImage = null;
          category = "Do";
          _isUploading = false;
          _uploadStatus = '';
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Food added successfully! Users can now see it."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        )
      );
    } catch (e) {
      debugPrint('Error adding food: $e');
      _updateStatus('Error: $e');

      if (!mounted) return;

      String errorMsg = e.toString();
      if (errorMsg.contains('permission') || errorMsg.contains('PERMISSION_DENIED')) {
        errorMsg = '❌ Permission denied. Check Firestore security rules!';
      } else if (errorMsg.contains('timeout')) {
        errorMsg = '❌ Connection timeout. Check your internet!';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        )
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _deleteFood(String docId, String imageUrl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Food"),
        content: const Text("Are you sure you want to delete this food?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await FirebaseFirestore.instance.collection('food_rules').doc(docId).delete();

      if (imageUrl.isNotEmpty) {
        try {
          final filePath = _extractSupabasePath(imageUrl, bucket: 'food_images');
          await SupabaseConfig.client.storage.from('food_images').remove([filePath]);
        } catch (e) {
          debugPrint('Could not delete image from Supabase: $e');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Food deleted successfully")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
    }
  }

  Future<void> _deleteUser(String userId, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ Confirm Delete"),
        content: Text(
          "Delete user '$email' permanently?\n\n"
          "⚠️ WARNING: This will delete:\n"
          "• User account from Firestore\n"
          "• All their food logs\n"
          "• All their data\n\n"
          "This action CANNOT be undone!",
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Deleting user...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      debugPrint('🗑️ Starting user deletion for: $userId ($email)');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        debugPrint('⚠️ User document does not exist in Firestore!');
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ User not found in database"),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      debugPrint('✅ User document found');

      debugPrint('📝 Checking food logs...');
      final foodLogsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('foodLogs')
          .get();

      debugPrint('Found ${foodLogsSnapshot.docs.length} food logs to delete');

      if (foodLogsSnapshot.docs.isNotEmpty) {
        WriteBatch batch = FirebaseFirestore.instance.batch();
        int count = 0;

        for (var doc in foodLogsSnapshot.docs) {
          batch.delete(doc.reference);
          count++;

          if (count >= 500) {
            await batch.commit();
            debugPrint('Batch committed: $count items');
            batch = FirebaseFirestore.instance.batch();
            count = 0;
          }
        }

        if (count > 0) {
          await batch.commit();
          debugPrint('Final batch committed: $count items');
        }

        debugPrint('✅ All food logs deleted');
      }

      debugPrint('👤 Deleting user document from Firestore...');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .delete();

      debugPrint('✅ User document deleted from Firestore');

      final verifyDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (verifyDoc.exists) {
        throw Exception('User still exists after deletion attempt!');
      }

      debugPrint('✅ Deletion verified - user no longer exists');

      if (!mounted) return;
      Navigator.of(context).pop();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("✅ User '$email' deleted successfully"),
              const SizedBox(height: 4),
              const Text(
                "User removed from Firestore and Authentication",
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      debugPrint('✅ User deletion complete');
    } catch (e, stackTrace) {
      debugPrint('❌ Error deleting user: $e');
      debugPrint('Stack trace: $stackTrace');

      if (!mounted) return;
      Navigator.of(context).pop();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Failed to delete user: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 160,
      height: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.9), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: Colors.white, size: 36),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 Dashboard Overview',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 20),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'user').snapshots(),
            builder: (context, userSnap) {
              if (!userSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              
              final users = userSnap.data!.docs;
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              
              // Calculate actual active users today
              int activeToday = 0;
              for (var user in users) {
                final data = user.data() as Map<String, dynamic>;
                final lastLogin = data['lastLogin'];
                if (lastLogin != null) {
                  final loginDate = (lastLogin as Timestamp).toDate();
                  if (loginDate.year == today.year && 
                      loginDate.month == today.month && 
                      loginDate.day == today.day) {
                    activeToday++;
                  }
                }
              }
              
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collectionGroup('foodLogs').snapshots(),
                builder: (context, logSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('food_rules').snapshots(),
                    builder: (context, foodSnap) {
                      final userCount = userSnap.hasData ? userSnap.data!.docs.length : 0;
                      final logCount = logSnap.hasData ? logSnap.data!.docs.length : 0;
                      final foodCount = foodSnap.hasData ? foodSnap.data!.docs.length : 0;

                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _statCard('Total Users', '$userCount', Icons.people, Colors.blue),
                          _statCard('Food Logs', '$logCount', Icons.restaurant, Colors.orange),
                          _statCard('Food Items', '$foodCount', Icons.fastfood, Colors.green),
                          _statCard('Active Today', '$activeToday', Icons.trending_up, Colors.purple),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),

          const SizedBox(height: 30),

          const Text(
            '📈 Users by Diabetes Type',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'user').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = snap.data!.docs;
              int mild = 0, moderate = 0, severe = 0, notSpecified = 0;

              for (var user in users) {
                final type = (user.data() as Map<String, dynamic>)['diabetesType'] ?? 'Not specified';
                if (type == 'Mild') mild++;
                else if (type == 'Moderate') moderate++;
                else if (type == 'Severe') severe++;
                else notSpecified++;
              }

              return Column(
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _diabetesTypeRow('Mild', mild, Colors.green),
                          const Divider(),
                          _diabetesTypeRow('Moderate', moderate, Colors.orange),
                          const Divider(),
                          _diabetesTypeRow('Severe', severe, Colors.red),
                          if (notSpecified > 0) ...[
                            const Divider(),
                            _diabetesTypeRow('Not Specified', notSpecified, Colors.grey),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildDiabetesBarChart(mild, moderate, severe, notSpecified),
                ],
              );
            },
          ),

          const SizedBox(height: 30),

          const Text(
            '🍎 Food Database Statistics',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('food_rules').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final foods = snap.data!.docs;
              int doCount = 0, dontCount = 0;

              for (var food in foods) {
                final category = (food.data() as Map<String, dynamic>)['category'];
                if (category == 'Do') doCount++;
                else if (category == "Don't") dontCount++;
              }

              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _miniStatCard('✅ Recommended', '$doCount', Colors.green),
                          _miniStatCard('🚫 To Avoid', '$dontCount', Colors.red),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: foods.isNotEmpty ? doCount / foods.length : 0,
                        backgroundColor: Colors.red.shade100,
                        valueColor: AlwaysStoppedAnimation(Colors.green),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${foods.isNotEmpty ? ((doCount / foods.length) * 100).toStringAsFixed(1) : 0}% foods are recommended for diabetics',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 30),

          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DoDontFoodsScreen(
                    title: "Recent User Activity",
                    foodCards: [],
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🕒 Recent User Activity',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Color(0xFF2C6E49),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collectionGroup('foodLogs')
                        .orderBy('timestamp', descending: true)
                        .limit(5)
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final logs = snap.data!.docs;
                      if (logs.isEmpty) {
                        return const Text(
                          'No recent activity found',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        );
                      }

                      return Column(
                        children: logs.map((logDoc) {
                          final logData = logDoc.data() as Map<String, dynamic>;
                          final foodName = logData['foodName'] ?? 'Unknown food';
                          final timestamp = (logData['timestamp'] as Timestamp?)?.toDate();
                          final timeAgo = timestamp != null 
                              ? _formatTimeAgo(timestamp)
                              : 'Unknown time';
                          
                          // Get user info from the parent document
                          final userId = logDoc.reference.parent.parent?.id;
                          String userName = 'Unknown User';
                          
                          if (userId != null) {
                            // We can cache user info to avoid multiple reads
                            return FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(userId)
                                  .get(),
                              builder: (context, userSnap) {
                                if (userSnap.hasData && userSnap.data != null) {
                                  final userData = userSnap.data!.data() as Map<String, dynamic>?;
                                  userName = userData?['displayName'] ?? 
                                              userData?['name'] ?? 
                                              userData?['email'] ?? 
                                              'Unknown User';
                                }
                                
                                return _buildActivityItem(
                                  icon: Icons.restaurant,
                                  userName: userName,
                                  action: 'logged food: $foodName',
                                  timeAgo: timeAgo,
                                  iconColor: Colors.orange,
                                );
                              },
                            );
                          }
                          
                          return _buildActivityItem(
                            icon: Icons.restaurant,
                            userName: userName,
                            action: 'logged food: $foodName',
                            timeAgo: timeAgo,
                            iconColor: Colors.orange,
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          const Text(
            '⚙️ System Health',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _systemHealthRow('Database Status', 'Connected', Icons.check_circle, Colors.green),
                  const Divider(),
                  _systemHealthRow('Storage Status', 'Active', Icons.cloud_done, Colors.blue),
                  const Divider(),
                  _systemHealthRow('Last Backup', 'Today', Icons.backup, Colors.orange),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiabetesBarChart(int mild, int moderate, int severe, int notSpecified) {
    final total = mild + moderate + severe + notSpecified;
    if (total == 0) return const SizedBox();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Distribution Chart',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildBar('Mild', mild, total, Colors.green),
            const SizedBox(height: 8),
            _buildBar('Moderate', moderate, total, Colors.orange),
            const SizedBox(height: 8),
            _buildBar('Severe', severe, total, Colors.red),
            if (notSpecified > 0) ...[
              const SizedBox(height: 8),
              _buildBar('Not Specified', notSpecified, total, Colors.grey),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBar(String label, int count, int total, Color color) {
    final percentage = total > 0 ? (count / total) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text('$count (${(percentage * 100).toStringAsFixed(0)}%)', 
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 12,
          ),
        ),
      ],
    );
  }

  Widget _miniStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemHealthRow(String label, String status, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diabetesTypeRow(String type, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              type,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '$count users',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${(difference.inDays / 7).floor()}w ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildUsersPage() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                onChanged: (value) => setState(() => searchQuery = value.toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search users by name or email...',
                  prefixIcon: const Icon(Icons.search, color: Colors.green),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              
              // Diabetes Type Filter Chips
              const SizedBox(height: 16),
              const Text(
                'Filter by Diabetes Type:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.start,
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _selectedUserDiabetesType == 'All',
                    onSelected: (selected) => setState(() => _selectedUserDiabetesType = 'All'),
                    backgroundColor: _selectedUserDiabetesType == 'All' ? Colors.green : Colors.grey.shade200,
                    selectedColor: Colors.white,
                  ),
                  FilterChip(
                    label: const Text('Mild'),
                    selected: _selectedUserDiabetesType == 'Mild',
                    onSelected: (selected) => setState(() => _selectedUserDiabetesType = 'Mild'),
                    backgroundColor: _selectedUserDiabetesType == 'Mild' ? Colors.green : Colors.grey.shade200,
                    selectedColor: Colors.white,
                  ),
                  FilterChip(
                    label: const Text('Moderate'),
                    selected: _selectedUserDiabetesType == 'Moderate',
                    onSelected: (selected) => setState(() => _selectedUserDiabetesType = 'Moderate'),
                    backgroundColor: _selectedUserDiabetesType == 'Moderate' ? Colors.orange : Colors.grey.shade200,
                    selectedColor: Colors.white,
                  ),
                  FilterChip(
                    label: const Text('Severe'),
                    selected: _selectedUserDiabetesType == 'Severe',
                    onSelected: (selected) => setState(() => _selectedUserDiabetesType = 'Severe'),
                    backgroundColor: _selectedUserDiabetesType == 'Severe' ? Colors.red : Colors.grey.shade200,
                    selectedColor: Colors.white,
                  ),
                  FilterChip(
                    label: const Text('Not Specified'),
                    selected: _selectedUserDiabetesType == 'Not Specified',
                    onSelected: (selected) => setState(() => _selectedUserDiabetesType = 'Not Specified'),
                    backgroundColor: _selectedUserDiabetesType == 'Not Specified' ? Colors.grey : Colors.grey.shade200,
                    selectedColor: Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'user')
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snap.hasError) {
                return Center(child: Text("Error: ${snap.error}"));
              }

              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const Center(child: Text("No users found"));
              }

              var docs = snap.data!.docs;

              // Apply diabetes type filter
              if (_selectedUserDiabetesType != 'All') {
                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final diabetesType = data['diabetesType'] ?? 'Not specified';
                  return diabetesType == _selectedUserDiabetesType;
                }).toList();
              }

              if (searchQuery.isNotEmpty) {
                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  return name.contains(searchQuery) || email.contains(searchQuery);
                }).toList();
              }

              if (docs.isEmpty) {
                return const Center(child: Text("No users match your search"));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name'] ?? 'No Name';
                  final email = data['email'] ?? 'No Email';
                  final diabetesType = data['diabetesType'] ?? 'Not specified';
                  final age = data['age'] ?? 'N/A';

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.shade100,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.monitor_heart, size: 14, color: Colors.red),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  "Type: $diabetesType",
                                  style: TextStyle(
                                    color: diabetesType == 'Not specified' ? Colors.red : Colors.black,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.cake, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                "Age: $age",
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'viewLogs') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserFoodLogScreen(
                                  userId: doc.id,
                                  userName: name,
                                ),
                              ),
                            );
                          } else if (value == 'editUser') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditUserScreen(
                                  userId: doc.id,
                                  userData: data,
                                ),
                              ),
                            );
                          } else if (value == 'deleteUser') {
                            _deleteUser(doc.id, email);
                          }
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(
                            value: 'viewLogs',
                            child: Row(
                              children: [
                                Icon(Icons.restaurant, size: 18, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('View Food Logs'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'editUser',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18, color: Colors.orange),
                                SizedBox(width: 8),
                                Text('Edit User'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'deleteUser',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete User'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFoodDataPage() {
    final foodsStream = FirebaseFirestore.instance
        .collection('food_rules')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            'Add New Food',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 8),
          const Text(
            'Foods will appear in user Do/Don\'t screen',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),

          GestureDetector(
            onTap: _isUploading ? null : _pickImage,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isUploading ? Colors.grey : Colors.green,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
                color: _isUploading ? Colors.grey.shade200 : Colors.white,
              ),
              child: _selectedImage != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(_selectedImage!, fit: BoxFit.cover, width: 200, height: 200),
                        ),
                        if (!_isUploading)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.check, color: Colors.white, size: 16),
                            ),
                          ),
                      ],
                    )
                  : _webImage != null
                      ? Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(_webImage!, fit: BoxFit.cover, width: 200, height: 200),
                            ),
                            if (!_isUploading)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                                ),
                              ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo,
                              color: _isUploading ? Colors.grey : Colors.green,
                              size: 56,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isUploading ? 'Processing...' : 'Tap to add image (optional)',
                              style: TextStyle(
                                color: _isUploading ? Colors.grey : Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
            ),
          ),

          if (_uploadStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _uploadStatus,
                style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold),
              ),
            ),

          const SizedBox(height: 14),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _foodField(Icons.restaurant, 'Food Name*', nameController),
              _foodField(Icons.scale, 'Portion Size*', portionController),
              _foodField(Icons.local_fire_department, 'Calories', caloriesController, isNumber: true),
              _foodField(Icons.bubble_chart, 'Carbs (g)', carbsController, isNumber: true),
              _foodField(Icons.fitness_center, 'Protein (g)', proteinController, isNumber: true),
              _foodField(Icons.opacity, 'Fat (g)', fatController, isNumber: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Category: ", style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: category,
                items: const [
                  DropdownMenuItem(value: 'Do', child: Text('✅ Do (Recommended)')),
                  DropdownMenuItem(value: "Don't", child: Text("❌ Don't (Avoid)")),
                ],
                onChanged: _isUploading ? null : (val) => setState(() => category = val ?? 'Do'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _clearForm,
                icon: const Icon(Icons.clear_all, color: Colors.orange),
                label: const Text('Clear Form', style: TextStyle(color: Colors.orange)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orange),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _addFood,
                icon: _isUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add),
                label: Text(_isUploading ? 'Adding...' : 'Add Food'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isUploading ? Colors.grey : Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                ),
              ),
            ],
          ),

          const SizedBox(height: 26),
          const Divider(),
          const SizedBox(height: 6),

          StreamBuilder<QuerySnapshot>(
            stream: foodsStream,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Text('No foods yet');

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final imageUrl = (data['imageUrl'] ?? data['imagePath'] ?? '') as String;

                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminFoodDetailScreen(foodId: doc.id),
                          ),
                        );
                      },
                      leading: imageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                imageUrl,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: Colors.green, size: 40),
                              ),
                            )
                          : const Icon(Icons.fastfood, color: Colors.green, size: 40),
                      title: Text(data['name'] ?? 'Unnamed', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${data['category'] ?? '?'}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteFood(doc.id, imageUrl),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _foodField(IconData icon, String hint, TextEditingController controller, {bool isNumber = false}) {
    return SizedBox(
      width: 170,
      child: TextField(
        enabled: !_isUploading,
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _isUploading ? Colors.grey : Colors.green),
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
          filled: true,
          fillColor: _isUploading ? Colors.grey.shade100 : Colors.white,
        ),
      ),
    );
  }

  Widget _buildReportsPage() {
    return const Center(
      child: Text('Reports Page - Coming Soon', style: TextStyle(fontSize: 18)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildDashboardPage(),
      _buildUsersPage(),
      _buildFoodDataPage(),
      AdminReportsScreen(),
    ];

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          centerTitle: true,
          backgroundColor: Colors.green,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => _confirmLogout(context),
            ),
          ],
        ),
        body: pages[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.green,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          onTap: (i) => setState(() => _selectedIndex = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Users'),
            BottomNavigationBarItem(icon: Icon(Icons.restaurant_menu), label: 'Food Data'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Reports'),
          ],
        ),
        backgroundColor: Colors.green.shade50,
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildActivityItem({
    required IconData icon,
    required String userName,
    required String action,
    required String timeAgo,
    required Color iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  action,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            timeAgo,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTypeSection(String title, List<Map<String, dynamic>> users, Color color) {
    // Convert to MaterialColor for shade access
    final materialColor = color == Colors.green ? Colors.green :
                        color == Colors.orange ? Colors.orange :
                        color == Colors.red ? Colors.red :
                        Colors.grey;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Text(
              '$title (${users.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: materialColor.shade700,
              ),
            ),
          ),
          
          // Users List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = users[index];
              final name = user['name'] ?? 'Unknown';
              final email = user['email'] ?? '';
              final age = user['age']?.toString() ?? 'N/A';
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: materialColor.shade700,
                    ),
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Age: $age',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        title.split(' ')[1], // Extract "Mild", "Moderate", etc.
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: materialColor.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}