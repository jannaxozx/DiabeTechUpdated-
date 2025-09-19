import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NutrientSummaryScreen extends StatefulWidget {
  const NutrientSummaryScreen({Key? key}) : super(key: key);

  @override
  State<NutrientSummaryScreen> createState() => _NutrientSummaryScreenState();
}

class _NutrientSummaryScreenState extends State<NutrientSummaryScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final TextEditingController foodNameController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? latestNutrition; // To hold the most recently added food's nutrition data

  Future<void> _addFoodByName(String foodName) async {
    if (user == null || foodName.isEmpty) return;

    // Try to fetch the food data from the "diabetic_foods" collection
    final doc = await _firestore.collection('diabetic_foods').doc(foodName).get();

    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Food "$foodName" not found in database')),
      );
      return;
    }

    final data = doc.data()!;
    final nutrition = {
      'calories': data['calories'] ?? 0,
      'carbs': data['carbs'] ?? 0,
      'protein': data['protein'] ?? 0,
      'fat': data['fat'] ?? 0,
      'sugar': data['sugar'] ?? 0,  // Added sugar to nutrition data
    };

    // Add the scanned food to the user's collection
    await _firestore
        .collection('users')
        .doc(user!.uid)
        .collection('scanned_foods')
        .add({
      'name': foodName,
      'nutrition': nutrition,
      'timestamp': Timestamp.now(),
    });

    // Update the latest nutrition data for display
    setState(() {
      latestNutrition = nutrition;
    });

    foodNameController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('You must be logged in to view this page')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Nutrient Summary')),
      body: Column(
        children: [
          // Food input field
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: foodNameController,
                    decoration: const InputDecoration(
                      labelText: 'Enter food name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('Add'),
                  onPressed: () => _addFoodByName(foodNameController.text.trim()),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                ),
              ],
            ),
          ),

          const Divider(),

          // Display the nutrition of the latest food added, if available
          if (latestNutrition != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nutrition Information:'),
                  SizedBox(height: 8),
                  Text('Calories: ${latestNutrition!['calories']} kcal'),
                  Text('Carbs: ${latestNutrition!['carbs']} g'),
                  Text('Protein: ${latestNutrition!['protein']} g'),
                  Text('Fat: ${latestNutrition!['fat']} g'),
                  Text('Sugar: ${latestNutrition!['sugar']} g'),  // Added sugar display
                ],
              ),
            ),

          // Display a message once the food is added
          if (latestNutrition == null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Add meals by entering the food name and click "Add" to log the food data.',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
