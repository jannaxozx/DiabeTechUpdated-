import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diabetechapp/services/nutrition_service.dart';


class FoodScannerScreen extends StatefulWidget {
  const FoodScannerScreen({Key? key}) : super(key: key);

  @override
  _FoodScannerScreenState createState() => _FoodScannerScreenState();
}

class _FoodScannerScreenState extends State<FoodScannerScreen> {
  XFile? _imageFile;
  final ImagePicker _picker = ImagePicker();
 final TextRecognizer _textRecognizer = TextRecognizer();

  String scannedText = "No text detected";

  // Function to pick image from the gallery or camera
  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _imageFile = pickedFile;
      });
      _processImage(pickedFile);
    }
  }

  // Function to process the picked image and extract text or labels
  Future<void> _processImage(XFile pickedFile) async {
    final inputImage = InputImage.fromFilePath(pickedFile.path);
    final recognisedText = await _textRecognizer.processImage(inputImage);

    setState(() {
      scannedText = recognisedText.text.isEmpty
          ? "No text detected in the image."
          : recognisedText.text;
    });
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Food Scanner"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logged out successfully')),
              );
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _imageFile == null
                ? const Text("No image selected")
                : Image.file(
                    File(_imageFile!.path),
                    height: 200,
                    width: 200,
                    fit: BoxFit.cover,
                  ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pickImage,
              child: const Text("Scan Food Item"),
            ),
            const SizedBox(height: 20),
            Text(
              "Scanned Text: $scannedText",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await addNutritionAndMealData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nutrition and meal saved!')),
                );
              },
              child: const Text('Save Meal'),
            ),
          ],
        ),
      ),

    );
  }
}
