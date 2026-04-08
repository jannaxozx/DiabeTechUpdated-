import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'admin_food_detail_screen.dart';
import 'admin_data_migration.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:diabetechapp/Screens/user_food_log_screen.dart';
import 'landing_page.dart';
import 'edit_user_screen.dart';
import 'admin_reports.dart';
import '../supabase_config.dart';
import '../health/nutrition_calculator.dart'; // ✅ ADD THIS

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  String searchQuery = "";
  String _selectedUserDiabetesType = 'All';
  String _filterFoodDiabetesType = 'All';

  final TextEditingController nameController = TextEditingController();
  final TextEditingController caloriesController = TextEditingController();
  final TextEditingController carbsController = TextEditingController();
  final TextEditingController proteinController = TextEditingController();
  final TextEditingController fatController = TextEditingController();

  File? _selectedImage;
  Uint8List? _webImage;

  bool _isUploading = false;
  String _uploadStatus = '';

  final ImagePicker _imagePicker = ImagePicker();

  // ── System Health state ───────────────────────────────────────────────
  bool _healthLoading = true;
  String _dbStatus = 'Checking...';
  Color _dbColor = Colors.grey;
  IconData _dbIcon = Icons.hourglass_empty;
  String _storageStatus = 'Checking...';
  Color _storageColor = Colors.grey;
  IconData _storageIcon = Icons.hourglass_empty;
  int _healthUserCount = 0;
  int _healthFoodCount = 0;
  String _lastScanTime = 'No scans yet';

  // ── Recent Activity state ─────────────────────────────────────────────
  bool _activityLoading = true;
  List<Map<String, dynamic>> _activityItems = [];

  @override
  void initState() {
    super.initState();
    _verifyAdminStatus();
    _fetchSystemHealth();
    _fetchRecentActivity();
  }

  Future<void> _verifyAdminStatus() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        debugPrint('❌ No user logged in');
        return;
      }
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
      if (!userDoc.exists) {
        debugPrint('❌ User document does not exist');
        return;
      }
      final role = userDoc.data()?['role'];
      debugPrint('✅ Current user role: $role');
      if (role != 'admin')
        debugPrint('⚠️ WARNING: User is not an admin!');
      else
        debugPrint('✅ Admin verified successfully');
    } catch (e) {
      debugPrint('❌ Error verifying admin status: $e');
    }
  }

  // ── Fetch recent activity (scans + meal logs merged) ────────────────
  Future<void> _fetchRecentActivity() async {
    if (!mounted) return;
    setState(() => _activityLoading = true);

    try {
      // NO .orderBy() on collectionGroup — avoids requiring Firestore indexes.
      // Fetch more docs and sort in code instead.
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collectionGroup('scanned_foods')
            .limit(30)
            .get(),
        FirebaseFirestore.instance.collectionGroup('foodLogs').limit(30).get(),
      ]);

      final scanDocs = results[0].docs;
      final logDocs = results[1].docs;

      // Collect unique user IDs for batch fetch
      final userIds = <String>{};
      for (final d in [...scanDocs, ...logDocs]) {
        final uid = d.reference.parent.parent?.id;
        if (uid != null) userIds.add(uid);
      }

      // Batch fetch user names
      final userNames = <String, String>{};
      await Future.wait(
        userIds.map((uid) async {
          try {
            final doc =
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .get();
            final data = doc.data();
            userNames[uid] = data?['name'] ?? data?['email'] ?? 'Unknown';
          } catch (_) {
            userNames[uid] = 'Unknown';
          }
        }),
      );

      // Build unified list
      final items = <Map<String, dynamic>>[];

      for (final doc in scanDocs) {
        final data = doc.data();
        final uid = doc.reference.parent.parent?.id ?? '';
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        items.add({
          'type': 'scan',
          'food': data['food'] ?? data['foodName'] ?? 'Unknown food',
          'category': data['category'] ?? 'unknown',
          'userName': userNames[uid] ?? 'Unknown',
          'timestamp': ts,
        });
      }

      for (final doc in logDocs) {
        final data = doc.data();
        final uid = doc.reference.parent.parent?.id ?? '';
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        items.add({
          'type': 'log',
          'food': data['foodName'] ?? 'Unknown food',
          'mealType': data['mealType'] ?? '',
          'userName': userNames[uid] ?? 'Unknown',
          'timestamp': ts,
        });
      }

      // Sort merged list newest first, take top 10
      items.sort((a, b) {
        final aTs = a['timestamp'] as DateTime?;
        final bTs = b['timestamp'] as DateTime?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });

      if (mounted) {
        setState(() {
          _activityItems = items.take(10).toList();
          _activityLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Activity fetch error: $e');
      if (mounted) setState(() => _activityLoading = false);
    }
  }

  // ── Fetch real system health data ───────────────────────────────────
  Future<void> _fetchSystemHealth() async {
    if (!mounted) return;
    setState(() => _healthLoading = true);

    // 1. Ping Firestore (database status)
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 6));
      if (mounted)
        setState(() {
          _dbStatus = 'Connected';
          _dbColor = Colors.green;
          _dbIcon = Icons.check_circle;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _dbStatus = 'Unreachable';
          _dbColor = Colors.red;
          _dbIcon = Icons.error;
        });
    }

    // 2. Ping Supabase storage (storage status)
    try {
      await SupabaseConfig.client.storage
          .from('food_images')
          .list(path: '', searchOptions: const SearchOptions(limit: 1))
          .timeout(const Duration(seconds: 6));
      if (mounted)
        setState(() {
          _storageStatus = 'Active';
          _storageColor = Colors.blue;
          _storageIcon = Icons.cloud_done;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _storageStatus = 'Unavailable';
          _storageColor = Colors.orange;
          _storageIcon = Icons.cloud_off;
        });
    }

    // 3. Live user + food counts
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'user')
            .count()
            .get(),
        FirebaseFirestore.instance.collection('food_rules').count().get(),
      ]);
      if (mounted)
        setState(() {
          _healthUserCount = results[0].count ?? 0;
          _healthFoodCount = results[1].count ?? 0;
        });
    } catch (e) {
      debugPrint('Health count error: $e');
    }

    // 4. Most recent scan across all users (no orderBy — no index needed)
    try {
      final scanSnap =
          await FirebaseFirestore.instance
              .collectionGroup('scanned_foods')
              .limit(50)
              .get();
      DateTime? latestTs;
      for (final doc in scanSnap.docs) {
        final ts = (doc['timestamp'] as Timestamp?)?.toDate();
        if (ts != null && (latestTs == null || ts.isAfter(latestTs))) {
          latestTs = ts;
        }
      }
      if (latestTs != null && mounted) {
        setState(() => _lastScanTime = _formatTimeAgo(latestTs!));
      }
    } catch (e) {
      debugPrint('Last scan error: $e');
    }

    if (mounted) setState(() => _healthLoading = false);
  }

  @override
  void dispose() {
    nameController.dispose();
    caloriesController.dispose();
    carbsController.dispose();
    proteinController.dispose();
    fatController.dispose();
    super.dispose();
  }

  void _updateStatus(String status) {
    debugPrint('STATUS: $status');
    if (mounted) setState(() => _uploadStatus = status);
  }

  String _extractSupabasePath(String url, {String bucket = 'food_images'}) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final pubIndex = segments.indexOf('public');
      if (pubIndex != -1 && pubIndex + 2 < segments.length) {
        return segments.sublist(pubIndex + 2).join('/');
      }
      return uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : url.split('/').last;
    } catch (e) {
      return url.split('/').last;
    }
  }

  void _clearForm() {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
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
                  caloriesController.clear();
                  carbsController.clear();
                  proteinController.clear();
                  fatController.clear();
                  setState(() {
                    _selectedImage = null;
                    _webImage = null;
                    _uploadStatus = '';
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("✅ Form cleared")),
                  );
                },
                child: const Text(
                  "Clear",
                  style: TextStyle(color: Colors.orange),
                ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Logout failed: $e")));
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("Confirm Logout"),
            content: const Text("Are you sure you want to log out?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _logout(context);
                },
                child: const Text(
                  "Logout",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _pickImage() async {
    if (kIsWeb) {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result != null && result.files.single.bytes != null) {
          setState(() {
            _webImage = result.files.single.bytes;
            _selectedImage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Image selected successfully")),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Could not pick image: $e")));
      }
    } else {
      try {
        final picked = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
        );
        if (picked != null) {
          setState(() {
            _selectedImage = File(picked.path);
            _webImage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Image selected successfully")),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Could not pick image: $e")));
      }
    }
  }

  Future<String?> _uploadImageToStorage() async {
    if (!kIsWeb && _selectedImage == null) return '';
    if (kIsWeb && _webImage == null) return '';
    try {
      _updateStatus('Uploading image to Supabase...');
      final fileName = "food_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final bucket = 'food_images';
      final client = SupabaseConfig.client;
      if (kIsWeb) {
        await client.storage
            .from(bucket)
            .uploadBinary(
              fileName,
              _webImage!,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
      } else {
        final bytes = await _selectedImage!.readAsBytes();
        await client.storage
            .from(bucket)
            .uploadBinary(
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
        errorMsg =
            '❌ Storage permission denied. Check Supabase Storage RLS/policies!';
      }
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      return null;
    }
  }

  Future<void> _addFood() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please enter a food name")),
      );
      return;
    }

    bool hasImage =
        (kIsWeb && _webImage != null) || (!kIsWeb && _selectedImage != null);

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("Confirm Add Food"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Name: $name",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
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
        ),
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
            builder:
                (ctx) => AlertDialog(
                  title: const Text("Image Upload Failed"),
                  content: const Text(
                    "Image upload failed. Continue adding food without image?",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text("Cancel"),
                    ),
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
                .createSignedUrl(imagePath, 60 * 60 * 24 * 7);
            imageUrl = signed;
          } catch (e) {
            debugPrint('Failed to create signed URL: $e');
            imageUrl = '';
          }
        }
      }

      _updateStatus('Checking admin permissions...');
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('Not logged in');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Timeout checking admin status'),
          );
      if (!userDoc.exists) throw Exception('User document not found');

      final role = userDoc.data()?['role'] ?? '';
      if (role != 'admin')
        throw Exception('You are not an admin. Your role: $role');

      _updateStatus('Saving to database...');

      // Get nutrition values
      final calories = double.tryParse(caloriesController.text.trim()) ?? 0.0;
      final carbs = double.tryParse(carbsController.text.trim()) ?? 0.0;
      final protein = double.tryParse(proteinController.text.trim()) ?? 0.0;
      final fat = double.tryParse(fatController.text.trim()) ?? 0.0;

      // Auto-determine suitable diabetes types
      final suitableTypes = FoodCategoryHelper.determineSuitableTypes(carbs);

      // Auto-calculate categories for each diabetes type
      final Map<String, String> categories = {};
      for (final type in ['Mild', 'Severe']) {
        categories[type] = FoodCategoryHelper.determineCategory(carbs, type);
      }

      // Auto-calculate portion sizes for each diabetes type
      final Map<String, String> portionSizes = {};
      for (final type in ['Mild', 'Severe']) {
        final grams = NutritionCalculator.recommendedGrams(
          heightCm: 160,
          weightKg: 60,
          activityLevel: 'Light',
          diabetesType: type,
          calories100g: calories,
          carbs100g: carbs,
        );
        portionSizes[type] = PortionDescriptionHelper.gramsToHumanPortion(
          grams,
          name,
        );
      }

      debugPrint('=== SAVING FOOD (Admin Dashboard) ===');
      debugPrint('Name: $name');
      debugPrint('Carbs: ${carbs}g per 100g');
      debugPrint('Suitable for: $suitableTypes');
      debugPrint('Categories: $categories');
      debugPrint('Portion sizes: $portionSizes');
      debugPrint('======================================');

      await FirebaseFirestore.instance
          .collection('food_rules')
          .doc(name.toLowerCase()) // ✅ Use food name as document ID
          .set({
            'name': name,
            'nameLower': name.toLowerCase().trim(),
            'searchKeywords': _buildKeywords(name),
            'calories': calories,
            'carbs': carbs,
            'protein': protein,
            'fat': fat,
            'imageUrl': imageUrl,
            'imagePath': imagePath,
            'suitableFor': suitableTypes, // ✅ NEW STRUCTURE
            'categories': categories, // ✅ NEW STRUCTURE
            'portionSizes': portionSizes, // ✅ NEW STRUCTURE
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(
            const Duration(seconds: 15),
            onTimeout:
                () =>
                    throw Exception(
                      'Database write timeout - Check Firestore rules!',
                    ),
          );

      _updateStatus('Success!');
      if (!mounted) return;

      nameController.clear();
      caloriesController.clear();
      carbsController.clear();
      proteinController.clear();
      fatController.clear();

      if (mounted) {
        setState(() {
          _selectedImage = null;
          _webImage = null;
          _isUploading = false;
          _uploadStatus = '';
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "✅ Food added successfully! Category will be auto-determined for each user.",
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('Error adding food: $e');
      _updateStatus('Error: $e');
      if (!mounted) return;
      String errorMsg = e.toString();
      if (errorMsg.contains('permission') ||
          errorMsg.contains('PERMISSION_DENIED'))
        errorMsg = '❌ Permission denied. Check Firestore security rules!';
      else if (errorMsg.contains('timeout'))
        errorMsg = '❌ Connection timeout. Check your internet!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteFood(String docId, String imageUrl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("Delete Food"),
            content: const Text("Are you sure you want to delete this food?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('food_rules')
          .doc(docId)
          .delete();
      if (imageUrl.isNotEmpty) {
        try {
          final filePath = _extractSupabasePath(
            imageUrl,
            bucket: 'food_images',
          );
          await SupabaseConfig.client.storage.from('food_images').remove([
            filePath,
          ]);
        } catch (e) {
          debugPrint('Could not delete image from Supabase: $e');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Food deleted successfully")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // _deleteUser — calls Cloud Function which deletes BOTH Firestore AND
  //               Firebase Authentication. User cannot log in afterwards.
  // ══════════════════════════════════════════════════════════════════════
  Future<void> _deleteUser(String userId, String name) async {
    // Step 1: Confirmation dialog
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
                SizedBox(width: 8),
                Text(
                  'Delete User',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    children: [
                      const TextSpan(
                        text: 'You are about to permanently delete ',
                      ),
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: '\'s account.'),
                    ],
                  ),
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
                    '⚠️ This will remove the user from:\n'
                    '• Firebase Authentication (cannot log in)\n'
                    '• Firestore (all their data deleted)\n\n'
                    'This action CANNOT be undone.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Delete Permanently',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );

    if (ok != true || !mounted) return;

    // Step 2: Loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
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
      // Delete Firestore sub-collections first
      final db = FirebaseFirestore.instance;
      for (final sub in ['foodLogs', 'mealLogs', 'scannedFoods']) {
        final snap =
            await db.collection('users').doc(userId).collection(sub).get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
      }

      // Delete Firestore user document
      await db.collection('users').doc(userId).delete();

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("✅ '$name' deleted successfully"),
              const SizedBox(height: 4),
              const Text(
                "Account data removed. User is blocked from logging in.",
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  List<String> _buildKeywords(String name) {
    final nameLower = name.toLowerCase().trim();
    final nameWords = nameLower.split(' ').where((w) => w.length > 1).toList();
    return {nameLower, ...nameWords}.toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INPUT FIELD HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD — same green gradient header + white bg as admin_reports
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashTab(),
      _usersTab(),
      _foodsTab(),
      const AdminReportsScreen(),
      const _FeedbackAdminTab(),
    ];
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: _bg,
        // ── Same gradient header style as admin_reports ─────────────────
        appBar: AppBar(
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2C6E49), Color(0xFF4A9B6F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          automaticallyImplyLeading: false,
          titleSpacing: 20,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Admin Dashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              Text(
                'DiabeTech Admin',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          actions: [
            InkWell(
              onTap: () => _confirmLogout(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        body: pages[_selectedIndex],
        // ── Bottom nav with unread badge on Feedback tab ─────────────────
        bottomNavigationBar: StreamBuilder<QuerySnapshot>(
          stream:
              FirebaseFirestore.instance
                  .collection('feedback')
                  .where('read', isEqualTo: false)
                  .snapshots(),
          builder: (context, fbSnap) {
            final unread = fbSnap.data?.docs.length ?? 0;
            return Container(
              decoration: BoxDecoration(
                color: _white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                selectedItemColor: _green,
                unselectedItemColor: _grey3,
                backgroundColor: Colors.transparent,
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedLabelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 11),
                onTap: (i) => setState(() => _selectedIndex = i),
                items: [
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard_rounded),
                    label: 'Dashboard',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.group_rounded),
                    label: 'Users',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.restaurant_menu_rounded),
                    label: 'Foods',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.bar_chart_rounded),
                    label: 'Reports',
                  ),
                  BottomNavigationBarItem(
                    icon: _badgeIcon(
                      Icons.feedback_rounded,
                      unread,
                      _selectedIndex == 4,
                    ),
                    label: 'Feedback',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1 — DASHBOARD
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1 — DASHBOARD  (redesigned)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _dashTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Welcome banner (extends AppBar gradient) ─────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2C6E49), Color(0xFF4A9B6F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: 'user')
                      .snapshots(),
              builder: (context, uSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collectionGroup('foodLogs')
                          .snapshots(),
                  builder: (context, lSnap) {
                    return StreamBuilder<QuerySnapshot>(
                      stream:
                          FirebaseFirestore.instance
                              .collection('food_rules')
                              .snapshots(),
                      builder: (context, fSnap) {
                        final users = uSnap.data?.docs ?? [];
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        int active = 0;
                        for (final u in users) {
                          final d = u.data() as Map<String, dynamic>;
                          final ll = d['lastLogin'];
                          if (ll != null && ll is Timestamp) {
                            final ld = ll.toDate();
                            if (ld.year == today.year &&
                                ld.month == today.month &&
                                ld.day == today.day)
                              active++;
                          }
                        }
                        final uC = users.length;
                        final lC = lSnap.data?.docs.length ?? 0;
                        final fC = fSnap.data?.docs.length ?? 0;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // greeting
                            const Text(
                              'Good day, Admin 👋',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Here\'s your overview',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 4 full-width stat chips
                            Row(
                              children: [
                                Expanded(
                                  child: _bannerChip(
                                    Icons.people_alt_rounded,
                                    '$uC',
                                    'Users',
                                    Colors.white,
                                    Colors.white.withOpacity(0.18),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _bannerChip(
                                    Icons.edit_note_rounded,
                                    '$lC',
                                    'Food Logs',
                                    Colors.white,
                                    Colors.white.withOpacity(0.18),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _bannerChip(
                                    Icons.restaurant_menu_rounded,
                                    '$fC',
                                    'Food Rules',
                                    Colors.white,
                                    Colors.white.withOpacity(0.18),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _bannerChip(
                                    Icons.trending_up_rounded,
                                    '$active',
                                    'Active Today',
                                    Colors.white,
                                    Colors.white.withOpacity(0.18),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Curved white body starts here
          Transform.translate(
            offset: const Offset(0, -20),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF4F7F5),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Diabetes type breakdown — visual pill bar ────────────
                    _sectionLabel('Patient Distribution'),
                    const SizedBox(height: 10),
                    StreamBuilder<QuerySnapshot>(
                      stream:
                          FirebaseFirestore.instance
                              .collection('users')
                              .where('role', isEqualTo: 'user')
                              .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData)
                          return const Center(
                            child: CircularProgressIndicator(color: _green),
                          );
                        int mild = 0, severe = 0, other = 0;
                        for (final u in snap.data!.docs) {
                          final dt =
                              (u.data()
                                  as Map<String, dynamic>)['diabetesType'] ??
                              '';
                          if (dt == 'Mild')
                            mild++;
                          else if (dt == 'Severe')
                            severe++;
                          else
                            other++;
                        }
                        final total = mild + severe + other;
                        return _card(
                          Column(
                            children: [
                              // Visual segmented bar
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  height: 12,
                                  child: Row(
                                    children: [
                                      if (mild > 0)
                                        Flexible(
                                          flex: mild,
                                          child: Container(color: _green),
                                        ),
                                      if (severe > 0)
                                        Flexible(
                                          flex: severe,
                                          child: Container(color: _red),
                                        ),
                                      if (other > 0)
                                        Flexible(
                                          flex: (other > 0 ? other : 0),
                                          child: Container(color: _grey4),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // 3 stat tiles
                              Row(
                                children: [
                                  Expanded(
                                    child: _typeTile(
                                      'Mild',
                                      mild,
                                      total,
                                      _green,
                                      _greenPal,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _typeTile(
                                      'Severe',
                                      severe,
                                      total,
                                      _red,
                                      _redPal,
                                    ),
                                  ),
                                  if (other > 0) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _typeTile(
                                        'Other',
                                        other,
                                        total,
                                        _grey3,
                                        _grey5,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),

                    // ── Food database — donut-style visual ───────────────────
                    _sectionLabel('Food Database'),
                    const SizedBox(height: 10),
                    StreamBuilder<QuerySnapshot>(
                      stream:
                          FirebaseFirestore.instance
                              .collection('food_rules')
                              .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData)
                          return const Center(
                            child: CircularProgressIndicator(color: _green),
                          );
                        int doC = 0, dontC = 0;
                        for (final f in snap.data!.docs) {
                          final cat =
                              (f.data() as Map<String, dynamic>)['category'] ??
                              '';
                          if (cat == 'Do')
                            doC++;
                          else if (cat == "Don't")
                            dontC++;
                        }
                        final total = snap.data!.docs.length;
                        final pct = total > 0 ? doC / total : 0.0;
                        return _card(
                          Row(
                            children: [
                              // Visual circle progress
                              SizedBox(
                                width: 90,
                                height: 90,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 90,
                                      height: 90,
                                      child: CircularProgressIndicator(
                                        value: pct,
                                        strokeWidth: 10,
                                        backgroundColor: _redPal,
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                              _green,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      '${(pct * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: _green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$total Total Foods',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: _grey1,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    _foodStatRow(
                                      Icons.check_circle_rounded,
                                      _green,
                                      _greenPal,
                                      'Recommended',
                                      doC,
                                    ),
                                    const SizedBox(height: 6),
                                    _foodStatRow(
                                      Icons.cancel_rounded,
                                      _red,
                                      _redPal,
                                      'To Avoid',
                                      dontC,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),

                    // ── Recent Activity — timeline style ─────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionLabel('Recent Activity'),
                        _activityLoading
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _green,
                              ),
                            )
                            : _refreshBtn(_fetchRecentActivity),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _activityLoading
                        ? _card(
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: CircularProgressIndicator(color: _green),
                            ),
                          ),
                        )
                        : _activityItems.isEmpty
                        ? _card(
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No recent activity yet',
                                style: TextStyle(color: _grey3, fontSize: 13),
                              ),
                            ),
                          ),
                        )
                        : _card(
                          Column(
                            children: [
                              // meal logs only — filter out scans
                              Builder(
                                builder: (_) {
                                  final logs =
                                      _activityItems
                                          .where(
                                            (item) => item['type'] == 'log',
                                          )
                                          .toList();
                                  if (logs.isEmpty)
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'No meal logs yet',
                                          style: TextStyle(
                                            color: _grey3,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    );
                                  return Column(
                                    children: [
                                      // legend — meal log only
                                      _legendDot(
                                        _amber,
                                        Icons.restaurant_rounded,
                                        'Meal Log',
                                      ),
                                      const SizedBox(height: 12),
                                      ...logs.asMap().entries.map((e) {
                                        final i = e.key;
                                        final item = e.value;
                                        final food = item['food'] as String;
                                        final user = item['userName'] as String;
                                        final ts =
                                            item['timestamp'] as DateTime?;
                                        final time =
                                            ts != null ? _ago(ts) : '—';
                                        final mt =
                                            item['mealType'] as String? ?? '';
                                        final badge =
                                            mt.isNotEmpty ? mt : 'Food Log';
                                        return _timelineRow(
                                          Icons.restaurant_rounded,
                                          _amber,
                                          user,
                                          food,
                                          badge,
                                          time,
                                          isLast: i == logs.length - 1,
                                        );
                                      }).toList(),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                    const SizedBox(height: 22),

                    // ── System Health — 2×2 status grid ─────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionLabel('System Health'),
                        _healthLoading
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _green,
                              ),
                            )
                            : _refreshBtn(_fetchSystemHealth),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _card(
                      Column(
                        children: [
                          _healthRow2(_dbIcon, _dbColor, 'Database', _dbStatus),
                          Divider(height: 12, color: _grey4),
                          _healthRow2(
                            _storageIcon,
                            _storageColor,
                            'Storage',
                            _storageStatus,
                          ),
                          Divider(height: 12, color: _grey4),
                          _healthRow2(
                            Icons.people_rounded,
                            _purp,
                            'Users',
                            _healthLoading
                                ? '...'
                                : '$_healthUserCount registered',
                          ),
                          Divider(height: 12, color: _grey4),
                          _healthRow2(
                            Icons.restaurant_menu_rounded,
                            _amber,
                            'Food Rules',
                            _healthLoading ? '...' : '$_healthFoodCount items',
                          ),
                          Divider(height: 12, color: _grey4),
                          _healthRow2(
                            Icons.qr_code_scanner_rounded,
                            _teal,
                            'Last Scan',
                            _healthLoading ? '...' : _lastScanTime,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dashboard-specific widgets ───────────────────────────────────────────

  /// Compact chip used inside the gradient banner
  Widget _bannerChip(
    IconData icon,
    String value,
    String label,
    Color fg,
    Color bg,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.25)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: fg, size: 18),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: fg,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: fg.withOpacity(0.85),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  /// Diabetes type tile (count + %)
  Widget _typeTile(
    String label,
    int count,
    int total,
    Color color,
    Color pal,
  ) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: BoxDecoration(
      color: pal,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _grey2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _pct(count, total),
          style: TextStyle(
            fontSize: 10,
            color: color.withOpacity(0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  /// Food stat row inside food card
  Widget _foodStatRow(
    IconData icon,
    Color color,
    Color pal,
    String label,
    int count,
  ) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: pal,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, color: color, size: 13),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label, style: const TextStyle(fontSize: 12, color: _grey2)),
      ),
      Text(
        '$count',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ],
  );

  /// Timeline-style activity row
  Widget _timelineRow(
    IconData icon,
    Color color,
    String user,
    String food,
    String badge,
    String time, {
    required bool isLast,
  }) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline line + dot
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 15),
            ),
            if (!isLast)
              Expanded(
                child: Container(
                  width: 2,
                  color: _grey4,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _grey1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(fontSize: 10, color: _grey3),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  food,
                  style: const TextStyle(fontSize: 12, color: _grey2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// Health status tile (2×2 grid)
  /// Compact health row — icon + label + status badge (right)
  Widget _healthRow2(IconData icon, Color color, String label, String status) =>
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: _grey2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.09),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.22)),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      );

  Widget _usersTab() {
    return Column(
      children: [
        Container(
          color: _bg,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            children: [
              // Search
              TextField(
                onChanged: (v) => setState(() => searchQuery = v.toLowerCase()),
                style: const TextStyle(color: _grey1, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by name or email...',
                  hintStyle: const TextStyle(color: _grey3),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: _green,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: _white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _grey4),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _grey4),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _green, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Filter dropdown
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _grey4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedUserDiabetesType,
                    isExpanded: true,
                    style: const TextStyle(color: _grey1, fontSize: 13),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _grey3,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('All Users')),
                      DropdownMenuItem(value: 'Mild', child: Text('🟢 Mild')),
                      DropdownMenuItem(
                        value: 'Severe',
                        child: Text('🔴 Severe'),
                      ),
                      DropdownMenuItem(
                        value: 'Not Specified',
                        child: Text('❓ Not Specified'),
                      ),
                    ],
                    onChanged:
                        (v) => setState(() => _selectedUserDiabetesType = v!),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('users')
                    .where('role', isEqualTo: 'user')
                    .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting)
                return const Center(
                  child: CircularProgressIndicator(color: _green),
                );
              if (snap.hasError)
                return Center(
                  child: Text(
                    'Error: ${snap.error}',
                    style: const TextStyle(color: _red),
                  ),
                );
              if (!snap.hasData || snap.data!.docs.isEmpty)
                return const Center(
                  child: Text(
                    'No users found',
                    style: TextStyle(color: _grey3),
                  ),
                );
              var docs = snap.data!.docs;
              if (_selectedUserDiabetesType != 'All') {
                docs =
                    docs.where((d) {
                      final dt =
                          (d.data() as Map<String, dynamic>)['diabetesType']
                              ?.toString() ??
                          'Not specified';
                      return dt == _selectedUserDiabetesType;
                    }).toList();
              }
              if (searchQuery.isNotEmpty) {
                docs =
                    docs.where((d) {
                      final dd = d.data() as Map<String, dynamic>;
                      return (dd['name'] ?? '')
                              .toString()
                              .toLowerCase()
                              .contains(searchQuery) ||
                          (dd['email'] ?? '').toString().toLowerCase().contains(
                            searchQuery,
                          );
                    }).toList();
              }
              if (docs.isEmpty)
                return const Center(
                  child: Text(
                    'No users match your search',
                    style: TextStyle(color: _grey3),
                  ),
                );

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name'] ?? 'No Name';
                  final email = data['email'] ?? 'No Email';
                  final dt = data['diabetesType'] ?? 'Not specified';
                  final age = data['age'] ?? 'N/A';
                  final actLevel = data['activityLevel'] ?? '';
                  final height = data['height'] ?? '';
                  final weight = data['weight'] ?? '';
                  final dtC =
                      dt == 'Mild'
                          ? _green
                          : dt == 'Severe'
                          ? _red
                          : _grey3;
                  final dtPal =
                      dt == 'Mild'
                          ? _greenPal
                          : dt == 'Severe'
                          ? _redPal
                          : _grey5;

                  return GestureDetector(
                    onTap: () => _showUserDetail(context, doc.id, name, data),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: dtPal,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: dtC,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: _grey1,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  email,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _grey3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 5,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: dtPal,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: dtC.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        dt,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: dtC,
                                        ),
                                      ),
                                    ),
                                    if (age != 'N/A')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _grey5,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          'Age $age',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: _grey2,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Chevron hint
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: _grey4,
                            size: 22,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3 — FOOD DATA
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _foodsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _sectionLabel('Add New Food'),
          const SizedBox(height: 4),
          const Text(
            "Foods appear in users' Do / Don't screen",
            style: TextStyle(fontSize: 12, color: _grey3),
          ),
          const SizedBox(height: 16),

          // Image picker
          GestureDetector(
            onTap: _isUploading ? null : _pickImage,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: _isUploading ? _grey5 : _white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isUploading ? _grey4 : _green,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child:
                  _selectedImage != null
                      ? Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              _selectedImage!,
                              fit: BoxFit.cover,
                              width: 180,
                              height: 180,
                            ),
                          ),
                          if (!_isUploading)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: _green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                        ],
                      )
                      : _webImage != null
                      ? Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(
                              _webImage!,
                              fit: BoxFit.cover,
                              width: 180,
                              height: 180,
                            ),
                          ),
                          if (!_isUploading)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: _green,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                        ],
                      )
                      : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_rounded,
                            color: _isUploading ? _grey3 : _green,
                            size: 46,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isUploading ? 'Processing...' : 'Tap to add image',
                            style: TextStyle(
                              color: _isUploading ? _grey3 : _green,
                              fontSize: 12,
                            ),
                          ),
                          const Text(
                            'optional',
                            style: TextStyle(color: _grey3, fontSize: 11),
                          ),
                        ],
                      ),
            ),
          ),

          if (_uploadStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _bluePal,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _uploadStatus,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Form
          _card(
            Column(
              children: [
                _ff(Icons.restaurant_rounded, 'Food Name*', nameController),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ff(
                        Icons.local_fire_department_rounded,
                        'Calories per 100g',
                        caloriesController,
                        isNum: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ff(
                        Icons.grain_rounded,
                        'Carbs per 100g (g)',
                        carbsController,
                        isNum: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ff(
                        Icons.fitness_center_rounded,
                        'Protein per 100g (g)',
                        proteinController,
                        isNum: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ff(
                        Icons.opacity_rounded,
                        'Fat per 100g (g)',
                        fatController,
                        isNum: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF2979C6),
                      width: 0.5,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFF2979C6),
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Enter nutrients per 100g of food. The app auto-calculates personalized portions for each user based on their height, weight, activity level & diabetes type (BMR+TDEE).',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF2979C6),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isUploading ? null : _clearForm,
                  icon: const Icon(Icons.clear_all_rounded, size: 17),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _amber,
                    side: const BorderSide(color: _amber),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _addFood,
                  icon:
                      _isUploading
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.add_rounded, size: 18),
                  label: Text(_isUploading ? 'Adding...' : 'Add Food'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isUploading ? _grey4 : _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Divider(color: _grey4),
          const SizedBox(height: 14),

          // Food list header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionLabel('Food Rules'),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _grey4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _filterFoodDiabetesType,
                    isDense: true,
                    style: const TextStyle(color: _grey1, fontSize: 12),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _grey3,
                      size: 16,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('All')),
                      DropdownMenuItem(value: 'Mild', child: Text('🟢 Mild')),
                      DropdownMenuItem(
                        value: 'Severe',
                        child: Text('🔴 Severe'),
                      ),
                    ],
                    onChanged:
                        (v) => setState(() => _filterFoodDiabetesType = v!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('food_rules')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData)
                return const Center(
                  child: CircularProgressIndicator(color: _green),
                );
              final docs =
                  snap.data!.docs.where((d) {
                    if (_filterFoodDiabetesType == 'All') return true;
                    return (d.data() as Map<String, dynamic>)['diabetesType'] ==
                        _filterFoodDiabetesType;
                  }).toList();
              if (docs.isEmpty)
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      _filterFoodDiabetesType == 'All'
                          ? 'No foods yet'
                          : 'No foods for $_filterFoodDiabetesType diabetes',
                      style: const TextStyle(color: _grey3, fontSize: 13),
                    ),
                  ),
                );
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final imgUrl =
                      (data['imageUrl'] ?? data['imagePath'] ?? '') as String;
                  final cat = (data['category'] ?? '').toString();
                  final isGood = cat == 'Do';
                  return Container(
                    decoration: BoxDecoration(
                      color: _white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                      onTap:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => AdminFoodDetailScreen(foodId: doc.id),
                            ),
                          ),
                      leading:
                          imgUrl.isNotEmpty
                              ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  imgUrl,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) => _foodImgPlaceholder(),
                                ),
                              )
                              : _foodImgPlaceholder(),
                      title: Text(
                        data['name'] ?? 'Unnamed',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _grey1,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isGood ? _greenPal : _redPal,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isGood ? '✅ Recommended' : '❌ Avoid',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isGood ? _green : _red,
                            ),
                          ),
                        ),
                      ),
                      trailing: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _redPal,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.delete_rounded,
                            color: _red,
                            size: 16,
                          ),
                        ),
                        onPressed: () => _deleteFood(doc.id, imgUrl),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED UI COMPONENTS  (identical style to admin_reports)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Section label — same as _sectionLabel in reports
  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: _grey1,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
  );

  /// White card — identical to reports _card
  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );

  /// KPI card — identical to reports _kpi
  Widget _kpi(
    String label,
    String value,
    IconData icon,
    Color color,
    Color palColor,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: palColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: _grey3,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );

  /// Horizontal bar — identical to reports _hBar
  Widget _hBar(String label, int value, int total, Color color) {
    final pct = (total > 0 ? value / total : 0.0).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _grey1,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _pct(value, total),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: _grey4,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            FractionallySizedBox(
              widthFactor: pct,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Stat row — identical to reports _sRow
  Widget _sRow(IconData icon, Color color, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: _grey2, fontSize: 13),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: _grey1,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );

  Widget _divider() => Divider(height: 1, color: _grey4);

  Widget _legendRow(List<Widget> items) =>
      Wrap(spacing: 18, runSpacing: 8, children: items);

  Widget _dot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: _grey2)),
    ],
  );

  Widget _miniStat(String label, String value, Color color, Color pal) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
        decoration: BoxDecoration(
          color: pal,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: _grey2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  Widget _typeRow(String type, int count, int total, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            type,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _grey1,
            ),
          ),
        ),
        Text(
          '$count users',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _activityRow(
    IconData icon,
    String user,
    String action,
    String time,
    Color color,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: _grey1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                action,
                style: const TextStyle(fontSize: 12, color: _grey3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(time, style: const TextStyle(fontSize: 11, color: _grey3)),
      ],
    ),
  );

  Widget _legendDot(Color color, IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: color, size: 12),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _refreshBtn(VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: _greenPal,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.refresh_rounded, color: _green, size: 16),
    ),
  );

  // ── User card action button ──────────────────────────────────────────────
  // ── User detail bottom sheet ─────────────────────────────────────────────
  void _showUserDetail(
    BuildContext context,
    String userId,
    String name,
    Map<String, dynamic> data,
  ) {
    final email = data['email'] ?? 'N/A';
    final dt = data['diabetesType'] ?? 'Not specified';
    final age = data['age']?.toString() ?? 'N/A';
    final actLevel = data['activityLevel'] ?? 'N/A';
    final height = data['height']?.toString() ?? 'N/A';
    final weight = data['weight']?.toString() ?? 'N/A';
    final dtC =
        dt == 'Mild'
            ? _green
            : dt == 'Severe'
            ? _red
            : _grey3;
    final dtPal =
        dt == 'Mild'
            ? _greenPal
            : dt == 'Severe'
            ? _redPal
            : _grey5;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => Container(
            decoration: const BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _grey4,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Avatar + name
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: dtPal,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: dtC,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _grey1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            email,
                            style: const TextStyle(fontSize: 12, color: _grey3),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: dtPal,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: dtC.withOpacity(0.3)),
                            ),
                            child: Text(
                              dt,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: dtC,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Detail rows
                Container(
                  decoration: BoxDecoration(
                    color: _grey5,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      _detailRow(Icons.cake_rounded, _purp, 'Age', age),
                      Divider(height: 1, color: _grey4),
                      _detailRow(
                        Icons.height_rounded,
                        _blue,
                        'Height',
                        '$height cm',
                      ),
                      Divider(height: 1, color: _grey4),
                      _detailRow(
                        Icons.monitor_weight_rounded,
                        _teal,
                        'Weight',
                        '$weight kg',
                      ),
                      Divider(height: 1, color: _grey4),
                      _detailRow(
                        Icons.directions_run_rounded,
                        _amber,
                        'Activity Level',
                        actLevel,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => UserFoodLogScreen(
                                    userId: userId,
                                    userName: name,
                                  ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long_rounded, size: 16),
                        label: const Text('View Logs'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _blue,
                          side: const BorderSide(color: _blue),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => EditUserScreen(
                                    userId: userId,
                                    userData: data,
                                  ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: const Text('Edit User'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteUser(userId, name);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _redPal,
                        foregroundColor: _red,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Icon(Icons.delete_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }

  Widget _detailRow(IconData icon, Color color, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 15),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: _grey2,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _grey1,
              ),
            ),
          ],
        ),
      );

  Widget _foodImgPlaceholder() => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: _greenPal,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.fastfood_rounded, color: _green, size: 24),
  );

  PopupMenuItem<String> _popItem(
    String value,
    String label,
    IconData icon,
    Color color,
    Color pal, {
    bool isDestructive = false,
  }) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: pal,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: isDestructive ? _red : _grey1, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _ff(
    IconData icon,
    String hint,
    TextEditingController ctrl, {
    bool isNum = false,
  }) => TextField(
    enabled: !_isUploading,
    controller: ctrl,
    keyboardType: isNum ? TextInputType.number : TextInputType.text,
    style: const TextStyle(color: _grey1, fontSize: 13),
    decoration: InputDecoration(
      prefixIcon: Icon(icon, color: _isUploading ? _grey3 : _green, size: 18),
      hintText: hint,
      hintStyle: const TextStyle(color: _grey3, fontSize: 12),
      filled: true,
      fillColor: _isUploading ? _grey5 : _white,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _grey4),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _grey4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _green, width: 1.5),
      ),
    ),
  );

  Widget _dropSection(String label, Widget dropdown) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: _grey2,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _grey4),
        ),
        child: dropdown,
      ),
    ],
  );

  String _pct(int n, int t) =>
      t > 0 ? '${(n / t * 100).toStringAsFixed(1)}%' : '0%';

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inDays > 0) return '${d.inDays}d ago';
    if (d.inHours > 0) return '${d.inHours}h ago';
    if (d.inMinutes > 0) return '${d.inMinutes}m ago';
    return 'Just now';
  }

  String _formatTimeAgo(DateTime dt) => _ago(dt);

  Widget _foodFieldFullWidth(
    IconData icon,
    String hint,
    TextEditingController ctrl, {
    bool isNumber = false,
  }) => _ff(icon, hint, ctrl, isNum: isNumber);

  Widget _foodField(
    IconData icon,
    String hint,
    TextEditingController ctrl, {
    bool isNumber = false,
  }) => _ff(icon, hint, ctrl, isNum: isNumber);

  /// Badge icon for bottom nav
  Widget _badgeIcon(IconData icon, int count, bool isSelected) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: _red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Palette — identical to admin_reports.dart ────────────────────────────────
