import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminFoodRulesScreen extends StatefulWidget {
  const AdminFoodRulesScreen({Key? key}) : super(key: key);

  @override
  State<AdminFoodRulesScreen> createState() => _AdminFoodRulesScreenState();
}

class _AdminFoodRulesScreenState extends State<AdminFoodRulesScreen> {
  final TextEditingController _foodController = TextEditingController();
  String _category = 'Do';
  bool _isSaving = false;
  bool _isAdmin = false;
  bool _checkingAdmin = true;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  /// 🔐 CHECK IF USER IS ADMIN
  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _denyAccess();
      return;
    }

    final adminDoc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .get();

    if (adminDoc.exists) {
      setState(() {
        _isAdmin = true;
        _checkingAdmin = false;
      });
    } else {
      _denyAccess();
    }
  }

  void _denyAccess() {
    setState(() => _checkingAdmin = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Access denied: Admins only')),
    );
    Navigator.pop(context);
  }

  /// ➕ SAVE FOOD
  Future<void> _saveFoodRule() async {
    final foodName = _foodController.text.trim().toLowerCase();

    if (foodName.isEmpty) return;

    setState(() => _isSaving = true);

    await FirebaseFirestore.instance
        .collection('food_rules')
        .doc(foodName)
        .set({
      'category': _category,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    setState(() {
      _isSaving = false;
      _foodController.clear();
      _category = 'Do';
    });
  }

  /// 🗑 DELETE FOOD
  Future<void> _deleteFood(String foodName) async {
    await FirebaseFirestore.instance
        .collection('food_rules')
        .doc(foodName)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAdmin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAdmin) {
      return const SizedBox();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin – Food Rules'),
        backgroundColor: const Color(0xFF2C6E49),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// ➕ ADD FOOD
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _foodController,
                      decoration: const InputDecoration(
                        labelText: 'Food name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _category,
                      items: const [
                        DropdownMenuItem(value: 'Do', child: Text('Do')),
                        DropdownMenuItem(value: 'Don’t', child: Text('Don’t')),
                      ],
                      onChanged: (value) =>
                          setState(() => _category = value!),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Category',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveFoodRule,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2C6E49),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            /// 📋 FOOD LIST
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('food_rules')
                    .orderBy('updatedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }

                  return ListView(
                    children: snapshot.data!.docs.map((doc) {
                      final food = doc.id;
                      final category = doc['category'];

                      return Card(
                        child: ListTile(
                          title: Text(food.toUpperCase()),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(category),
                                backgroundColor: category == 'Do'
                                    ? Colors.green[100]
                                    : Colors.red[100],
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.red),
                                onPressed: () => _deleteFood(food),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
