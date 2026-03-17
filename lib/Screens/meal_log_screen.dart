import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetechapp/health/nutrition_calculator.dart';

// ── Palette — identical to dashboard ────────────────────────────────────────
const _ml_bg      = Color(0xFFF4F7F5);
const _ml_white   = Color(0xFFFFFFFF);
const _ml_green   = Color(0xFF2C6E49);
const _ml_greenLt = Color(0xFF4A9B6F);
const _ml_greenPal= Color(0xFFE8F5EE);
const _ml_red     = Color(0xFFD64045);
const _ml_redPal  = Color(0xFFFDECEC);
const _ml_amber   = Color(0xFFF09D18);
const _ml_amberPal= Color(0xFFFFF4E0);
const _ml_blue    = Color(0xFF2979C6);
const _ml_bluePal = Color(0xFFE8F0FB);
const _ml_teal    = Color(0xFF0D8A7C);
const _ml_tealPal = Color(0xFFE3F5F3);
const _ml_purp    = Color(0xFF7B5EA7);
const _ml_purpPal = Color(0xFFF0EBF8);
const _ml_grey1   = Color(0xFF1A2E22);
const _ml_grey2   = Color(0xFF4D6357);
const _ml_grey3   = Color(0xFF8FA898);
const _ml_grey4   = Color(0xFFD5E2DA);
const _ml_grey5   = Color(0xFFF0F5F2);

// ─────────────────────────────────────────────────────────────────────────────
// MealLogScreen
// ─────────────────────────────────────────────────────────────────────────────
class MealLogScreen extends StatefulWidget {
  const MealLogScreen({super.key});

  @override
  State<MealLogScreen> createState() => _MealLogScreenState();
}

