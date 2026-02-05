import 'package:flutter/material.dart';

class GoalProgressScreen extends StatelessWidget {
  final double weeklyGoalProgress;
  final String goalText;

  const GoalProgressScreen({
    super.key,
    required this.weeklyGoalProgress,
    required this.goalText,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.teal.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.flag, color: Colors.teal),
              title: Text(goalText),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: weeklyGoalProgress,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(Colors.teal),
            ),
          ],
        ),
      ),
    );
  }
}
