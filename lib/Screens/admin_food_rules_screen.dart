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
  final TextEditingController _foodController        = TextEditingController();
  final TextEditingController _caloriesController    = TextEditingController();
  final TextEditingController _carbsController       = TextEditingController();
  final TextEditingController _proteinController     = TextEditingController();
  final TextEditingController _fatController         = TextEditingController();
  final TextEditingController _sugarController       = TextEditingController(); // Added
  final TextEditingController _portionSizeController = TextEditingController();

  String _category           = 'Do';
  String _diabetesType       = 'Mild';
  String _filterDiabetesType = 'All';
  bool _isSaving       = false;
  bool _isAdmin        = false;
  bool _checkingAdmin  = true;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  @override
  void dispose() {
    _foodController.dispose();
    _caloriesController.dispose();
    _carbsController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _sugarController.dispose(); // Added
    _portionSizeController.dispose();
    super.dispose();
  }

  List<String> _buildKeywords(String name) {
    final nameLower = name.toLowerCase().trim();
    final nameWords = nameLower.split(' ').where((w) => w.length > 1).toList();
    return {nameLower, ...nameWords}.toList();
  }

  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _denyAccess(); return; }

    final adminDoc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .get();

    if (adminDoc.exists) {
      setState(() { _isAdmin = true; _checkingAdmin = false; });
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

  Future<void> _saveFoodRule() async {
    final foodName = _foodController.text.trim();
    if (foodName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Please enter a food name')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance
          .collection('food_rules')
          .add({
        'name':           foodName,
        'nameLower':      foodName.toLowerCase().trim(),
        'searchKeywords': _buildKeywords(foodName),
        'category':       _category,
        'diabetesType':   _diabetesType,
        'portionSize': _portionSizeController.text.trim().isEmpty
            ? '1 serving'
            : _portionSizeController.text.trim(),
        'calories':  double.tryParse(_caloriesController.text.trim()) ?? 0.0,
        'carbs':     double.tryParse(_carbsController.text.trim())    ?? 0.0,
        'protein':   double.tryParse(_proteinController.text.trim())  ?? 0.0,
        'fat':       double.tryParse(_fatController.text.trim())      ?? 0.0,
        'sugar':     double.tryParse(_sugarController.text.trim())    ?? 0.0, // Added
        'imageUrl':  '',
        'imagePath': '',
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
        _sugarController.clear(); // Added
        _portionSizeController.clear();
        _category     = 'Do';
        _diabetesType = 'Mild';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ "$foodName" saved! Scanner can now find this food.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteFood(String foodId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Food'),
        content: const Text('Remove this food from the scanner database?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await FirebaseFirestore.instance.collection('food_rules').doc(foodId).delete();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Food deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAdmin) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_isAdmin) return const SizedBox();

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

            // ── ADD FOOD FORM ─────────────────────────────────────────
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Info banner
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Foods saved here will be found by the AI Scanner.',
                            style: TextStyle(color: Colors.blue.shade800, fontSize: 11),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // Food name
                    TextField(
                      controller: _foodController,
                      decoration: const InputDecoration(
                        labelText: 'Food Name *',
                        prefixIcon: Icon(Icons.restaurant, color: Color(0xFF2C6E49)),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Portion Size + Carbs
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _portionSizeController,
                          decoration: const InputDecoration(
                            labelText: 'Portion Size (e.g. 1 cup, 100g)',
                            prefixIcon: Icon(Icons.scale, color: Color(0xFF2C6E49)),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _carbsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Carbs (g)', border: OutlineInputBorder()),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),

                    // Calories + Protein
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _caloriesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Calories', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _proteinController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Protein (g)', border: OutlineInputBorder()),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),

                    // Fat + Sugar
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _fatController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Fat (g)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _sugarController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Sugar (g)', border: OutlineInputBorder()),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),

                    // Category + Diabetes Type
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _category,
                          decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'Do',    child: Text('✅ Do')),
                            DropdownMenuItem(value: "Don't", child: Text("⚠️ Don't")),
                          ],
                          onChanged: (v) => setState(() => _category = v!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _diabetesType,
                          decoration: const InputDecoration(labelText: 'Diabetes Type', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'Mild',     child: Text('🟢 Mild')),
                            DropdownMenuItem(value: 'Moderate', child: Text('🟡 Moderate')),
                            DropdownMenuItem(value: 'Severe',   child: Text('🔴 Severe')),
                          ],
                          onChanged: (v) => setState(() => _diabetesType = v!),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveFoodRule,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2C6E49),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _isSaving
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cloud_upload),
                        label: Text(_isSaving ? 'Saving...' : 'Save to Scanner Database'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(thickness: 2, color: Colors.green),
            const SizedBox(height: 12),

            // ── FILTER DROPDOWN ───────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    value: _filterDiabetesType,
                    decoration: InputDecoration(
                      labelText: 'Filter',
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2C6E49)),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.filter_list, color: Color(0xFF2C6E49), size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF2C6E49), width: 1),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'All',      child: Text('📋 All', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'Mild',     child: Text('🟢 Mild', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'Moderate', child: Text('🟡 Moderate', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(value: 'Severe',   child: Text('🔴 Severe', style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (v) => setState(() => _filterDiabetesType = v!),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── FOOD LIST ─────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('food_rules')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  final filteredDocs = snapshot.data!.docs.where((doc) {
                    if (_filterDiabetesType == 'All') return true;
                    final data = doc.data() as Map<String, dynamic>;
                    return (data['diabetesType']?.toString() ?? 'Mild') == _filterDiabetesType;
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.no_meals, size: 50, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            _filterDiabetesType == 'All'
                                ? 'No foods added yet.'
                                : 'No foods for $_filterDiabetesType Diabetes',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc      = filteredDocs[index];
                      final data     = doc.data() as Map<String, dynamic>;
                      final foodName = (data['name'] ?? doc.id).toString();
                      final cat      = (data['category'] ?? 'Do').toString();
                      final dtype    = (data['diabetesType'] ?? '').toString();
                      final isDoFood = cat == 'Do';

                      Color dtColor = Colors.green;
                      if (dtype == 'Moderate') dtColor = Colors.orange;
                      if (dtype == 'Severe')   dtColor = Colors.red;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isDoFood
                                ? Colors.green.withOpacity(0.3)
                                : Colors.red.withOpacity(0.3),
                          ),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isDoFood ? Colors.green.shade100 : Colors.red.shade100,
                            child: Icon(isDoFood ? Icons.check : Icons.close,
                                color: isDoFood ? Colors.green : Colors.red),
                          ),
                          title: Text(foodName.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Row(children: [
                            _badge(isDoFood ? '✅ Do' : "⚠️ Don't",
                                isDoFood ? Colors.green : Colors.red),
                            const SizedBox(width: 6),
                            if (dtype.isNotEmpty) _badge(dtype, dtColor),
                          ]),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(isDoFood ? 'Do' : "Don't"),
                                backgroundColor: isDoFood ? Colors.green[100] : Colors.red[100],
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteFood(doc.id),
                              ),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminFoodDetailScreen(foodId: doc.id),
                            ),
                          ),
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

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );
}