class _MealLogScreenState extends State<MealLogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  static const List<String> _mealTypes = ['Breakfast', 'Lunch', 'Dinner'];

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
        preselectedMeal:
            preselectedMeal ?? _mealTypes[_tabController.index],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _ml_bg,
      body: Column(children: [
        // ── Gradient header — same as dashboard ──────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2C6E49), Color(0xFF4A9B6F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(children: [
              // Title row
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Meal Log',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1)),
                        Text("Today's food entries",
                            style: TextStyle(
                                color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ]),
              ),
              // Tab bar
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3),
                unselectedLabelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500),
                tabs: _mealTypes
                    .map((m) => Tab(
                          icon: Icon(_mealIcon(m), size: 16),
                          text: m,
                        ))
                    .toList(),
              ),
            ]),
          ),
        ),

        // ── Tab body ─────────────────────────────────────────────────
        Expanded(
          child: user == null
              ? const Center(
                  child: Text('Please log in',
                      style: TextStyle(color: _ml_grey3)))
              : TabBarView(
                  controller: _tabController,
                  children: _mealTypes
                      .map((meal) => _MealTab(mealType: meal))
                      .toList(),
                ),
        ),
      ]),

      // ── FAB ──────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _ml_green,
        elevation: 2,
        onPressed: _openAddFoodSheet,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Food',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  IconData _mealIcon(String meal) {
    switch (meal) {
      case 'Breakfast': return Icons.wb_sunny_rounded;
      case 'Lunch':     return Icons.light_mode_rounded;
      case 'Dinner':    return Icons.nights_stay_rounded;
      default:          return Icons.restaurant_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-meal tab
// ─────────────────────────────────────────────────────────────────────────────
class _MealTab extends StatelessWidget {
  final String mealType;
  const _MealTab({required this.mealType});

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

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
        if (snap.connectionState == ConnectionState.waiting)
          return const Center(
              child: CircularProgressIndicator(color: _ml_green));
        if (snap.hasError)
          return Center(
              child: Text('Error: ${snap.error}',
                  style: const TextStyle(color: _ml_red)));

        final now      = DateTime.now();
        final today    = DateTime(now.year, now.month, now.day);
        final tomorrow = today.add(const Duration(days: 1));

        final docs = (snap.data?.docs ?? []).where((doc) {
          final ts = ((doc.data() as Map)['timestamp'] as Timestamp?)
              ?.toDate();
          return ts != null &&
              !ts.isBefore(today) &&
              ts.isBefore(tomorrow);
        }).toList()
          ..sort((a, b) {
            final aTs = ((a.data() as Map)['timestamp'] as Timestamp?)
                ?.toDate();
            final bTs = ((b.data() as Map)['timestamp'] as Timestamp?)
                ?.toDate();
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

        double tCal = 0, tCarbs = 0, tProt = 0, tFat = 0;
        for (final doc in docs) {
          final n = (doc.data() as Map)['nutrition'] as Map<String, dynamic>? ?? {};
          tCal   += _d(n['calories']);
          tCarbs += _d(n['carbs']);
          tProt  += _d(n['protein']);
          tFat   += _d(n['fat']);
        }

        return Column(children: [
          // ── Summary card ────────────────────────────────────────
          if (docs.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _ml_white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color: _ml_greenPal,
                        borderRadius: BorderRadius.circular(9)),
                    child: const Icon(Icons.bar_chart_rounded,
                        color: _ml_green, size: 15),
                  ),
                  const SizedBox(width: 10),
                  Text('$mealType Summary',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _ml_grey1)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _ml_greenPal,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${docs.length} item${docs.length > 1 ? 's' : ''}',
                        style: const TextStyle(
                            fontSize: 10,
                            color: _ml_green,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _nutriSummary('Calories',
                      '${tCal.toStringAsFixed(0)} kcal',
                      _ml_amber, _ml_amberPal)),
                  const SizedBox(width: 8),
                  Expanded(child: _nutriSummary('Carbs',
                      '${tCarbs.toStringAsFixed(1)}g',
                      _ml_blue, _ml_bluePal)),
                  const SizedBox(width: 8),
                  Expanded(child: _nutriSummary('Protein',
                      '${tProt.toStringAsFixed(1)}g',
                      _ml_purp, _ml_purpPal)),
                  const SizedBox(width: 8),
                  Expanded(child: _nutriSummary('Fat',
                      '${tFat.toStringAsFixed(1)}g',
                      _ml_red, _ml_redPal)),
                ]),
              ]),
            ),

          // ── Food list ────────────────────────────────────────────
          Expanded(
            child: docs.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final doc  = docs[i];
                      final data = doc.data() as Map<String, dynamic>;
                      return _FoodLogCard(
                          data: data,
                          docId: doc.id,
                          userId: user.uid);
                    },
                  ),
          ),
        ]);
      },
    );
  }

  Widget _nutriSummary(String label, String value, Color color, Color pal) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: pal,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 9, color: _ml_grey3)),
        ]),
      );

  Widget _emptyState() => Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: _ml_greenPal, shape: BoxShape.circle),
            child: const Icon(Icons.restaurant_menu_rounded,
                size: 48, color: _ml_green),
          ),
          const SizedBox(height: 16),
          Text('No $mealType logged today',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _ml_grey1)),
          const SizedBox(height: 6),
          Text('Tap + Add Food to log your $mealType',
              style: const TextStyle(fontSize: 12, color: _ml_grey3)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Food log card
// ─────────────────────────────────────────────────────────────────────────────
class _FoodLogCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String userId;
  const _FoodLogCard(
      {required this.data, required this.docId, required this.userId});

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final n          = data['nutrition'] as Map<String, dynamic>? ?? {};
    final name       = data['foodName'] ?? 'Unknown Food';
    final imageUrl   = data['imageUrl'] ?? '';
    final time       = (data['timestamp'] as Timestamp?)?.toDate();
    final h          = time?.hour ?? 0;
    final m          = time?.minute.toString().padLeft(2, '0') ?? '00';
    final timeStr    = time != null
        ? '${(h % 12 == 0 ? 12 : h % 12)}:$m ${h >= 12 ? 'PM' : 'AM'}'
        : '';
    final grams      = _d(data['portionGrams']);
    final portionLbl = data['portionLabel']?.toString() ??
        data['portionSize']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _ml_white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Image
            imageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(imageUrl,
                        width: 60, height: 60, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _imgPlaceholder()))
                : _imgPlaceholder(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Name + time
                Row(children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _ml_grey1)),
                  ),
                  if (timeStr.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: _ml_grey5,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(timeStr,
                          style: const TextStyle(
                              fontSize: 10,
                              color: _ml_grey3,
                              fontWeight: FontWeight.w600)),
                    ),
                ]),
                const SizedBox(height: 5),

                // Portion pill
                if (portionLbl.isNotEmpty || grams > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _ml_tealPal,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _ml_teal.withOpacity(0.25)),
                    ),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      const Icon(Icons.scale_rounded,
                          size: 10, color: _ml_teal),
                      const SizedBox(width: 4),
                      Text(
                        portionLbl.isNotEmpty
                            ? portionLbl
                            : '${grams.toInt()}g',
                        style: const TextStyle(
                            fontSize: 10,
                            color: _ml_teal,
                            fontWeight: FontWeight.w700)),
                    ]),
                  ),
                const SizedBox(height: 6),

                // Nutrient chips
                Wrap(spacing: 5, runSpacing: 4, children: [
                  if (_d(n['calories']) > 0)
                    _chip('🔥 ${_d(n['calories']).toStringAsFixed(0)} kcal',
                        _ml_amber, _ml_amberPal),
                  if (_d(n['carbs']) > 0)
                    _chip('🍞 ${_d(n['carbs']).toStringAsFixed(1)}g',
                        _ml_blue, _ml_bluePal),
                  if (_d(n['protein']) > 0)
                    _chip('💪 ${_d(n['protein']).toStringAsFixed(1)}g',
                        _ml_purp, _ml_purpPal),
                  if (_d(n['fat']) > 0)
                    _chip('🧈 ${_d(n['fat']).toStringAsFixed(1)}g',
                        _ml_red, _ml_redPal),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Divider(height: 1, color: _ml_grey4),
          const SizedBox(height: 8),

          // Delete button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _ml_red,
                side: BorderSide(color: _ml_red.withOpacity(0.5)),
                backgroundColor: _ml_redPal,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Remove from log',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              onPressed: () => _confirmDelete(context),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        width: 60, height: 60,
        decoration: BoxDecoration(
            color: _ml_greenPal,
            borderRadius: BorderRadius.circular(10)),
        child:
            const Icon(Icons.fastfood_rounded, color: _ml_green, size: 26),
      );

  Widget _chip(String label, Color color, Color pal) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: pal, borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600)),
      );

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.delete_outline_rounded, color: _ml_red),
          SizedBox(width: 8),
          Text('Remove Food',
              style: TextStyle(color: _ml_grey1)),
        ]),
        content: Text(
          'Remove "${data['foodName']}" from your meal log?\n\n'
          'This will also update your nutrient tracking.',
          style: const TextStyle(color: _ml_grey2, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: _ml_grey3))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _ml_red,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
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

