import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MealLogScreen extends StatefulWidget {
  const MealLogScreen({super.key});

  @override
  State<MealLogScreen> createState() => _MealLogScreenState();
}

class _MealLogScreenState extends State<MealLogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const Color _green = Color(0xFF2C6E49);
  static const List<String> _mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _mealTypes.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openAddFoodSheet({String? preselectedMeal}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => AddFoodSheet(
        preselectedMeal: preselectedMeal ?? _mealTypes[_tabController.index],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      appBar: AppBar(
        backgroundColor: _green,
        title: const Text('Meal Log', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabs: _mealTypes.map((m) => Tab(text: m)).toList(),
        ),
      ),
      body: user == null
          ? const Center(child: Text('Please log in'))
          : TabBarView(
              controller: _tabController,
              children: _mealTypes
                  .map((meal) => _MealTab(mealType: meal))
                  .toList(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _green,
        onPressed: _openAddFoodSheet,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Food', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

// ── Per-meal tab ──────────────────────────────────────────────────────────
class _MealTab extends StatelessWidget {
  final String mealType;
  const _MealTab({required this.mealType});

  static const Color _green = Color(0xFF2C6E49);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('foodLogs')
          .where('mealType', isEqualTo: mealType)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(
            child: Text('Error: ${snap.error}',
                style: const TextStyle(color: Colors.red)),
          );
        }

        final now   = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final tomorrow = today.add(const Duration(days: 1));

        final allDocs = snap.data?.docs ?? [];
        final docs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final ts = (data['timestamp'] as Timestamp?)?.toDate();
          if (ts == null) return true;
          return ts.isAfter(today) && ts.isBefore(tomorrow);
        }).toList()
          ..sort((a, b) {
            final aTs = ((a.data() as Map)['timestamp'] as Timestamp?)?.toDate();
            final bTs = ((b.data() as Map)['timestamp'] as Timestamp?)?.toDate();
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

        double totalCal = 0, totalCarbs = 0, totalProtein = 0,
               totalFat = 0, totalSugar = 0;
        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          final n = d['nutrition'] as Map<String, dynamic>? ?? {};
          totalCal     += _d(n['calories']);
          totalCarbs   += _d(n['carbs']);
          totalProtein += _d(n['protein']);
          totalFat     += _d(n['fat']);
          totalSugar   += _d(n['sugar']);
        }

        return Column(
          children: [
            if (docs.isNotEmpty)
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _green.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$mealType Summary',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _green)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _summaryChip('🔥 ${totalCal.toStringAsFixed(0)} kcal', Colors.orange),
                        _summaryChip('🍞 ${totalCarbs.toStringAsFixed(1)}g carbs', Colors.blue),
                        _summaryChip('💪 ${totalProtein.toStringAsFixed(1)}g protein', Colors.purple),
                        _summaryChip('🧈 ${totalFat.toStringAsFixed(1)}g fat', Colors.brown),
                        _summaryChip('🍬 ${totalSugar.toStringAsFixed(1)}g sugar', Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
            Expanded(
              child: docs.isEmpty
                  ? _emptyState(mealType)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                      itemCount: docs.length,
                      itemBuilder: (ctx, i) {
                        final doc  = docs[i];
                        final data = doc.data() as Map<String, dynamic>;
                        return _FoodLogCard(
                          data: data,
                          docId: doc.id,
                          userId: user.uid,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState(String meal) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restaurant_menu, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No $meal logged today',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          Text('Tap + Add Food to log your $meal',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
}

// ── Food log card with visible DELETE button ───────────────────────────────
class _FoodLogCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String userId;

  const _FoodLogCard({
    required this.data,
    required this.docId,
    required this.userId,
  });

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final n        = data['nutrition'] as Map<String, dynamic>? ?? {};
    final name     = data['foodName'] ?? 'Unknown Food';
    final imageUrl = data['imageUrl'] ?? '';
    final time     = (data['timestamp'] as Timestamp?)?.toDate();
    final timeStr  = time != null
        ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: imageUrl.isNotEmpty
                      ? Image.network(imageUrl,
                          width: 64, height: 64, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF2C6E49))),
                          ),
                          if (timeStr.isNotEmpty)
                            Text(timeStr,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                      if ((data['portionSize'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text('Portion: ${data['portionSize']}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600)),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (_d(n['calories']) > 0)
                            _chip('🔥 ${_d(n['calories']).toStringAsFixed(0)} kcal', Colors.orange),
                          if (_d(n['carbs']) > 0)
                            _chip('🍞 ${_d(n['carbs']).toStringAsFixed(1)}g carbs', Colors.blue),
                          if (_d(n['protein']) > 0)
                            _chip('💪 ${_d(n['protein']).toStringAsFixed(1)}g protein', Colors.purple),
                          if (_d(n['fat']) > 0)
                            _chip('🧈 ${_d(n['fat']).toStringAsFixed(1)}g fat', Colors.brown),
                          if (_d(n['sugar']) > 0)
                            _chip('🍬 ${_d(n['sugar']).toStringAsFixed(1)}g sugar', Colors.red),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove from log',
                    style: TextStyle(fontSize: 13)),
                onPressed: () => _confirmDelete(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.fastfood, color: Colors.grey),
      );

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.delete_outline, color: Colors.red),
          SizedBox(width: 8),
          Text('Remove Food'),
        ]),
        content: Text(
            'Remove "${data['foodName']}" from your meal log?\n\nThis will also update your nutrient tracking.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('foodLogs')
          .doc(docId)
          .delete();
    }
  }
}

// ── Add Food Bottom Sheet (public — Dashboard can call this directly) ──────
class AddFoodSheet extends StatefulWidget {
  final String preselectedMeal;
  const AddFoodSheet({super.key, required this.preselectedMeal});

  @override
  State<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<AddFoodSheet> {
  static const Color _green = Color(0xFF2C6E49);
  static const List<String> _mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

  final _searchController = TextEditingController();
  String _searchQuery = '';
  late String _selectedMeal;
  bool _isSaving = false;
  String _userDiabetesType = '';

  Map<String, dynamic>? _selectedFood;
  String? _selectedFoodId;

  @override
  void initState() {
    super.initState();
    _selectedMeal = widget.preselectedMeal;
    _loadDiabetesType();
  }

  Future<void> _loadDiabetesType() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(() {
          _userDiabetesType =
              (doc.data()?['diabetesType'] ?? '').toString();
        });
      }
    } catch (e) {
      debugPrint('Error loading diabetes type: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _saveToMealLog() async {
    if (_selectedFood == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      final food = _selectedFood!;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('foodLogs')
          .add({
        'foodName':    food['name'] ?? 'Unknown',
        'mealType':    _selectedMeal,
        'portionSize': food['portionSize'] ?? '',
        'imageUrl':    food['imageUrl'] ?? food['imagePath'] ?? '',
        'diabetesType': food['diabetesType'] ?? '',
        'category':    food['category'] ?? '',
        'manualEntry': true,
        'timestamp':   FieldValue.serverTimestamp(),
        'nutrition': {
          'calories': _d(food['calories']),
          'carbs':    _d(food['carbs']),
          'protein':  _d(food['protein']),
          'fat':      _d(food['fat']),
          'sugar':    _d(food['sugar']),
        },
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ ${food['name']} added to $_selectedMeal!'),
        backgroundColor: _green,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to save: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 1.0,
          expand: false,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle
                const SizedBox(height: 10),
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 14),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle, color: _green),
                      const SizedBox(width: 8),
                      const Text('Add Food to Meal Log',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _green)),
                      const Spacer(),
                      if (_userDiabetesType.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: _green.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.monitor_heart,
                                  size: 12, color: _green),
                              const SizedBox(width: 4),
                              Text(_userDiabetesType,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: _green,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Meal type selector
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Meal Type',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.black54)),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _mealTypes.map((meal) {
                            final selected = _selectedMeal == meal;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedMeal = meal),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? _green
                                        : Colors.grey.shade100,
                                    borderRadius:
                                        BorderRadius.circular(30),
                                    border: Border.all(
                                        color: selected
                                            ? _green
                                            : Colors.grey.shade300),
                                  ),
                                  child: Text(
                                    '${_mealIcon(meal)} $meal',
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : Colors.black54,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(
                        () => _searchQuery = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText:
                          'Search food (e.g. white rice, chicken)...',
                      prefixIcon:
                          const Icon(Icons.search, color: _green),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery  = '';
                                  _selectedFood = null;
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide:
                              BorderSide(color: Colors.grey.shade200)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide:
                              BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                              color: _green, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Selected food preview
                if (_selectedFood != null)
                  _SelectedFoodPreview(
                    food: _selectedFood!,
                    onClear: () => setState(() {
                      _selectedFood   = null;
                      _selectedFoodId = null;
                    }),
                  ),

                // Search results
                Expanded(
                  child: _searchQuery.isEmpty && _selectedFood == null
                      ? _buildHint()
                      : _FoodSearchResults(
                          query: _searchQuery,
                          selectedId: _selectedFoodId,
                          diabetesType: _userDiabetesType,
                          onSelect: (id, food) {
                            setState(() {
                              _selectedFoodId = id;
                              _selectedFood   = food;
                            });
                          },
                        ),
                ),

                // Add button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedFood != null
                            ? _green
                            : Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed:
                          (_selectedFood != null && !_isSaving)
                              ? _saveToMealLog
                              : null,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Icon(Icons.check_circle,
                              color: Colors.white),
                      label: Text(
                        _isSaving
                            ? 'Saving...'
                            : _selectedFood != null
                                ? 'Add "${_selectedFood!['name']}" to $_selectedMeal'
                                : 'Select a food first',
                        style: TextStyle(
                            color: _selectedFood != null
                                ? Colors.white
                                : Colors.grey.shade500,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHint() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 56, color: Colors.grey.shade200),
          const SizedBox(height: 12),
          Text('Search foods for your diet',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
          const SizedBox(height: 4),
          if (_userDiabetesType.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2C6E49).withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Showing foods for $_userDiabetesType Diabetes only',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF2C6E49),
                    fontWeight: FontWeight.w500),
              ),
            )
          else
            Text('e.g. rice, chicken, banana...',
                style: TextStyle(
                    color: Colors.grey.shade300, fontSize: 12)),
        ],
      ),
    );
  }

  String _mealIcon(String meal) {
    switch (meal) {
      case 'Breakfast': return '🌅';
      case 'Lunch':     return '☀️';
      case 'Dinner':    return '🌙';
      case 'Snack':     return '🍎';
      default:          return '🍽️';
    }
  }
}

