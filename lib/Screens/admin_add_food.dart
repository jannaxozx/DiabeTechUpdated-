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
  final TextEditingController _portionSizeController = TextEditingController();
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
    final foodName = _foodController.text.trim();

    if (foodName.isEmpty) return;

    setState(() => _isSaving = true);

    await FirebaseFirestore.instance
        .collection('food_rules')
        .doc(foodName.toLowerCase())
        .set({
      'name': foodName,
      'category': _category.trim().split(' ')[0], // Save only "Do" or "Don't"
      'calories': int.tryParse(_caloriesController.text) ?? 0,
      'carbs': double.tryParse(_carbsController.text) ?? 0,
      'protein': double.tryParse(_proteinController.text) ?? 0,
      'fat': double.tryParse(_fatController.text) ?? 0,
      'portionSize': _portionSizeController.text.trim().isEmpty 
          ? '1 serving' 
          : _portionSizeController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    setState(() {
      _isSaving = false;
      _foodController.clear();
      _caloriesController.clear();
      _carbsController.clear();
      _proteinController.clear();
      _fatController.clear();
      _portionSizeController.clear();
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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _portionSizeController,
                            decoration: const InputDecoration(
                              labelText: 'Portion Size (e.g., 1 cup, 100g)',
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
                              labelText: 'Carbs (g)',
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
                            controller: _caloriesController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Calories',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _proteinController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Protein (g)',
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
                            controller: _fatController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Fat (g)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _category,
                      items: const [
                        DropdownMenuItem(value: 'Do', child: Text('Do')),
                        DropdownMenuItem(value: 'Don\'t', child: Text('Don\'t')),
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

            /// FOOD LIST
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
                      final data = doc.data() as Map<String, dynamic>;
                      final foodName = data['name'] ?? doc.id;
                      final category = data['category'] ?? 'Do';
                      
                      // More robust category cleaning - extract just "Do" or "Don't"
                      String cleanCategory = 'Do';
                      final categoryStr = category.toString().trim();
                      
                      // Remove any extra characters after "Do" or "Don't"
                      if (categoryStr.toLowerCase().startsWith('don')) {
                        cleanCategory = 'Don\'t';
                      } else if (categoryStr.toLowerCase().startsWith('do')) {
                        cleanCategory = 'Do';
                      }
                      
                      debugPrint('Raw category: "$categoryStr"');
                      debugPrint('Clean category: "$cleanCategory"');
                      
                      final calories = data['calories'] ?? 0;
                      final carbs = data['carbs'] ?? 0;
                      final protein = data['protein'] ?? 0;
                      final fat = data['fat'] ?? 0;

                      // Check if this is old data (no nutritional info)
                      final hasNutritionalData = data.containsKey('calories') || 
                                               data.containsKey('carbs') || 
                                               data.containsKey('protein') || 
                                               data.containsKey('fat');

                      return Card(
                        child: ListTile(
                          title: Text(foodName.toString().toUpperCase()),
                          subtitle: Text(cleanCategory),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(cleanCategory),
                                backgroundColor: cleanCategory == 'Do'
                                    ? Colors.green[100]
                                    : Colors.red[100],
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.red),
                                onPressed: () => _deleteFood(doc.id),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminFoodDetailScreen(foodId: doc.id),
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