// ─────────────────────────────────────────────────────────────────────────────
// Add Food Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class AddFoodSheet extends StatefulWidget {
  final String preselectedMeal;
  const AddFoodSheet({super.key, required this.preselectedMeal});

  @override
  State<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<AddFoodSheet> {
  static const List<String> _mealTypes = ['Breakfast', 'Lunch', 'Dinner'];

  final _searchController = TextEditingController();
  String _searchQuery     = '';
  late String _selectedMeal;
  bool _isSaving          = false;

  String _userDiabetesType   = '';
  double? _userHeight;
  double? _userWeight;
  String  _userActivityLevel = 'Light';

  Map<String, dynamic>? _selectedFood;
  String? _selectedFoodId;

  @override
  void initState() {
    super.initState();
    _selectedMeal = widget.preselectedMeal;
    _loadUserProfile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      final d = doc.data() ?? {};
      setState(() {
        _userDiabetesType  = (d['diabetesType']  ?? '').toString();
        _userHeight        = double.tryParse(d['height']?.toString()  ?? '');
        _userWeight        = double.tryParse(d['weight']?.toString()  ?? '');
        _userActivityLevel = (d['activityLevel'] ?? 'Light').toString();
      });
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  PersonalizedNutrition _calcNutrition(Map<String, dynamic> food) =>
      NutritionCalculator.calculate(
        heightCm:      _userHeight,
        weightKg:      _userWeight,
        activityLevel: _userActivityLevel,
        diabetesType:  _userDiabetesType,
        calories100g:  _d(food['calories']),
        carbs100g:     _d(food['carbs']),
        protein100g:   _d(food['protein']),
        fat100g:       _d(food['fat']),
      );

  Future<void> _saveToMealLog() async {
    if (_selectedFood == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isSaving = true);
    try {
      final food   = _selectedFood!;
      final result = _calcNutrition(food);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('foodLogs')
          .add({
        'foodName':     food['name'] ?? 'Unknown',
        'mealType':     _selectedMeal,
        'portionSize':  result.portionLabel,
        'portionGrams': result.grams,
        'imageUrl':     food['imageUrl'] ?? food['imagePath'] ?? '',
        'diabetesType': food['diabetesType'] ?? '',
        'category':     food['category'] ?? '',
        'manualEntry':  true,
        'timestamp':    Timestamp.fromDate(DateTime.now()),
        'nutrition': {
          'calories': result.calories,
          'carbs':    result.carbs,
          'protein':  result.protein,
          'fat':      result.fat,
        },
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '✅ ${food['name']} (${result.grams.toInt()}g) added to $_selectedMeal!'),
        backgroundColor: _ml_green,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: _ml_red));
    }
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  String _mealEmoji(String meal) {
    switch (meal) {
      case 'Breakfast': return '🌅';
      case 'Lunch':     return '☀️';
      case 'Dinner':    return '🌙';
      default:          return '🍽️';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final result =
        _selectedFood != null ? _calcNutrition(_selectedFood!) : null;

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
              color: _ml_white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(children: [
              const SizedBox(height: 10),
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: _ml_grey4,
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),

              // ── Sheet header ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: _ml_greenPal,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.add_rounded,
                        color: _ml_green, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add Food to Meal Log',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _ml_grey1)),
                        Text('Search and select a food item',
                            style: TextStyle(
                                fontSize: 11, color: _ml_grey3)),
                      ],
                    ),
                  ),
                  if (_userDiabetesType.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _ml_greenPal,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _ml_green.withOpacity(0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min,
                          children: [
                        const Icon(Icons.monitor_heart_rounded,
                            size: 11, color: _ml_green),
                        const SizedBox(width: 4),
                        Text(_userDiabetesType,
                            style: const TextStyle(
                                fontSize: 10,
                                color: _ml_green,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                ]),
              ),

              // ── Profile pill ─────────────────────────────────────
              if (_userHeight != null && _userWeight != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _ml_tealPal,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _ml_teal.withOpacity(0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min,
                        children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 11, color: _ml_teal),
                      const SizedBox(width: 5),
                      Text(
                        'Portions for ${_userHeight!.toInt()}cm · '
                        '${_userWeight!.toInt()}kg · $_userActivityLevel',
                        style: const TextStyle(
                            fontSize: 10,
                            color: _ml_teal,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 14),

              // ── Meal type selector ───────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Meal Type',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: _ml_grey2)),
                  const SizedBox(height: 8),
                  Row(
                    children: _mealTypes.map((meal) {
                      final sel = _selectedMeal == meal;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedMeal = meal),
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10),
                              decoration: BoxDecoration(
                                color: sel
                                    ? _ml_green
                                    : _ml_grey5,
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                    color: sel
                                        ? _ml_green
                                        : _ml_grey4),
                              ),
                              child: Column(children: [
                                Text(_mealEmoji(meal),
                                    style: const TextStyle(
                                        fontSize: 16)),
                                const SizedBox(height: 2),
                                Text(meal,
                                    style: TextStyle(
                                        color: sel
                                            ? Colors.white
                                            : _ml_grey2,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11)),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ]),
              ),
              const SizedBox(height: 12),

              // ── Search bar ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(
                      () => _searchQuery = v.trim().toLowerCase()),
                  style: const TextStyle(
                      color: _ml_grey1, fontSize: 14),
                  decoration: InputDecoration(
                    hintText:
                        'Search food (e.g. white rice, chicken)...',
                    hintStyle: const TextStyle(
                        color: _ml_grey3, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: _ml_green, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                color: _ml_grey3, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery  = '';
                                _selectedFood = null;
                              });
                            })
                        : null,
                    filled: true,
                    fillColor: _ml_grey5,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _ml_grey4)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _ml_grey4)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: _ml_green, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ── Selected food preview ────────────────────────────
              if (_selectedFood != null && result != null)
                _SelectedFoodPreview(
                  food: _selectedFood!,
                  result: result,
                  onClear: () => setState(() {
                    _selectedFood   = null;
                    _selectedFoodId = null;
                  }),
                ),

              // ── Search results ───────────────────────────────────
              Expanded(
                child: _searchQuery.isEmpty && _selectedFood == null
                    ? _buildHint()
                    : _FoodSearchResults(
                        query:         _searchQuery,
                        selectedId:    _selectedFoodId,
                        diabetesType:  _userDiabetesType,
                        userHeight:    _userHeight,
                        userWeight:    _userWeight,
                        activityLevel: _userActivityLevel,
                        onSelect: (id, food) => setState(() {
                          _selectedFoodId = id;
                          _selectedFood   = food;
                        }),
                      ),
              ),

              // ── Add button ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedFood != null
                          ? _ml_green
                          : _ml_grey4,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: (_selectedFood != null && !_isSaving)
                        ? _saveToMealLog
                        : null,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : Icon(
                            _selectedFood != null
                                ? Icons.check_circle_rounded
                                : Icons.touch_app_rounded,
                            color: Colors.white, size: 18),
                    label: Text(
                      _isSaving
                          ? 'Saving...'
                          : result != null
                              ? 'Add "${_selectedFood!['name']}" · '
                                '${result.grams.toInt()}g to $_selectedMeal'
                              : 'Select a food first',
                      style: TextStyle(
                          color: _selectedFood != null
                              ? Colors.white
                              : _ml_grey3,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildHint() => Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: _ml_greenPal, shape: BoxShape.circle),
            child: const Icon(Icons.search_rounded,
                size: 40, color: _ml_green),
          ),
          const SizedBox(height: 14),
          const Text('Search for a food',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _ml_grey1)),
          const SizedBox(height: 4),
          if (_userDiabetesType.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _ml_greenPal,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _ml_green.withOpacity(0.3)),
              ),
              child: Text(
                'Showing foods for $_userDiabetesType Diabetes',
                style: const TextStyle(
                    fontSize: 11,
                    color: _ml_green,
                    fontWeight: FontWeight.w600),
              ),
            ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Selected food preview
