import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image_picker/image_picker.dart';

class FoodScannerScreen extends StatefulWidget {
  const FoodScannerScreen({Key? key}) : super(key: key);

  @override
  State<FoodScannerScreen> createState() => _FoodScannerScreenState();
}

class _FoodScannerScreenState extends State<FoodScannerScreen> {
  String _detectedFood = '';
  Map<String, dynamic>? _nutritionInfo;
  bool _isLoading = false;

  final picker = ImagePicker();

  Map<String, dynamic> _foodDatabase = {};

  @override
  void initState() {
    super.initState();
    _loadFoodDatabase();
  }

  Future<void> _loadFoodDatabase() async {
    final snapshot = await FirebaseFirestore.instance.collection('diabetic_foods').get();
    final data = <String, Map<String, dynamic>>{};
    for (var doc in snapshot.docs) {
      data[doc.id.toLowerCase()] = doc.data();
    }
    setState(() {
      _foodDatabase = data;
    });
  }

  final Map<String, String> labelMapping = {
    'soft drink': 'Soft Drinks',
    'cola': 'Soft Drinks',
    'soda': 'Soft Drinks',
    'apple': 'Apple (Raw)',
    'red apple': 'Apple (Raw)',
    'green apple': 'Apple (Raw)',
    'chicken': 'Chicken Breast (Raw)',
    'tofu': 'Firm Tofu (Tokwa)',
    'tokwa': 'Firm Tofu (Tokwa)',
    'rice': 'White Rice',
    'spaghetti': 'Filipino Spaghetti',
    'turon': 'Turon',
    'bibingka': 'Bibingka',
  };

  final List<String> nonFoodLabels = ['hand', 'person', 'skin', 'table'];

  Future<void> _scanImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;

    setState(() {
      _isLoading = true;
      _detectedFood = '';
      _nutritionInfo = null;
    });

    try {
      final inputImage = InputImage.fromFile(File(pickedFile.path));
      final imageLabeler = ImageLabeler(
        options: ImageLabelerOptions(confidenceThreshold: 0.3),
      );

      final labels = await imageLabeler.processImage(inputImage);
      await imageLabeler.close();

      String? matchedFood;
      Map<String, dynamic>? foodData;

      for (final label in labels) {
        final original = label.label.toLowerCase();
        if (nonFoodLabels.contains(original)) continue;

        // Step 1: Use labelMapping
        final mapped = labelMapping[original] ?? _capitalizeWords(original);

        // Step 2: Try exact match
        foodData = _foodDatabase[mapped.toLowerCase()];
        if (foodData != null) {
          matchedFood = mapped;
          break;
        }

        // Step 3: Try partial fuzzy match (contains)
        for (var key in _foodDatabase.keys) {
          if (key.contains(original)) {
            matchedFood = _capitalizeWords(key);
            foodData = _foodDatabase[key];
            break;
          }
        }

        if (matchedFood != null) break;
      }

      setState(() {
        _detectedFood = matchedFood ?? 'Food not recognized';
        _nutritionInfo = foodData;
        _isLoading = false;
      });

      if (matchedFood != null && foodData != null) {
        await _saveFoodToFirestore(matchedFood, foodData);
      }
    } catch (e) {
      debugPrint('Error: $e');
      setState(() {
        _detectedFood = 'Error occurred';
        _isLoading = false;
      });
    }
  }

  String _capitalizeWords(String text) {
    return text
        .split(' ')
        .map((word) =>
            word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
        .join(' ');
  }

  Future<void> _saveFoodToFirestore(
      String foodName, Map<String, dynamic> nutrition) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final foodData = {
      'name': foodName,
      'timestamp': FieldValue.serverTimestamp(),
      'nutrition': nutrition,
    };

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('scanned_foods')
        .add(foodData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Food Scanner')),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/scan.png', fit: BoxFit.cover),
          ),
          Center(
            child: _isLoading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _detectedFood.isEmpty
                            ? 'No food detected yet'
                            : 'Detected: $_detectedFood',
                        style: const TextStyle(fontSize: 20, color: Colors.white),
                      ),
                      if (_nutritionInfo != null)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Calories: ${_nutritionInfo!['calories']} kcal', style: const TextStyle(color: Colors.white)),
                              Text('Carbs: ${_nutritionInfo!['carbs']} g', style: const TextStyle(color: Colors.white)),
                              Text('Sugar: ${_nutritionInfo!['sugar']} g', style: const TextStyle(color: Colors.white)),
                              Text('Protein: ${_nutritionInfo!['protein']} g', style: const TextStyle(color: Colors.white)),
                              Text('Fat: ${_nutritionInfo!['fat']} g', style: const TextStyle(color: Colors.white)),
                              Text(
                                'Diabetic Friendly: ${_nutritionInfo!['isDiabeticFriendly'] ? "Yes" : "No"}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _scanImage,
                        child: const Text('Scan Food'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