const _bg = Color(0xFFF4F7F5);
const _white = Color(0xFFFFFFFF);
const _green = Color(0xFF2C6E49);
const _greenLt = Color(0xFF4A9B6F);
const _greenPal = Color(0xFFE8F5EE);
const _red = Color(0xFFD64045);
const _redPal = Color(0xFFFDECEC);
const _amber = Color(0xFFF09D18);
const _amberPal = Color(0xFFFFF4E0);
const _blue = Color(0xFF2979C6);
const _bluePal = Color(0xFFE8F0FB);
const _teal = Color(0xFF0D8A7C);
const _tealPal = Color(0xFFE3F5F3);
const _purp = Color(0xFF7B5EA7);
const _purpPal = Color(0xFFF0EBF8);
const _grey1 = Color(0xFF1A2E22);
const _grey2 = Color(0xFF4D6357);
const _grey3 = Color(0xFF8FA898);
const _grey4 = Color(0xFFD5E2DA);
const _grey5 = Color(0xFFF0F5F2);

// ─────────────────────────────────────────────────────────────────────────────
// Admin Feedback Tab — view all user feedback, mark read, send replies
// ─────────────────────────────────────────────────────────────────────────────
class _FeedbackAdminTab extends StatefulWidget {
  const _FeedbackAdminTab();

