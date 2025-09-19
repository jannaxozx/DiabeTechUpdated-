import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No food logs found"));
          }

          final logs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              var log = logs[index];
              String foodName = log['food'] ?? "Unknown food";
              int calories = log['calories'] ?? 0;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(foodName),
                  subtitle: Text("Calories: $calories"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection("users")
                          .doc(userId)
                          .collection("foodLogs")
                          .doc(log.id)
                          .delete();

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Food log deleted")),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),

      // ✅ Floating Action Button to add food log
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AddFoodLogScreen(userId: userId, userName: userName),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ✅ New Screen: Add Food Log
class AddFoodLogScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const AddFoodLogScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AddFoodLogScreen> createState() => _AddFoodLogScreenState();
}

class _AddFoodLogScreenState extends State<AddFoodLogScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController foodController = TextEditingController();
  final TextEditingController caloriesController = TextEditingController();

  Future<void> _saveLog() async {
    if (_formKey.currentState!.validate()) {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.userId)
          .collection("foodLogs")
          .add({
        "food": foodController.text,
        "calories": int.tryParse(caloriesController.text) ?? 0,
        "timestamp": FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Food log added")),
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Add Food Log for ${widget.userName}")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: foodController,
                decoration: const InputDecoration(
                  labelText: "Food Name",
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? "Enter a food name" : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: caloriesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Calories",
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? "Enter calories" : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveLog,
                child: const Text("Save Log"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
