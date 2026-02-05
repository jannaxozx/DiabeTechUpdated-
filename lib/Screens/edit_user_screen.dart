import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditUserScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> userData;

  const EditUserScreen({super.key, required this.userId, required this.userData});

  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  late TextEditingController nameController;
  late TextEditingController emailController;
  String role = "user";

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.userData['name']);
    emailController = TextEditingController(text: widget.userData['email']);
    role = widget.userData['role'] ?? "user";
  }

  Future<void> updateUser() async {
    try {
      await FirebaseFirestore.instance.collection("users").doc(widget.userId).update({
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'role': role,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User updated successfully")),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update user: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit User")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: role,
              items: const [
                DropdownMenuItem(value: "user", child: Text("User")),
                DropdownMenuItem(value: "admin", child: Text("Admin")),
              ],
              onChanged: (value) => setState(() => role = value!),
              decoration: const InputDecoration(labelText: "Role"),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: updateUser,
              child: const Text("Save Changes"),
            ),
          ],
        ),
      ),
    );
  }
}
