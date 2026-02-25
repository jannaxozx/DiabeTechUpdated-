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
  String _filterDiabetesType = 'All'; // ← NEW: filter state
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
      'category': _category.trim().split(' ')[0],
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
  Future<void> _deleteFood(String foodId) async {
    await FirebaseFirestore.instance
        .collection('food_rules')
        .doc(foodId)
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
            /// ➕ ADD FOOD FORM
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
                        DropdownMenuItem(
                            value: "Don't", child: Text("Don't")),
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

            const SizedBox(height: 16),

            // ════════════════════════════════════════════════════════════════
            //  DIVIDER
            // ════════════════════════════════════════════════════════════════
            const Divider(thickness: 2, color: Colors.green),

            const SizedBox(height: 12),

            // ════════════════════════════════════════════════════════════════
            //  FILTER DROPDOWN — right after the divider
            // ════════════════════════════════════════════════════════════════
            DropdownButtonFormField<String>(
              value: _filterDiabetesType,
              decoration: InputDecoration(
                labelText: 'Filter by Diabetes Type',
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C6E49),
                ),
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.filter_list,
                    color: Color(0xFF2C6E49)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFF2C6E49)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF2C6E49), width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF2C6E49), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'All', child: Text('📋 All Foods')),
                DropdownMenuItem(
                    value: 'Mild', child: Text('🟢 Mild Diabetes')),
                DropdownMenuItem(
                    value: 'Moderate',
                    child: Text('🟡 Moderate Diabetes')),
                DropdownMenuItem(
                    value: 'Severe',
                    child: Text('🔴 Severe Diabetes')),
              ],
              onChanged: (value) =>
                  setState(() => _filterDiabetesType = value!),
            ),

            const SizedBox(height: 12),

            // ════════════════════════════════════════════════════════════════
            //  FOOD LIST
            // ════════════════════════════════════════════════════════════════
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

                  // Apply diabetes type filter
                  final filteredDocs =
                      snapshot.data!.docs.where((doc) {
                    if (_filterDiabetesType == 'All') return true;
                    final data = doc.data() as Map<String, dynamic>;
                    return (data['diabetesType']?.toString() ?? 'Mild') ==
                        _filterDiabetesType;
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.no_meals,
                              size: 50, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            _filterDiabetesType == 'All'
                                ? 'No foods added yet.'
                                : 'No foods found for $_filterDiabetesType Diabetes',
                            style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 15),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final foodName = data['name'] ?? doc.id;
                      final category = data['category'] ?? 'Do';
                      final diabetesType =
                          data['diabetesType']?.toString() ?? '';

                      // Clean category
                      String cleanCategory = 'Do';
                      final categoryStr = category.toString().trim();
                      if (categoryStr.toLowerCase().startsWith('don')) {
                        cleanCategory = "Don't";
                      } else if (categoryStr.toLowerCase().startsWith('do')) {
                        cleanCategory = 'Do';
                      }

                      // Diabetes type badge color
                      Color dtColor = Colors.green;
                      String dtIcon = '🟢';
                      if (diabetesType == 'Moderate') {
                        dtColor = Colors.orange;
                        dtIcon = '🟡';
                      } else if (diabetesType == 'Severe') {
                        dtColor = Colors.red;
                        dtIcon = '🔴';
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            foodName.toString().toUpperCase(),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: Row(
                            children: [
                              Text(
                                cleanCategory,
                                style: TextStyle(
                                  color: cleanCategory == 'Do'
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (diabetesType.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: dtColor.withOpacity(0.15),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    border: Border.all(
                                        color:
                                            dtColor.withOpacity(0.4)),
                                  ),
                                  child: Text(
                                    '$dtIcon $diabetesType',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: dtColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
                                builder: (context) =>
                                    AdminFoodDetailScreen(
                                        foodId: doc.id),
                              ),
                            );
                          },
                        ),
                      );
                    },
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