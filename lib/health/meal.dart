import 'package:flutter/material.dart';

class MealLogScreen extends StatelessWidget {
  const MealLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Meal Log"),
        backgroundColor: const Color(0xFF2C6E49),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Today's Meals",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  _buildMealCard("Breakfast", "Oatmeal with fruits"),
                  _buildMealCard("Lunch", "Grilled chicken with salad"),
                  _buildMealCard("Dinner", "Steamed fish and vegetables"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealCard(String mealType, String description) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.restaurant_menu, color: Color(0xFF2C6E49)),
        title: Text(mealType, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
      ),
    );
  }
}
