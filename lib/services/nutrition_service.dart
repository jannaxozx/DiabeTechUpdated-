import 'package:cloud_firestore/cloud_firestore.dart';

class NutritionService {
  // Hardcoded food-to-nutrition data for now
  static final Map<String, Map<String, dynamic>> foodNutritionMap = {
    'chicken': {'calories': 335, 'carbs': 0, 'protein': 30, 'fats': 20},
    'salad': {'calories': 120, 'carbs': 10, 'protein': 2, 'fats': 8},
    'rice': {'calories': 200, 'carbs': 45, 'protein': 4, 'fats': 1},
    'egg': {'calories': 78, 'carbs': 1, 'protein': 6, 'fats': 5},
    // Add more food items as needed
  };

  // Function to get nutrition data for a food item
  Map<String, dynamic>? getNutritionData(String food) {
    return foodNutritionMap[food];
  }

  // Future version for fetching nutrition data from Firestore
  Future<Map<String, dynamic>?> fetchNutritionDataFromFirestore(String food) async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('nutrition_data')
          .doc(food.toLowerCase())
          .get();

      if (docSnapshot.exists) {
        return docSnapshot.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print("Error fetching nutrition data: $e");
      return null;
    }
  }
}