  @override
  State<_FeedbackAdminTab> createState() => _FeedbackAdminTabState();
}

class _FeedbackAdminTabState extends State<_FeedbackAdminTab> {
  String _filter = 'All'; // All | Unread | Replied | Pending

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filter bar ─────────────────────────────────────────────────
        Container(
          color: _bg,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User Feedback',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _grey1,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children:
                      ['All', 'Unread', 'Pending', 'Replied'].map((f) {
                        final sel = _filter == f;
                        return GestureDetector(
                          onTap: () => setState(() => _filter = f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: sel ? _green : _white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: sel ? _green : _grey4),
                              boxShadow:
                                  sel
                                      ? [
                                        BoxShadow(
                                          color: _green.withOpacity(0.2),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                      : [],
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                color: sel ? Colors.white : _grey2,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
            ],
          ),
        ),

        // ── Feedback list ───────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance.collection('feedback').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting)
                return const Center(
                  child: CircularProgressIndicator(color: _green),
                );
              if (snap.hasError)
                return Center(
                  child: Text(
                    'Error: ${snap.error}',
                    style: const TextStyle(color: _red),
                  ),
                );

              // Sort newest first in Dart — no index needed
              var docs = [...(snap.data?.docs ?? [])]..sort((a, b) {
                final aTs =
                    ((a.data() as Map)['timestamp'] as Timestamp?)?.toDate();
                final bTs =
                    ((b.data() as Map)['timestamp'] as Timestamp?)?.toDate();
                if (aTs == null && bTs == null) return 0;
                if (aTs == null) return 1;
                if (bTs == null) return -1;
                return bTs.compareTo(aTs);
              });

              // Apply filter
              docs =
                  docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final isRead = d['read'] == true;
                    final hasReply = (d['reply'] ?? '').toString().isNotEmpty;
                    switch (_filter) {
                      case 'Unread':
                        return !isRead;
                      case 'Pending':
                        return !hasReply;
                      case 'Replied':
                        return hasReply;
                      default:
                        return true;
                    }
                  }).toList();

              if (docs.isEmpty)
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _greenPal,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.inbox_rounded,
                          size: 40,
                          color: _green,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _filter == 'All'
                            ? 'No feedback yet'
                            : 'No $_filter feedback',
                        style: const TextStyle(color: _grey3, fontSize: 13),
                      ),
                    ],
                  ),
                );

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  return _FeedbackCard(docId: doc.id, data: data);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual feedback card with reply functionality
// ─────────────────────────────────────────────────────────────────────────────
class _FeedbackCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _FeedbackCard({required this.docId, required this.data});

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard> {
  final _replyCtrl = TextEditingController();
  bool _showReply = false;
  bool _isSending = false;

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    await FirebaseFirestore.instance
        .collection('feedback')
        .doc(widget.docId)
        .update({'read': true});
  }

  Future<void> _sendReply() async {
    final reply = _replyCtrl.text.trim();
    if (reply.isEmpty) return;
    setState(() => _isSending = true);
    try {
      final userId = widget.data['userId'] as String? ?? '';
      final now = FieldValue.serverTimestamp();

      // 1. Update the top-level feedback doc (admin collection)
      await FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.docId)
          .update({'reply': reply, 'repliedAt': now, 'read': true});

      // 2. Mirror reply to the user's own subcollection so they see it instantly
      if (userId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('feedback')
            .doc(widget.docId)
            .update({'reply': reply, 'repliedAt': now});
      }

      _replyCtrl.clear();
      if (mounted)
        setState(() {
          _showReply = false;
          _isSending = false;
        });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Reply sent to user!'),
            backgroundColor: _green,
            duration: Duration(seconds: 2),
          ),
        );
    } catch (e) {
      if (mounted) setState(() => _isSending = false);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed: $e'), backgroundColor: _red),
        );
    }
  }

  Future<void> _deleteFeedback(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.delete_forever_rounded, color: _red, size: 22),
                SizedBox(width: 8),
                Text(
                  'Delete Feedback',
                  style: TextStyle(color: _red, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            content: const Text(
              'Permanently delete this feedback message? This cannot be undone.',
              style: TextStyle(color: _grey2, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: _grey3)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
    if (ok != true) return;
    try {
      final userId = widget.data['userId'] as String? ?? '';
      // Delete from top-level collection
      await FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.docId)
          .delete();
      // Delete from user's subcollection too
      if (userId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('feedback')
            .doc(widget.docId)
            .delete();
      }
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Feedback deleted'),
            backgroundColor: _green,
            duration: Duration(seconds: 2),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed: $e'), backgroundColor: _red),
        );
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final userName = d['userName'] ?? 'Unknown User';
    final email = d['userEmail'] ?? '';
    final msg = d['message'] ?? '';
    final reply = d['reply'] ?? '';
    final diabType = d['diabetesType'] ?? '';
    final isRead = d['read'] == true;
    final hasReply = reply.toString().isNotEmpty;
    final ts = (d['timestamp'] as Timestamp?)?.toDate();
    final rTs = (d['repliedAt'] as Timestamp?)?.toDate();
    final editTs = (d['editedAt'] as Timestamp?)?.toDate();
    final dtColor =
        diabType == 'Mild'
            ? _green
            : diabType == 'Severe'
            ? _red
            : _grey3;
    final dtPal =
        diabType == 'Mild'
            ? _greenPal
            : diabType == 'Severe'
            ? _redPal
            : _grey5;

    // Auto-mark as read when visible
    if (!isRead)
      WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());

    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border:
            !isRead
                ? Border.all(color: _amber.withOpacity(0.5), width: 1.5)
                : hasReply
                ? Border.all(color: _green.withOpacity(0.2))
                : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── User info row ────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _greenPal,
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _green,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              userName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _grey1,
                              ),
                            ),
                          ),
                          // Diabetes type badge
                          if (diabType.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: dtPal,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: dtColor.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                diabType,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: dtColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: const TextStyle(fontSize: 10, color: _grey3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (ts != null)
                      Text(
                        _formatDate(ts),
                        style: const TextStyle(fontSize: 10, color: _grey3),
                      ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            !isRead
                                ? _amberPal
                                : hasReply
                                ? _greenPal
                                : _grey5,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        !isRead
                            ? '🔵 New'
                            : hasReply
                            ? '✅ Replied'
                            : '⏳ Pending',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color:
                              !isRead
                                  ? _amber
                                  : hasReply
                                  ? _green
                                  : _grey3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Message bubble ───────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _grey5,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                msg,
                style: const TextStyle(
                  fontSize: 13,
                  color: _grey1,
                  height: 1.5,
                ),
              ),
            ),
            if (editTs != null) ...[
              const SizedBox(height: 4),
              Text(
                'Edited ${_formatDate(editTs)}',
                style: const TextStyle(
                  fontSize: 9,
                  color: _grey3,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            // ── Admin reply (if exists) ───────────────────────────────
            if (hasReply) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: _grey4),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _greenPal,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: _green,
                      size: 13,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'Your reply',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _green,
                    ),
                  ),
                  const Spacer(),
                  if (rTs != null)
                    Text(
                      _formatDate(rTs),
                      style: const TextStyle(fontSize: 10, color: _grey3),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _greenPal,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _green.withOpacity(0.2)),
                ),
                child: Text(
                  reply,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _green,
                    height: 1.5,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),
            Divider(height: 1, color: _grey4),
            const SizedBox(height: 10),

            // ── Action buttons ────────────────────────────────────────
            if (!_showReply)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _showReply = true),
                      icon: Icon(
                        hasReply ? Icons.edit_rounded : Icons.reply_rounded,
                        size: 15,
                      ),
                      label: Text(
                        hasReply ? 'Edit Reply' : 'Reply',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _green,
                        side: const BorderSide(color: _green),
                        backgroundColor: _greenPal,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _deleteFeedback(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: BorderSide(color: _red.withOpacity(0.5)),
                      backgroundColor: _redPal,
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Icon(Icons.delete_rounded, size: 16),
                  ),
                ],
              )
            else ...[
              // Reply input
              TextField(
                controller: _replyCtrl,
                maxLines: 3,
                minLines: 2,
                enabled: !_isSending,
                style: const TextStyle(color: _grey1, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Type your reply to ${userName.split(' ')[0]}...',
                  hintStyle: const TextStyle(color: _grey3, fontSize: 12),
                  filled: true,
                  fillColor: _isSending ? _grey5 : _white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _grey4),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _grey4),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _green, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isSending
                              ? null
                              : () => setState(() {
                                _showReply = false;
                                _replyCtrl.clear();
                              }),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _grey3,
                        side: const BorderSide(color: _grey4),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : _sendReply,
                      icon:
                          _isSending
                              ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(
                                Icons.send_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                      label: Text(
                        _isSending ? 'Sending...' : 'Send Reply',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSending ? _grey4 : _green,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
