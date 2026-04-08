import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_food_detail_screen.dart';

class AdminFoodRulesScreen extends StatefulWidget {
  const AdminFoodRulesScreen({Key? key}) : super(key: key);

  @override
  State<AdminFoodRulesScreen> createState() => _AdminFoodRulesScreenState();
}

class _AdminFoodRulesScreenState extends State<AdminFoodRulesScreen> {
  final TextEditingController _foodController = TextEditingController();
  final TextEditingController _caloriesController = TextEditingController();
  final TextEditingController _carbsController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  bool _isSaving = false;
  bool _isAdmin = false;
  bool _checkingAdmin = true;

  String _diabetesType = 'Mild';
  String _category = 'Do';

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

    final adminDoc =
        await FirebaseFirestore.instance
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Access denied: Admins only')));
    Navigator.pop(context);
  }

  /// ➕ SAVE FOOD
  Future<void> _saveFoodRule() async {
    final foodName = _foodController.text.trim();

    if (foodName.isEmpty) return;

    setState(() => _isSaving = true);

    await FirebaseFirestore.instance
        .collection('food_rules')
        .doc(foodName.toLowerCase())
        .set({
          'name': foodName,
          'calories': int.tryParse(_caloriesController.text) ?? 0,
          'carbs': double.tryParse(_carbsController.text) ?? 0,
          'protein': double.tryParse(_proteinController.text) ?? 0,
          'fat': double.tryParse(_fatController.text) ?? 0,
          'diabetesType': _diabetesType,
          'category': _category,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

    setState(() {
      _isSaving = false;
      _foodController.clear();
      _caloriesController.clear();
      _carbsController.clear();
      _proteinController.clear();
      _fatController.clear();
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                borderRadius: BorderRadius.circular(12),
              ),
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
                    const Text(
                      'Nutrition per 100g',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C6E49),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _diabetesType,
                            decoration: const InputDecoration(
                              labelText: 'Diabetes Type',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Mild',
                                child: Text('Mild'),
                              ),
                              DropdownMenuItem(
                                value: 'Severe',
                                child: Text('Severe'),
                              ),
                            ],
                            onChanged:
                                (v) => setState(() => _diabetesType = v!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _category,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Do',
                                child: Text('✅ Do (Safe)'),
                              ),
                              DropdownMenuItem(
                                value: "Don't",
                                child: Text("🚫 Don't (Avoid)"),
                              ),
                            ],
                            onChanged: (v) => setState(() => _category = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _caloriesController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Calories (per 100g)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _carbsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Carbs (g per 100g)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _proteinController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Protein (g per 100g)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _fatController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Fat (g per 100g)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Note: Select the diabetes type and category (Do/Don\'t) for this food. Users will only see foods matching their diabetes type.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
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
                        child:
                            _isSaving
                                ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                                : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            /// FOOD LIST
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    FirebaseFirestore.instance
                        .collection('food_rules')
                        .orderBy('updatedAt', descending: true)
                        .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return ListView(
                    children:
                        snapshot.data!.docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final foodName = data['name'] ?? doc.id;
                          final carbs = data['carbs'] ?? 0;
                          final calories = data['calories'] ?? 0;
                          final diabetesType =
                              data['diabetesType'] ?? 'Not set';
                          final category = data['category'] ?? 'Not set';

                          return Card(
                            child: ListTile(
                              title: Text(foodName.toString().toUpperCase()),
                              subtitle: Text(
                                '${carbs}g carbs, ${calories} cal per 100g\n$diabetesType • $category',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Chip(
                                    label: Text(
                                      category == 'Do' ? '✅ Do' : "🚫 Don't",
                                    ),
                                    backgroundColor:
                                        category == 'Do'
                                            ? Colors.green
                                            : Colors.red,
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _deleteFood(doc.id),
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => AdminFoodDetailScreen(
                                          foodId: doc.id,
                                        ),
                                  ),
                                );
                              },
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
