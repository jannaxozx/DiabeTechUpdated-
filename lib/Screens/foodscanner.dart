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
  File? _capturedImage;

  final ImagePicker _picker = ImagePicker();
  Map<String, dynamic> _foodDatabase = {};
  final List<String> nonFoodLabels = ['hand', 'person', 'skin', 'table'];

  @override
  void initState() {
    super.initState();
    _loadFoodDatabase();

    // Automatically take photo after the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanImageAutomatically();
    });
  }

  Future<void> _loadFoodDatabase() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('diabetic_foods').get();
    final data = <String, dynamic>{};
    for (var doc in snapshot.docs) {
      data[doc.id.toLowerCase()] = doc.data();
    }
    setState(() {
      _foodDatabase = data;
    });
  }

  Future<void> _scanImageAutomatically() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Take a picture automatically
      final pickedFile = await _picker.pickImage(source: ImageSource.camera);
      if (pickedFile == null) {
        setState(() => _isLoading = false);
        return;
      }

      _capturedImage = File(pickedFile.path);

      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final imageLabeler =
          ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.3));

      final labels = await imageLabeler.processImage(inputImage);
      await imageLabeler.close();

      String? matchedFood;
      Map<String, dynamic>? foodData;

      for (final label in labels) {
        final original = label.label.toLowerCase();
        if (nonFoodLabels.contains(original)) continue;

        foodData = _foodDatabase[original];
        if (foodData != null) {
          matchedFood = _capitalizeWords(original);
          break;
        }
      }

      if (matchedFood != null && foodData != null) {
        await _saveFoodToFirestore(matchedFood, foodData);
      }

      setState(() {
        _detectedFood = matchedFood ?? 'Food not recognized';
        _nutritionInfo = foodData;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error scanning image: $e');
      setState(() {
        _detectedFood = 'Error occurred';
        _isLoading = false;
      });
    }
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

  String _capitalizeWords(String text) {
    return text
        .split(' ')
        .map((word) =>
            word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Food Scanner')),
      body: Stack(
        children: [
          if (_capturedImage != null)
            Positioned.fill(
              child: Image.file(_capturedImage!, fit: BoxFit.cover),
            )
          else
            const Positioned.fill(
              child: ColoredBox(color: Colors.grey),
            ),
          Center(
            child: _isLoading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_detectedFood.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Detected: $_detectedFood',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold),
                              ),
                              if (_nutritionInfo != null)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Calories: ${_nutritionInfo!['calories']} kcal',
                                        style: const TextStyle(
                                            color: Colors.white)),
                                    Text(
                                        'Carbs: ${_nutritionInfo!['carbs']} g',
                                        style: const TextStyle(
                                            color: Colors.white)),
                                    Text(
                                        'Protein: ${_nutritionInfo!['protein']} g',
                                        style: const TextStyle(
                                            color: Colors.white)),
                                    Text(
                                        'Fat: ${_nutritionInfo!['fat']} g',
                                        style: const TextStyle(
                                            color: Colors.white)),
                                    Text(
                                      'Diabetic Friendly: ${_nutritionInfo!['isDiabeticFriendly'] ? "Yes" : "No"}',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ],
                                )
                            ],
                          ),
                        ),
                    ],
                  ),
          )
        ],
      ),
    );
  }
}
