import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetechapp/Screens/landing_page.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Logged out successfully")),
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LandingPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection("users").snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No users found"));
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              var user = users[index];
              String name = user['name'] ?? "No Name";
              String email = user['email'] ?? "No Email";
              String role = user['role'] ?? "user";

              return Card(
                child: ListTile(
                  title: Text(name),
                  subtitle: Text("$email\nRole: $role"),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == "viewLogs") {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserFoodLogScreen(
                              userId: user.id,
                              userName: name,
                            ),
                          ),
                        );
                      } else if (value == "editUser") {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                EditUserScreen(userId: user.id, userData: user),
                          ),
                        );
                      } else if (value == "deleteUser") {
                        FirebaseFirestore.instance
                            .collection("users")
                            .doc(user.id)
                            .delete();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("User deleted")),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                          value: "viewLogs", child: Text("View Food Logs")),
                      const PopupMenuItem(
                          value: "editUser", child: Text("Edit User")),
                      const PopupMenuItem(
                          value: "deleteUser", child: Text("Delete User")),
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

// ✅ User Food Log Screen with Add/Delete
class UserFoodLogScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const UserFoodLogScreen(
      {super.key, required this.userId, required this.userName});

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
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

// ✅ Add Food Log Screen
class AddFoodLogScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const AddFoodLogScreen(
      {super.key, required this.userId, required this.userName});

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

// ✅ Edit User Screen
class EditUserScreen extends StatefulWidget {
  final String userId;
  final DocumentSnapshot userData;

  const EditUserScreen(
      {super.key, required this.userId, required this.userData});

  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  late TextEditingController nameController;
  late TextEditingController emailController;
  late String role;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.userData['name']);
    emailController = TextEditingController(text: widget.userData['email']);
    role = widget.userData['role'] ?? "user";
  }

  Future<void> _saveChanges() async {
    await FirebaseFirestore.instance
        .collection("users")
        .doc(widget.userId)
        .update({
      "name": nameController.text,
      "email": emailController.text,
      "role": role,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("User updated successfully")),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit User")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: role,
              items: const [
                DropdownMenuItem(value: "user", child: Text("User")),
                DropdownMenuItem(value: "admin", child: Text("Admin")),
              ],
              onChanged: (value) {
                setState(() {
                  role = value!;
                });
              },
              decoration: const InputDecoration(labelText: "Role"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveChanges,
              child: const Text("Save Changes"),
            ),
          ],
        ),
      ),
    );
  }
}
