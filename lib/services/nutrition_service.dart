import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> addNutritionAndMealData({
  int calories = 1400,
  int carbs = 120,
  int protein = 60,
  int fats = 50,
  String mealName = 'Chicken Salad',
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userId = user.uid;
  final firestore = FirebaseFirestore.instance;

  final today = DateTime.now();
  final nutritionDate = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

  // Save nutrition data
  await firestore
      .collection('users')
      .doc(userId)
      .collection('nutrition')
      .doc(nutritionDate)
      .set({
        'calories': calories,
        'carbs': carbs,
        'protein': protein,
        'fats': fats,
        'date': Timestamp.now(),
      });

  // Save meal data
  final mealId = firestore.collection('users').doc(userId).collection('meals').doc().id;
  await firestore
      .collection('users')
      .doc(userId)
      .collection('meals')
      .doc(mealId)
      .set({
        'mealName': mealName,
        'date': Timestamp.now(),
        'calories': calories,
        'carbs': carbs,
        'protein': protein,
        'fats': fats,
      });
}
