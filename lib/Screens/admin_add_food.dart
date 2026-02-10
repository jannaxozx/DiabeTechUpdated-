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
      'category': _category,
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
                    TextField(
                      controller: _portionSizeController,
                      decoration: const InputDecoration(
                        labelText: 'Portion Size (e.g., 1 cup, 100g)',
                        border: OutlineInputBorder(),
                      ),
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
                            controller: _proteinController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Protein (g)',
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
                        DropdownMenuItem(value: 'Don't', child: Text('Don't')),
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
                      final data = doc.data() as Map<String, dynamic>;
                      final foodName = data['name'] ?? doc.id;
                      final category = data['category'] ?? 'Do';
                      // Clean category to show only "Do" or "Don't"
                      final cleanCategory = category.toString().split(' ')[0];
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
                          subtitle: hasNutritionalData 
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.local_fire_department, size: 16, color: Colors.orange),
                                      const SizedBox(width: 4),
                                      Text('$calories kcal'),
                                      const SizedBox(width: 12),
                                      Icon(Icons.grain, size: 16, color: Colors.brown),
                                      const SizedBox(width: 4),
                                      Text('${carbs}g carbs'),
                                      const SizedBox(width: 12),
                                      Icon(Icons.fitness_center, size: 16, color: Colors.red),
                                      const SizedBox(width: 4),
                                      Text('${protein}g protein'),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.water_drop, size: 16, color: Colors.yellow[700]),
                                      const SizedBox(width: 4),
                                      Text('${fat}g fat'),
                                      const SizedBox(width: 12),
                                      Icon(Icons.straighten, size: 16, color: Colors.blue),
                                      const SizedBox(width: 4),
                                      Text('${data['portionSize'] ?? '1 serving'}'),
                                    ],
                                  ),
                                ],
                              )
                            : Text(
                                'Category: ${cleanCategory}',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
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
