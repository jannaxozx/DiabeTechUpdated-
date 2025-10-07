import 'package:flutter/material.dart';

class GoalProgressScreen extends StatelessWidget {
  final double weeklyGoalProgress; // 0.0 to 1.0
  final String goalText; // Example: "Weekly goal: 80% completed"

  const GoalProgressScreen({
    Key? key,
    this.weeklyGoalProgress = 0.8,
    this.goalText = "Weekly goal: 80% completed",
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.teal.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Progress Circle
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    value: weeklyGoalProgress,
                    strokeWidth: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                  ),
                ),
                Text(
                  "${(weeklyGoalProgress * 100).toInt()}%",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(width: 16),
            // Goal Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goalText,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Keep going! You’re doing great.",
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.flag, color: Colors.teal),
          ],
        ),
      ),
    );
  }
}