// ── Food search results ────────────────────────────────────────────────────
class _FoodSearchResults extends StatelessWidget {
  final String query;
  final String? selectedId;
  final String diabetesType;
  final void Function(String id, Map<String, dynamic> food) onSelect;

  const _FoodSearchResults({
    required this.query,
    required this.selectedId,
    required this.diabetesType,
    required this.onSelect,
  });

  static const Color _green = Color(0xFF2C6E49);
  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('food_rules')
          .orderBy('nameLower')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }

        final allDocs = snap.data?.docs ?? [];

        final typeFiltered = diabetesType.isEmpty
            ? allDocs
            : allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return (data['diabetesType'] ?? '') == diabetesType;
              }).toList();

        final filtered = query.isEmpty
            ? typeFiltered
            : typeFiltered.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['nameLower'] ?? '').toString();
                final keywords = (data['searchKeywords'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    [];
                return name.contains(query) ||
                    keywords.any((k) => k.contains(query));
              }).toList();

        if (filtered.isEmpty) {
          // FIX: Wrap in SingleChildScrollView so content doesn't overflow
          // when the keyboard is open and vertical space is reduced
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.no_food,
                        size: 52, color: Colors.red.shade300),
                  ),
                  const SizedBox(height: 16),
                  Text('Food Not Found',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade400)),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      query.isEmpty
                          ? 'No foods found for $diabetesType diabetes type.'
                          : '"$query" is not in the database for $diabetesType diabetes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 13)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline,
                          color: Colors.orange.shade400, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ask your admin to add this food to the database.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          itemCount: filtered.length,
          itemBuilder: (ctx, i) {
            final doc      = filtered[i];
            final data     = doc.data() as Map<String, dynamic>;
            final name     = data['name'] ?? 'Unknown';
            final imageUrl = data['imageUrl'] ?? data['imagePath'] ?? '';
            final isSelected = doc.id == selectedId;
            final isSafe   = (data['category'] ?? '') == 'Do';
            final diabType = data['diabetesType'] ?? '';

            return GestureDetector(
              onTap: () => onSelect(doc.id, data),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _green.withOpacity(0.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isSelected ? _green : Colors.grey.shade200,
                      width: isSelected ? 2 : 1),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: imageUrl.isNotEmpty
                            ? Image.network(imageUrl,
                                width: 56, height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _placeholder())
                            : _placeholder(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(name,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isSelected
                                            ? _green
                                            : Colors.black87)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSafe
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.red.withOpacity(0.1),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isSafe ? '✅ Safe' : '⚠️ Avoid',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: isSafe
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 2,
                              children: [
                                if (_d(data['calories']) > 0)
                                  _miniChip(
                                      '${_d(data['calories']).toStringAsFixed(0)} kcal',
                                      Colors.orange),
                                if (_d(data['carbs']) > 0)
                                  _miniChip(
                                      '${_d(data['carbs']).toStringAsFixed(1)}g carbs',
                                      Colors.blue),
                                if (_d(data['protein']) > 0)
                                  _miniChip(
                                      '${_d(data['protein']).toStringAsFixed(1)}g protein',
                                      Colors.purple),
                                if (_d(data['sugar']) > 0)
                                  _miniChip(
                                      '${_d(data['sugar']).toStringAsFixed(1)}g sugar',
                                      Colors.red),
                              ],
                            ),
                            if (diabType.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text('For $diabType Diabetes',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500)),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.check_circle,
                              color: _green, size: 22),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _placeholder() => Container(
        width: 56, height: 56,
        color: Colors.grey.shade100,
        child: const Icon(Icons.fastfood, color: Colors.grey, size: 28),
      );

  Widget _miniChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w600)),
      );
}

// ── Selected food preview banner ───────────────────────────────────────────
class _SelectedFoodPreview extends StatelessWidget {
  final Map<String, dynamic> food;
  final VoidCallback onClear;

  const _SelectedFoodPreview({required this.food, required this.onClear});

  static const Color _green = Color(0xFF2C6E49);
  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _green.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: _green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Selected: ${food['name']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _green,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (_d(food['calories']) > 0)
                      '${_d(food['calories']).toStringAsFixed(0)} kcal',
                    if (_d(food['carbs']) > 0)
                      '${_d(food['carbs']).toStringAsFixed(1)}g carbs',
                    if (_d(food['protein']) > 0)
                      '${_d(food['protein']).toStringAsFixed(1)}g protein',
                    if (_d(food['fat']) > 0)
                      '${_d(food['fat']).toStringAsFixed(1)}g fat',
                    if (_d(food['sugar']) > 0)
                      '${_d(food['sugar']).toStringAsFixed(1)}g sugar',
                  ].join(' • '),
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}