// ─────────────────────────────────────────────────────────────────────────────
class _SelectedFoodPreview extends StatelessWidget {
  final Map<String, dynamic> food;
  final PersonalizedNutrition result;
  final VoidCallback onClear;
  const _SelectedFoodPreview(
      {required this.food, required this.result, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _ml_greenPal,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ml_green.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded,
            color: _ml_green, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('${food['name']}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _ml_green,
                    fontSize: 13)),
            const SizedBox(height: 4),
            // Portion pill
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: result.isPersonalized
                    ? _ml_tealPal
                    : _ml_grey5,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: result.isPersonalized
                      ? _ml_teal.withOpacity(0.3)
                      : _ml_grey4,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    result.isPersonalized
                        ? Icons.auto_awesome_rounded
                        : Icons.scale_rounded,
                    size: 9,
                    color: result.isPersonalized
                        ? _ml_teal
                        : _ml_grey3),
                const SizedBox(width: 3),
                Text(result.portionLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: result.isPersonalized
                            ? _ml_teal
                            : _ml_grey2)),
              ]),
            ),
            const SizedBox(height: 4),
            Text(
              '🔥 ${result.calories.toStringAsFixed(0)} kcal  '
              '🍞 ${result.carbs.toStringAsFixed(1)}g  '
              '💪 ${result.protein.toStringAsFixed(1)}g  '
              '🧈 ${result.fat.toStringAsFixed(1)}g',
              style: const TextStyle(fontSize: 10, color: _ml_grey2),
            ),
            if (result.isPersonalized) ...[
              const SizedBox(height: 3),
              const Text(
                '✨ Calculated for your profile',
                style: TextStyle(
                    fontSize: 9,
                    color: _ml_teal,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded,
              size: 17, color: _ml_grey3),
          onPressed: onClear,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Food search results
// ─────────────────────────────────────────────────────────────────────────────
class _FoodSearchResults extends StatelessWidget {
  final String  query;
  final String? selectedId;
  final String  diabetesType;
  final double? userHeight;
  final double? userWeight;
  final String  activityLevel;
  final void Function(String id, Map<String, dynamic> food) onSelect;

  const _FoodSearchResults({
    required this.query,
    required this.selectedId,
    required this.diabetesType,
    required this.userHeight,
    required this.userWeight,
    required this.activityLevel,
    required this.onSelect,
  });

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('food_rules')
          .orderBy('nameLower')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting)
          return const Center(
              child: CircularProgressIndicator(color: _ml_green));
        if (snap.hasError)
          return Center(child: Text('Error: ${snap.error}'));

        final all = snap.data?.docs ?? [];
        final typeFiltered = diabetesType.isEmpty
            ? all
            : all.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return (d['diabetesType'] ?? '') == diabetesType;
              }).toList();

        final filtered = query.isEmpty
            ? typeFiltered
            : typeFiltered.where((doc) {
                final d   = doc.data() as Map<String, dynamic>;
                final n   = (d['nameLower'] ?? '').toString();
                final kws = (d['searchKeywords'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    [];
                return n.contains(query) ||
                    kws.any((k) => k.contains(query));
              }).toList();

        if (filtered.isEmpty) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: _ml_redPal, shape: BoxShape.circle),
                child: const Icon(Icons.no_food_rounded,
                    size: 44, color: _ml_red),
              ),
              const SizedBox(height: 16),
              const Text('Food Not Found',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ml_grey1)),
              const SizedBox(height: 6),
              Text(
                query.isEmpty
                    ? 'No foods found for $diabetesType diabetes.'
                    : '"$query" is not in the database for $diabetesType diabetes.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _ml_grey3, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _ml_amberPal,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _ml_amber.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: _ml_amber, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Ask your admin to add this food to the database.',
                      style: TextStyle(
                          fontSize: 11, color: _ml_grey2),
                    ),
                  ),
                ]),
              ),
            ]),
          );
        }

        return ListView.builder(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          itemCount: filtered.length,
          itemBuilder: (ctx, i) {
            final doc      = filtered[i];
            final data     = doc.data() as Map<String, dynamic>;
            final name     = data['name'] ?? 'Unknown';
            final imageUrl =
                data['imageUrl'] ?? data['imagePath'] ?? '';
            final isSel  = doc.id == selectedId;
            final isSafe = (data['category'] ?? '') == 'Do';
            final diabType = data['diabetesType'] ?? '';

            final result = NutritionCalculator.calculate(
              heightCm:      userHeight,
              weightKg:      userWeight,
              activityLevel: activityLevel,
              diabetesType:  diabetesType,
              calories100g:  _d(data['calories']),
              carbs100g:     _d(data['carbs']),
              protein100g:   _d(data['protein']),
              fat100g:       _d(data['fat']),
            );

            return GestureDetector(
              onTap: () => onSelect(doc.id, data),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color:
                      isSel ? _ml_greenPal : _ml_white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isSel ? _ml_green : _ml_grey4,
                      width: isSel ? 1.5 : 1),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    // Image
                    imageUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius:
                                BorderRadius.circular(10),
                            child: Image.network(imageUrl,
                                width: 54, height: 54,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _imgPh()))
                        : _imgPh(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                        // Name + safe/avoid badge
                        Row(children: [
                          Expanded(
                            child: Text(name,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: isSel
                                        ? _ml_green
                                        : _ml_grey1)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSafe
                                  ? _ml_greenPal
                                  : _ml_redPal,
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: Text(
                                isSafe ? '✅ Safe' : '⚠️ Avoid',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: isSafe
                                        ? _ml_green
                                        : _ml_red,
                                    fontWeight:
                                        FontWeight.w700)),
                          ),
                        ]),
                        const SizedBox(height: 4),

                        // Portion pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: result.isPersonalized
                                ? _ml_tealPal
                                : _ml_grey5,
                            borderRadius:
                                BorderRadius.circular(8),
                            border: Border.all(
                                color: result.isPersonalized
                                    ? _ml_teal.withOpacity(0.3)
                                    : _ml_grey4),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            Icon(
                                result.isPersonalized
                                    ? Icons.auto_awesome_rounded
                                    : Icons.scale_rounded,
                                size: 9,
                                color: result.isPersonalized
                                    ? _ml_teal
                                    : _ml_grey3),
                            const SizedBox(width: 3),
                            Text(
                                'Your portion: ${result.portionLabel}',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: result.isPersonalized
                                        ? _ml_teal
                                        : _ml_grey2)),
                          ]),
                        ),
                        const SizedBox(height: 4),

                        // Nutrient chips
                        Wrap(spacing: 4, runSpacing: 3,
                            children: [
                          if (result.calories > 0)
                            _chip('🔥 ${result.calories.toStringAsFixed(0)} kcal',
                                _ml_amber, _ml_amberPal),
                          if (result.carbs > 0)
                            _chip('🍞 ${result.carbs.toStringAsFixed(1)}g',
                                _ml_blue, _ml_bluePal),
                          if (result.protein > 0)
                            _chip('💪 ${result.protein.toStringAsFixed(1)}g',
                                _ml_purp, _ml_purpPal),
                          if (result.fat > 0)
                            _chip('🧈 ${result.fat.toStringAsFixed(1)}g',
                                _ml_red, _ml_redPal),
                        ]),
                        const SizedBox(height: 3),
                        Text(
                            'Base: ${_d(data['calories']).toStringAsFixed(0)} kcal per 100g',
                            style: const TextStyle(
                                fontSize: 9,
                                color: _ml_grey3,
                                fontStyle: FontStyle.italic)),
                        if (diabType.isNotEmpty)
                          Text('For $diabType Diabetes',
                              style: const TextStyle(
                                  fontSize: 9, color: _ml_grey3)),
                      ]),
                    ),
                    if (isSel)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.check_circle_rounded,
                            color: _ml_green, size: 20),
                      ),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _imgPh() => Container(
        width: 54, height: 54,
        decoration: BoxDecoration(
            color: _ml_greenPal,
            borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.fastfood_rounded,
            color: _ml_green, size: 24),
      );

  Widget _chip(String label, Color color, Color pal) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: pal, borderRadius: BorderRadius.circular(7)),
        child: Text(label,
            style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w600)),
      );
}