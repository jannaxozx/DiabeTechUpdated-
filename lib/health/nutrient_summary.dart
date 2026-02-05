import 'package:flutter/material.dart';

class NutrientSummaryScreen extends StatelessWidget {
  const NutrientSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nutrient Summary"),
        backgroundColor: const Color(0xFF2C6E49),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: const [
            const Text(
              "Your nutrient summary will be shown here",
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            const Center(child: Icon(Icons.bar_chart, size: 80, color: Colors.teal)),
          ],
        ),
      ),
    );
  }
}
