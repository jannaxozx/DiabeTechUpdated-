import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'admin_food_detail_screen.dart';
import '../health/nutrition_calculator.dart';

class AdminFoodRulesScreen extends StatefulWidget {
  const AdminFoodRulesScreen({Key? key}) : super(key: key);

  @override
  State<AdminFoodRulesScreen> createState() => _AdminFoodRulesScreenState();
}

class _AdminFoodRulesScreenState extends State<AdminFoodRulesScreen> {
  final TextEditingController _foodController = TextEditingController();
  final TextEditingController _caloriesController = TextEditingController();
  final TextEditingController _carbsController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  bool _isSaving = false;
  bool _isAdmin = false;
  bool _checkingAdmin = true;

  File? _selectedImage;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  /// 🔐 CHECK IF USER IS ADMIN
  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _denyAccess();
      return;
    }

    final adminDoc =
        await FirebaseFirestore.instance
            .collection('admins')
            .doc(user.uid)
            .get();

    if (adminDoc.exists) {
      setState(() {
        _isAdmin = true;
        _checkingAdmin = false;
      });
    } else {
      _denyAccess();
    }
  }

  void _denyAccess() {
    setState(() => _checkingAdmin = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Access denied: Admins only')));
    Navigator.pop(context);
  }

  /// 📷 PICK IMAGE
  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  /// ☁️ UPLOAD IMAGE TO FIREBASE STORAGE
  Future<String?> _uploadImage(String foodName) async {
    if (_selectedImage == null) return null;

    try {
      final String fileName =
          '${foodName.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference storageRef = FirebaseStorage.instance
          .ref()
          .child('food_images')
          .child(fileName);

      final UploadTask uploadTask = storageRef.putFile(_selectedImage!);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  /// ➕ SAVE FOOD WITH AUTO-CALCULATION
  Future<void> _saveFoodRule() async {
    final foodName = _foodController.text.trim();

    if (foodName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter food name')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Get nutrition values
      final calories = double.tryParse(_caloriesController.text) ?? 0;
      final carbs = double.tryParse(_carbsController.text) ?? 0;
      final protein = double.tryParse(_proteinController.text) ?? 0;
      final fat = double.tryParse(_fatController.text) ?? 0;

      // Upload image if selected
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadImage(foodName);
      }

      // Auto-determine suitable diabetes types
      final suitableTypes = FoodCategoryHelper.determineSuitableTypes(carbs);

      // Auto-calculate categories for each diabetes type
      final Map<String, String> categories = {};
      for (final type in ['Mild', 'Severe']) {
        categories[type] = FoodCategoryHelper.determineCategory(carbs, type);
      }

      // Auto-calculate portion sizes for each diabetes type
      // Using average profile: 160cm, 60kg, Light activity
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
          foodName,
        );
      }

      // DEBUG: Print what we're about to save
      debugPrint('=== SAVING FOOD ===');
      debugPrint('Name: $foodName');
      debugPrint('Carbs: ${carbs}g per 100g');
      debugPrint('Suitable for: $suitableTypes');
      debugPrint('Categories: $categories');
      debugPrint('Portion sizes: $portionSizes');
      debugPrint('==================');

      // Save to Firestore
      debugPrint('📝 Calling Firestore.set()...');
      try {
        await FirebaseFirestore.instance
            .collection('food_rules')
            .doc(foodName.toLowerCase())
            .set({
              'name': foodName,
              'nameLower':
                  foodName.toLowerCase().trim(), // ✅ ADD THIS for search
              'calories': calories,
              'carbs': carbs,
              'protein': protein,
              'fat': fat,
              'imageUrl': imageUrl ?? '',
              'suitableFor': suitableTypes,
              'categories': categories,
              'portionSizes': portionSizes,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
        debugPrint('✅ Firestore save SUCCESS!');
      } catch (e) {
        debugPrint('❌ Firestore save FAILED: $e');
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ Save failed: $e')));
        return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $foodName saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        _isSaving = false;
        _foodController.clear();
        _caloriesController.clear();
        _carbsController.clear();
        _proteinController.clear();
        _fatController.clear();
        _selectedImage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving food: $e')));
    }
  }

  /// 🗑 DELETE FOOD
  Future<void> _deleteFood(String foodName) async {
    await FirebaseFirestore.instance
        .collection('food_rules')
        .doc(foodName)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAdmin) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAdmin) {
      return const SizedBox();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin – Food Rules'),
        backgroundColor: const Color(0xFF2C6E49),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// ➕ ADD FOOD
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _foodController,
                      decoration: const InputDecoration(
                        labelText: 'Food name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    /// 📷 IMAGE PICKER
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child:
                            _selectedImage != null
                                ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    _selectedImage!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  ),
                                )
                                : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate,
                                      size: 40,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Tap to upload food image',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text(
                      'Nutrition per 100g',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C6E49),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _caloriesController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Calories (per 100g)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _carbsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Carbs (g per 100g)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _proteinController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Protein (g per 100g)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _fatController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Fat (g per 100g)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Diabetes type, category (Do/Don\'t), and portion sizes will be automatically calculated based on carb content.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveFoodRule,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2C6E49),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child:
                            _isSaving
                                ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                                : const Text('Save Food'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            /// FOOD LIST
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    FirebaseFirestore.instance
                        .collection('food_rules')
                        .orderBy('updatedAt', descending: true)
                        .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return ListView(
                    children:
                        snapshot.data!.docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final foodName = data['name'] ?? doc.id;
                          final carbs = data['carbs'] ?? 0;
                          final calories = data['calories'] ?? 0;
                          final suitableFor =
                              (data['suitableFor'] as List?)?.cast<String>() ??
                              [];
                          final categories =
                              data['categories'] as Map<String, dynamic>? ?? {};
                          final imageUrl = data['imageUrl'] ?? '';

                          return Card(
                            child: ListTile(
                              leading:
                                  imageUrl.isNotEmpty
                                      ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          imageUrl,
                                          width: 50,
                                          height: 50,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (_, __, ___) => Container(
                                                width: 50,
                                                height: 50,
                                                color: Colors.grey.shade200,
                                                child: const Icon(
                                                  Icons.fastfood,
                                                ),
                                              ),
                                        ),
                                      )
                                      : Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(Icons.fastfood),
                                      ),
                              title: Text(foodName.toString().toUpperCase()),
                              subtitle: Text(
                                '${carbs}g carbs, $calories cal per 100g\n${suitableFor.join(", ")}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Removed Do/Don't chips - not needed in admin view
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _deleteFood(doc.id),
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => AdminFoodDetailScreen(
                                          foodId: doc.id,
                                        ),
                                  ),
                                );
                              },
                            ),
                          );
                        }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
