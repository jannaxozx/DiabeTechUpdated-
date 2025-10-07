import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:diabetechapp/Screens/add_food_log_screen.dart';

class UserFoodLogScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const UserFoodLogScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("$userName's Food Logs")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(userId)
            .collection("foodLogs")
            .orderBy("timestamp", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snapshot.data?.docs ?? [];
          if (logs.isEmpty) {
            return const Center(child: Text("No food logs found"));
          }

          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final logDoc = logs[index];
              final logData = logDoc.data() as Map<String, dynamic>? ?? {};

              final foodName = (logData['food'] ?? "Unknown food").toString();

              final rawCalories = logData['calories'];
              final calories = (rawCalories is int)
                  ? rawCalories
                  : int.tryParse(rawCalories?.toString() ?? '0') ?? 0;

              final timestamp = logData['timestamp'] as Timestamp?;
              final formattedDate = timestamp != null
                  ? DateFormat("MMM d, yyyy • h:mm a")
                      .format(timestamp.toDate())
                  : "No date";

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                elevation: 3,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LEFT SIDE (Food details)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              foodName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text("Calories: $calories kcal"),
                            if (logData.containsKey("carbs"))
                              Text("Carbs: ${logData['carbs']} g"),
                            if (logData.containsKey("protein"))
                              Text("Protein: ${logData['protein']} g"),
                            if (logData.containsKey("fat"))
                              Text("Fat: ${logData['fat']} g"),
                            Text("Logged on: $formattedDate"),
                          ],
                        ),
                      ),

                      // RIGHT SIDE (popup menu)
                      PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == "delete") {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Delete log"),
                                content: Text("Delete \"$foodName\"?"),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, false),
                                    child: const Text("Cancel"),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, true),
                                    child: const Text("Delete"),
                                  ),
                                ],
                              ),
                            );

                            if (confirm ?? false) {
                              await FirebaseFirestore.instance
                                  .collection("users")
                                  .doc(userId)
                                  .collection("foodLogs")
                                  .doc(logDoc.id)
                                  .delete();

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text("Food log deleted")),
                                );
                              }
                            }
                          } else if (value == "edit") {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddFoodLogScreen(
                                  userId: userId,
                                  userName: userName,
                                  logId: logDoc.id,
                                  existingData: logData,
                                ),
                              ),
                            );
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: "edit", child: Text("Edit")),
                          PopupMenuItem(value: "delete", child: Text("Delete")),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
