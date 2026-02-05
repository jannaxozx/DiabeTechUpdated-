import 'package:flutter/material.dart';

// NutrientTile widget
class NutrientTile extends StatelessWidget {
  final String label;
  final String value;

  const NutrientTile({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class DoDontFoodsScreen extends StatelessWidget {
  final String title; // '✅ DO' or '🚫 DON\'T'
  final List<Widget> foodCards;

  const DoDontFoodsScreen({super.key, required this.title, required this.foodCards});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: title.contains('DO') ? Colors.green : Colors.red,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: foodCards,
        ),
      ),
    );
  }
}
