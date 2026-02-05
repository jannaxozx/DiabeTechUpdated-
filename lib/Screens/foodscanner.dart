import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/nutrition_service.dart';

class FoodScannerScreen extends StatefulWidget {
  const FoodScannerScreen({Key? key}) : super(key: key);

  @override
  State<FoodScannerScreen> createState() => _FoodScannerScreenState();
}

class _FoodScannerScreenState extends State<FoodScannerScreen> {
  File? _capturedImage;
  bool _isLoading = false;

  String _detectedFood = '';
  Map<String, dynamic>? _nutritionInfo;
  String _category = 'unknown';

  final ImagePicker _picker = ImagePicker();
  final nutritionService = NutritionService();

  final List<String> nonFoodLabels = [
    'hand',
    'person',
    'skin',
    'table',
    'finger',
    'thumb',
  ];

  Future<void> _scanImage() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _capturedImage = File(pickedFile.path);
        _isLoading = true;
        _detectedFood = '';
        _nutritionInfo = null;
        _category = 'unknown';
      });

      /// 🔹 ML Kit image labeling
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final imageLabeler = ImageLabeler(
        options: ImageLabelerOptions(confidenceThreshold: 0.4),
      );

      final labels = await imageLabeler.processImage(inputImage);
      await imageLabeler.close();

      String? detectedFood;
      for (final label in labels) {
        final text = label.label.toLowerCase();
        if (!nonFoodLabels.contains(text)) {
          detectedFood = text;
          break;
        }
      }

      if (detectedFood == null) {
        _showError('Food not recognized');
        return;
      }

      final foodKey = detectedFood.toLowerCase();
      _detectedFood = _capitalizeWords(foodKey);

      /// 🔹 ONLINE nutrition API (NO Firebase)
      _nutritionInfo = await nutritionService.fetchNutrition(foodKey);
      if (_nutritionInfo == null) {
        _showError('Nutrition info not found');
        return;
      }

      /// 🔹 ADMIN DO / DON’T RULE (Firebase ONLY)
      final ruleDoc = await FirebaseFirestore.instance
          .collection('food_rules') // ✅ MATCHED
          .doc(foodKey)
          .get();

      if (ruleDoc.exists) {
        _category = ruleDoc['category'].toString().toLowerCase();
      }

      /// 🔹 SAVE SCAN HISTORY
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('scanned_foods')
            .add({
          'food': _detectedFood,
          'category': _category,
          'nutrition': _nutritionInfo,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      setState(() => _isLoading = false);
    } catch (e) {
      _showError('Error scanning image');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _capitalizeWords(String text) {
    return text
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final cat = _category;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      appBar: AppBar(
        title: const Text('Food Scanner', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2C6E49),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          if (_capturedImage != null)
            Positioned.fill(
              child: Image.file(_capturedImage!, fit: BoxFit.cover),
            )
          else
            _buildPlaceholder(),

          if (_capturedImage != null)
            Container(color: const Color.fromRGBO(0, 0, 0, 0.4)),

          Center(
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : _detectedFood.isNotEmpty
                    ? _buildResultCard(cat)
                    : const SizedBox.shrink(),
          ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C6E49),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                icon:
                    const Icon(Icons.camera_alt, size: 28, color: Colors.white),
                label: Text(
                  _detectedFood.isEmpty ? 'Scan Food' : 'Scan Again',
                  style:
                      const TextStyle(fontSize: 18, color: Colors.white),
                ),
                onPressed: _isLoading ? null : _scanImage,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Positioned.fill(
      child: Container(
        color: Colors.grey.shade200,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, size: 100, color: Colors.grey.shade400),
            const SizedBox(height: 20),
            Text(
              'Tap the button to scan your food',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(String cat) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _detectedFood,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_nutritionInfo != null) ...[
            _buildNutritionRow('Calories', '${_nutritionInfo!['calories']} kcal'),
            _buildNutritionRow('Carbs', '${_nutritionInfo!['carbs']} g'),
            _buildNutritionRow('Protein', '${_nutritionInfo!['protein']} g'),
            _buildNutritionRow('Fat', '${_nutritionInfo!['fat']} g'),
          ],
          const SizedBox(height: 12),
          Text(
            cat == 'do'
                ? '✅ Recommended for Diabetics'
                : cat == 'dont'
                    ? '⚠️ Avoid if Diabetic'
                    : 'ℹ️ No rule for this food',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 15)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
