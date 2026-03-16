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
  final _foodController     = TextEditingController();
  final _caloriesController = TextEditingController();
  final _carbsController    = TextEditingController();
  final _proteinController  = TextEditingController();
  final _fatController      = TextEditingController();
  // portionSize is now a text description only (e.g. "1 cup / 240 ml")
  // because the app auto-calculates the actual gram amount per user
  final _portionDescController = TextEditingController();

  String _category           = 'Do';
  String _diabetesType       = 'Mild';
  String _filterDiabetesType = 'All';
  bool   _isSaving           = false;
  bool   _isAdmin            = false;
  bool   _checkingAdmin      = true;

  static const Color _green = Color(0xFF2C6E49);

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
    _portionDescController.dispose();
    super.dispose();
  }

  List<String> _buildKeywords(String name) {
    final lower = name.toLowerCase().trim();
    final words = lower.split(' ').where((w) => w.length > 1).toList();
    return {lower, ...words}.toList();
  }

  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _denyAccess(); return; }
    final doc = await FirebaseFirestore.instance
        .collection('admins').doc(user.uid).get();
    if (doc.exists) {
      setState(() { _isAdmin = true; _checkingAdmin = false; });
    } else {
      _denyAccess();
    }
  }

  void _denyAccess() {
    setState(() => _checkingAdmin = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Access denied: Admins only')));
    Navigator.pop(context);
  }

  Future<void> _saveFoodRule() async {
    final foodName = _foodController.text.trim();
    if (foodName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Please enter a food name')));
      return;
    }

    // Validate at least calories is filled
    final cal = double.tryParse(_caloriesController.text.trim()) ?? 0.0;
    if (cal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('⚠️ Please enter calories per 100g'),
              backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('food_rules').add({
        'name':           foodName,
        'nameLower':      foodName.toLowerCase().trim(),
        'searchKeywords': _buildKeywords(foodName),
        'category':       _category,
        'diabetesType':   _diabetesType,
        // portionSize is kept as a human-readable description
        'portionSize':    _portionDescController.text.trim().isEmpty
            ? '1 serving'
            : _portionDescController.text.trim(),
        // All nutrients stored as per-100g values
        'calories': double.tryParse(_caloriesController.text.trim()) ?? 0.0,
        'carbs':    double.tryParse(_carbsController.text.trim())    ?? 0.0,
        'protein':  double.tryParse(_proteinController.text.trim())  ?? 0.0,
        'fat':      double.tryParse(_fatController.text.trim())      ?? 0.0,
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
        _portionDescController.clear();
        _category     = 'Do';
        _diabetesType = 'Mild';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ "$foodName" saved!'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteFood(String foodId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Food'),
        content: const Text('Remove this food from the database?'),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Food deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAdmin) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_isAdmin)      return const SizedBox();

    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      appBar: AppBar(
        title: const Text('Admin – Food Rules',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _green,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [

          // ── ADD FOOD FORM ───────────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Header
                Row(children: [
                  const Icon(Icons.add_circle, color: _green, size: 20),
                  const SizedBox(width: 8),
                  const Text('Add New Food',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _green)),
                ]),
                const SizedBox(height: 10),

                // Info banner
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Enter all nutrient values per 100g of this food.\n'
                        'The app will automatically calculate the right portion size and '
                        'nutrient amounts for each user based on their height, weight, '
                        'activity level, and diabetes type.',
                        style: TextStyle(color: Colors.blue.shade800, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),

                // Food name
                TextField(
                  controller: _foodController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Food Name *',
                    prefixIcon: Icon(Icons.restaurant, color: _green),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _green, width: 2)),
                  ),
                ),
                const SizedBox(height: 10),

                // Portion description (optional, human-readable)
                TextField(
                  controller: _portionDescController,
                  decoration: const InputDecoration(
                    labelText: 'Portion Description (optional, e.g. 1 cup, 1 bowl)',
                    prefixIcon: Icon(Icons.rice_bowl, color: _green),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _green, width: 2)),
                    hintText: 'e.g. 1 cup cooked',
                  ),
                ),
                const SizedBox(height: 12),

                // ── Nutrients per 100g label ────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _green.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _green.withOpacity(0.2)),
                  ),
                  child: const Text(
                    '📊 Nutrients per 100g',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold, color: _green),
                  ),
                ),
                const SizedBox(height: 10),

                // Calories + Carbs
                Row(children: [
                  Expanded(child: _nutrientField(
                    controller: _caloriesController,
                    label: 'Calories (kcal) *',
                    icon: '🔥',
                    color: Colors.orange,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _nutrientField(
                    controller: _carbsController,
                    label: 'Carbs (g)',
                    icon: '🍞',
                    color: Colors.blue,
                  )),
                ]),
                const SizedBox(height: 10),

                // Protein + Fat
                Row(children: [
                  Expanded(child: _nutrientField(
                    controller: _proteinController,
                    label: 'Protein (g)',
                    icon: '💪',
                    color: Colors.purple,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _nutrientField(
                    controller: _fatController,
                    label: 'Fat (g)',
                    icon: '🧈',
                    color: Colors.brown,
                  )),
                ]),
                const SizedBox(height: 12),

                // Category + Diabetes Type
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _category,
                      decoration: const InputDecoration(
                          labelText: 'Category', border: OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: _green, width: 2))),
                      items: const [
                        DropdownMenuItem(value: 'Do',    child: Text('✅ Do (Safe)')),
                        DropdownMenuItem(value: "Don't", child: Text("⚠️ Don't (Avoid)")),
                      ],
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _diabetesType,
                      decoration: const InputDecoration(
                          labelText: 'Diabetes Type', border: OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: _green, width: 2))),
                      items: const [
                        DropdownMenuItem(value: 'Mild',   child: Text('🟢 Mild')),
                        DropdownMenuItem(value: 'Severe', child: Text('🔴 Severe')),
                      ],
                      onChanged: (v) => setState(() => _diabetesType = v!),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveFoodRule,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload, color: Colors.white),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save Food to Database',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 14),
          const Divider(thickness: 1.5, color: Color(0xFF2C6E49)),
          const SizedBox(height: 8),

          // ── FILTER ─────────────────────────────────────────────────
          Row(
            children: [
              const Text('Filter by type:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _green)),
              const Spacer(),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  value: _filterDiabetesType,
                  decoration: InputDecoration(
                    filled: true, fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.filter_list, color: _green, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _green)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'All',      child: Text('📋 All',      style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'Mild',     child: Text('🟢 Mild',     style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'Severe',   child: Text('🔴 Severe',   style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) => setState(() => _filterDiabetesType = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── FOOD LIST ───────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('food_rules')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final filtered = snapshot.data!.docs.where((doc) {
                  if (_filterDiabetesType == 'All') return true;
                  final d = doc.data() as Map<String, dynamic>;
                  return (d['diabetesType']?.toString() ?? 'Mild') == _filterDiabetesType;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.no_food, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('No foods added yet.\nUse the form above to add foods.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                    ],
                  ));
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final doc      = filtered[i];
                    final data     = doc.data() as Map<String, dynamic>;
                    final name     = (data['name'] ?? '').toString();
                    final category = (data['category'] ?? 'Do').toString();
                    final dtype    = (data['diabetesType'] ?? '').toString();
                    final isSafe   = category == 'Do';

                    // Nutrient preview (per 100g)
                    final cal     = _d(data['calories']);
                    final carbs   = _d(data['carbs']);
                    final protein = _d(data['protein']);
                    final fat     = _d(data['fat']);

                    final dtColor = dtype == 'Mild'
                        ? Colors.green
                        : Colors.red;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                            color: isSafe
                                ? Colors.green.withOpacity(0.3)
                                : Colors.red.withOpacity(0.3)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AdminFoodDetailScreen(foodId: doc.id))),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            // Name row
                            Row(children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: isSafe
                                    ? Colors.green.shade100 : Colors.red.shade100,
                                child: Icon(isSafe ? Icons.check : Icons.close,
                                    color: isSafe ? Colors.green : Colors.red, size: 16),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(name.toUpperCase(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              _badge(isSafe ? '✅ Do' : "⚠️ Don't",
                                  isSafe ? Colors.green : Colors.red),
                              const SizedBox(width: 6),
                              if (dtype.isNotEmpty) _badge(dtype, dtColor),
                            ]),
                            const SizedBox(height: 8),
                            // Nutrient chips per 100g
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Per 100g:',
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.grey.shade500,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Wrap(spacing: 6, runSpacing: 4, children: [
                                    if (cal > 0)
                                      _nutrientBadge('🔥 ${cal.toStringAsFixed(0)} kcal', Colors.orange),
                                    if (carbs > 0)
                                      _nutrientBadge('🍞 ${carbs.toStringAsFixed(1)}g carbs', Colors.blue),
                                    if (protein > 0)
                                      _nutrientBadge('💪 ${protein.toStringAsFixed(1)}g protein', Colors.purple),
                                    if (fat > 0)
                                      _nutrientBadge('🧈 ${fat.toStringAsFixed(1)}g fat', Colors.brown),
                                  ]),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Delete row
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2)),
                                icon: const Icon(Icons.delete_outline, size: 14),
                                label: const Text('Delete',
                                    style: TextStyle(fontSize: 11)),
                                onPressed: () => _deleteFood(doc.id),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ── Nutrient text field with colored icon prefix ──────────────────
  Widget _nutrientField({
    required TextEditingController controller,
    required String label,
    required String icon,
    required Color  color,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Container(
          width: 36,
          alignment: Alignment.center,
          child: Text(icon, style: const TextStyle(fontSize: 16)),
        ),
        border: const OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: color, width: 2)),
        labelStyle: TextStyle(color: color.withOpacity(0.8), fontSize: 12),
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
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _nutrientBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
}