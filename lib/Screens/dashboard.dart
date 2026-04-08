import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetechapp/Screens/edit_profile.dart';
import 'package:diabetechapp/Screens/foodscanner.dart';
import 'package:diabetechapp/Screens/log_in.dart';
import 'package:diabetechapp/Screens/meal_log_screen.dart';
import 'package:diabetechapp/health/goal_progress.dart';
import 'package:diabetechapp/health/do_dont_foods_screen.dart';
import 'package:diabetechapp/health/nutrition_calculator.dart';
import 'feedback_screen.dart';

class _DiabetesNutrientGoals {
  final double calories;
  final double carbs;
  final double protein;
  final double fat;
  const _DiabetesNutrientGoals({
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
  });
}

// Static fallback goals (used only when height/weight not set)
const Map<String, _DiabetesNutrientGoals> _diabetesGoals = {
  'Mild': _DiabetesNutrientGoals(
    calories: 1800,
    carbs: 150,
    protein: 65,
    fat: 55,
  ),
  'Severe': _DiabetesNutrientGoals(
    calories: 1400,
    carbs: 100,
    protein: 60,
    fat: 45,
  ),
};

const _defaultGoals = _DiabetesNutrientGoals(
  calories: 1800,
  carbs: 150,
  protein: 60,
  fat: 50,
);

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  User? user;
  int _currentIndex = 0;

  double caloriesProgress = 0.0;
  double carbsProgress = 0.0;
  double proteinProgress = 0.0;
  double fatProgress = 0.0;
  double weeklyGoalProgress = 0.0;

  double todayCalories = 0;
  double todayCarbs = 0;
  double todayProtein = 0;
  double todayFat = 0;

  String diabetesType = 'Loading...';
  String? profilePictureUrl;
  List<Map<String, dynamic>> recentScans = [];
  List<Map<String, dynamic>> filteredScans = [];
  String scanDateFilter = 'All'; // All, Today, This Week, This Month

  double? userHeight;
  double? userWeight;
  String? activityLevel;

  double dailyCalorieGoal = 1800;
  double dailyCarbGoal = 150;
  double dailyProteinGoal = 60;
  double dailyFatGoal = 50;
  double weeklyScanGoal = 10;

  // Weekly nutrient tracking (last 7 days)
  double weeklyCalories = 0;
  double weeklyCarbs = 0;
  double weeklyProtein = 0;
  double weeklyFat = 0;
  double avgDailyCalories = 0;
  double avgDailyCarbs = 0;
  double avgDailyProtein = 0;
  double avgDailyFat = 0;

  static const double _cautionThreshold = 0.75;
  static const double _dangerThreshold = 1.0;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Map<String, Map<String, dynamic>> _activityConfig = {
    'Sedentary': {'icon': Icons.weekend, 'color': Color(0xFF9E9E9E)},
    'Light': {'icon': Icons.directions_walk, 'color': Color(0xFF42A546)},
    'Very Active': {'icon': Icons.directions_run, 'color': Color(0xFFE53935)},
  };

  static const Map<String, Map<String, String>> _activityDetails = {
    'Sedentary': {
      'desc':
          'Little or no physical activity. Mostly sitting or lying down throughout the day.',
      'examples':
          '🛋️ Resting  •  📺 Watching TV  •  💻 Desk work with no movement',
    },
    'Light': {
      'desc': 'Minimal movement with light physical tasks during the day.',
      'examples': '🏢 Office work  •  🚗 Driving  •  🧹 Light house chores',
    },
    'Very Active': {
      'desc':
          'Extensive and rapid movements with high physical demands all day.',
      'examples':
          '🏃 Running  •  🏗️ Heavy labor  •  📦 Carrying heavy objects extensively',
    },
  };

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _fetchDashboardData();
      _fetchUserProfile();
    }
  }

  Future<void> _fetchUserProfile() async {
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user!.uid).get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      setState(() {
        diabetesType = (data['diabetesType'] ?? 'Not set').toString();
        userHeight = double.tryParse(data['height']?.toString() ?? '');
        userWeight = double.tryParse(data['weight']?.toString() ?? '');
        activityLevel = data['activityLevel']?.toString();
        profilePictureUrl =
            data['profilePictureUrl'] ??
            data['photoUrl'] ??
            data['profilePicture'] ??
            data['profileImage'] ??
            data['imageUrl'];
      });
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      setState(() => diabetesType = 'Error loading type');
    }
  }

  // ── UPGRADED: Uses NutritionCalculator.dailyGoals() when profile complete ──
  _DiabetesNutrientGoals _resolveGoals(
    String type,
    Map<String, dynamic> userData,
  ) {
    // 1. Manual override from Firestore takes highest priority
    if (userData.containsKey('dailyCalorieGoal')) {
      return _DiabetesNutrientGoals(
        calories:
            (userData['dailyCalorieGoal'] ?? _defaultGoals.calories).toDouble(),
        carbs: (userData['dailyCarbGoal'] ?? _defaultGoals.carbs).toDouble(),
        protein:
            (userData['dailyProteinGoal'] ?? _defaultGoals.protein).toDouble(),
        fat: (userData['dailyFatGoal'] ?? _defaultGoals.fat).toDouble(),
      );
    }
    // 2. Personalized BMR + TDEE goals when height/weight available
    final h = double.tryParse(userData['height']?.toString() ?? '');
    final w = double.tryParse(userData['weight']?.toString() ?? '');
    final al = userData['activityLevel']?.toString() ?? 'Light';
    if (h != null && w != null && h > 0 && w > 0) {
      final g = NutritionCalculator.dailyGoals(h, w, al, type);
      debugPrint(
        'Goals → BMR+TDEE | Cal:${g.calories} Carbs:${g.carbs} '
        'Prot:${g.protein} Fat:${g.fat}',
      );
      return _DiabetesNutrientGoals(
        calories: g.calories,
        carbs: g.carbs,
        protein: g.protein,
        fat: g.fat,
      );
    }
    // 3. Fallback to static table
    debugPrint('Goals → static fallback for $type');
    return _diabetesGoals[type] ?? _defaultGoals;
  }

  Future<void> _fetchDashboardData() async {
    if (user == null) return;
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final tomorrowMidnight = todayMidnight.add(const Duration(days: 1));

    double cal = 0, carbs = 0, protein = 0, fat = 0;
    int weekScans = 0;
    _DiabetesNutrientGoals goals = _defaultGoals;
    double scanGoal = 10;

    try {
      final userDoc = await _firestore.collection('users').doc(user!.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      final type = (userData['diabetesType'] ?? diabetesType).toString();
      goals = _resolveGoals(type, userData);
      scanGoal = (userData['weeklyScanGoal'] ?? 10).toDouble();

      final foodLogsSnap =
          await _firestore
              .collection('users')
              .doc(user!.uid)
              .collection('foodLogs')
              .get();

      // Weekly tracking variables
      double weeklyCal = 0, weeklyCarb = 0, weeklyProt = 0, weeklyFt = 0;
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      for (var doc in foodLogsSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        final entryTime = ts ?? now;

        // Today's totals
        final isToday =
            !entryTime.isBefore(todayMidnight) &&
            entryTime.isBefore(tomorrowMidnight);
        if (isToday) {
          final nutrition = data['nutrition'] as Map<String, dynamic>? ?? {};
          cal += _d(nutrition['calories']);
          carbs += _d(nutrition['carbs']);
          protein += _d(nutrition['protein']);
          fat += _d(nutrition['fat']);
        }

        // Last 7 days totals
        if (ts != null && ts.isAfter(sevenDaysAgo)) {
          final nutrition = data['nutrition'] as Map<String, dynamic>? ?? {};
          weeklyCal += _d(nutrition['calories']);
          weeklyCarb += _d(nutrition['carbs']);
          weeklyProt += _d(nutrition['protein']);
          weeklyFt += _d(nutrition['fat']);
        }

        // Weekly scan count
        if (ts != null &&
            (data['imagePath'] != null || data['scannedFood'] == true)) {
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          if (ts.isAfter(weekStart)) weekScans++;
        }
      }

      if (mounted) {
        setState(() {
          dailyCalorieGoal = goals.calories;
          dailyCarbGoal = goals.carbs;
          dailyProteinGoal = goals.protein;
          dailyFatGoal = goals.fat;
          weeklyScanGoal = scanGoal;
          todayCalories = cal;
          todayCarbs = carbs;
          todayProtein = protein;
          todayFat = fat;

          // Weekly totals and averages
          weeklyCalories = weeklyCal;
          weeklyCarbs = weeklyCarb;
          weeklyProtein = weeklyProt;
          weeklyFat = weeklyFt;
          avgDailyCalories = weeklyCal / 7;
          avgDailyCarbs = weeklyCarb / 7;
          avgDailyProtein = weeklyProt / 7;
          avgDailyFat = weeklyFt / 7;

          caloriesProgress =
              goals.calories > 0 ? (cal / goals.calories).clamp(0.0, 1.5) : 0.0;
          carbsProgress =
              goals.carbs > 0 ? (carbs / goals.carbs).clamp(0.0, 1.5) : 0.0;
          proteinProgress =
              goals.protein > 0
                  ? (protein / goals.protein).clamp(0.0, 1.5)
                  : 0.0;
          fatProgress = goals.fat > 0 ? (fat / goals.fat).clamp(0.0, 1.5) : 0.0;
          weeklyGoalProgress =
              scanGoal > 0 ? (weekScans / scanGoal).clamp(0.0, 1.0) : 0.0;
        });
        _checkNutrientWarnings(cal, carbs, fat, goals);
      }
    } catch (e) {
      debugPrint('❌ Error fetching foodLogs: $e');
    }

    try {
      final scannedFoodsSnap =
          await _firestore
              .collection('users')
              .doc(user!.uid)
              .collection('scanned_foods')
              .get();
      final fetchedScans =
          scannedFoodsSnap.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final ts = (d['timestamp'] as Timestamp?)?.toDate();
            return {
              'name': d['food'] ?? d['foodName'] ?? d['name'] ?? 'Unknown',
              'timestamp': ts,
            };
          }).toList();
      fetchedScans.sort((a, b) {
        final aTs = a['timestamp'] as DateTime?;
        final bTs = b['timestamp'] as DateTime?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });
      if (mounted) {
        setState(() {
          recentScans = fetchedScans;
          _applyDateFilter();
        });
      }
    } catch (e) {
      debugPrint('❌ Error fetching scanned_foods: $e');
    }
  }

  void _applyDateFilter() {
    final now = DateTime.now();
    List<Map<String, dynamic>> filtered = [];

    switch (scanDateFilter) {
      case 'Today':
        final todayStart = DateTime(now.year, now.month, now.day);
        filtered =
            recentScans.where((scan) {
              final ts = scan['timestamp'] as DateTime?;
              return ts != null && ts.isAfter(todayStart);
            }).toList();
        break;
      case 'This Week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        filtered =
            recentScans.where((scan) {
              final ts = scan['timestamp'] as DateTime?;
              return ts != null && ts.isAfter(weekStart);
            }).toList();
        break;
      case 'This Month':
        final monthStart = DateTime(now.year, now.month, 1);
        filtered =
            recentScans.where((scan) {
              final ts = scan['timestamp'] as DateTime?;
              return ts != null && ts.isAfter(monthStart);
            }).toList();
        break;
      default: // 'All'
        filtered = recentScans;
    }

    setState(() => filteredScans = filtered);
  }

  void _checkNutrientWarnings(
    double cal,
    double carbs,
    double fat,
    _DiabetesNutrientGoals goals,
  ) {
    final exceeded = <String>[];
    if (cal > goals.calories)
      exceeded.add(
        '🔥 Calories (${cal.toStringAsFixed(0)} / ${goals.calories.toInt()} kcal)',
      );
    if (carbs > goals.carbs)
      exceeded.add(
        '🍞 Carbs (${carbs.toStringAsFixed(1)} / ${goals.carbs.toInt()} g)',
      );
    if (fat > goals.fat)
      exceeded.add(
        '🧈 Fat (${fat.toStringAsFixed(1)} / ${goals.fat.toInt()} g)',
      );
    if (exceeded.isEmpty || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Nutrient Alert!',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You exceeded your $diabetesType diabetes daily limits:',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 10),
                  ...exceeded.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.circle, color: Colors.red, size: 8),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      '⚠️ As a $diabetesType diabetic, exceeding these limits may significantly spike your blood sugar.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C6E49),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Got it',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
      );
    });
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to log out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Logout'),
              ),
            ],
          ),
    );
    if (ok == true) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  Color _nutrientColor(double progress, Color defaultColor) {
    if (progress >= _dangerThreshold) return Colors.red;
    if (progress >= _cautionThreshold) return Colors.orange;
    return defaultColor;
  }

  void _showActivityDetail() {
    if (activityLevel == null) return;
    final cfg = _activityConfig[activityLevel!];
    final detail = _activityDetails[activityLevel!];
    if (cfg == null || detail == null) return;
    final color = cfg['color'] as Color;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (_) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(cfg['icon'] as IconData, color: color, size: 32),
                ),
                const SizedBox(height: 14),
                Text(
                  activityLevel!,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail['desc']!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Examples:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        detail['examples']!,
                        style: TextStyle(
                          fontSize: 13,
                          color: color.withOpacity(0.9),
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Got it',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(body: Center(child: Text('No user logged in.')));
    }
    final name = user?.displayName ?? 'User';
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildHeader(name),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _fetchUserProfile();
                await _fetchDashboardData();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -20),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Today's Nutrients ─────────────────────────
                            _sLabel("Today's Nutrient Tracking"),
                            const SizedBox(height: 8),
                            _buildGoalsInfoStrip(),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Swipe to see all  •  Log meals to update',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _grey3,
                                    ),
                                  ),
                                ),
                                _legendDot2(Colors.green, 'OK'),
                                const SizedBox(width: 6),
                                _legendDot2(Colors.orange, 'Caution'),
                                const SizedBox(width: 6),
                                _legendDot2(Colors.red, 'Exceeded'),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 150,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                children: [
                                  _nutrientCard(
                                    'Calories',
                                    caloriesProgress,
                                    Colors.orange,
                                    '${todayCalories.toStringAsFixed(0)}\n${dailyCalorieGoal.toInt()} kcal',
                                  ),
                                  _nutrientCard(
                                    'Carbs',
                                    carbsProgress,
                                    _blue,
                                    '${todayCarbs.toStringAsFixed(1)}\n${dailyCarbGoal.toInt()}g',
                                  ),
                                  _nutrientCard(
                                    'Protein',
                                    proteinProgress,
                                    _purp,
                                    '${todayProtein.toStringAsFixed(1)}\n${dailyProteinGoal.toInt()}g',
                                  ),
                                  _nutrientCard(
                                    'Fat',
                                    fatProgress,
                                    _amber,
                                    '${todayFat.toStringAsFixed(1)}\n${dailyFatGoal.toInt()}g',
                                  ),
                                ],
                              ),
                            ),
                            _buildStatusBanner(),
                            const SizedBox(height: 20),

                            // ── Quick Log ─────────────────────────────────
                            _buildQuickLogCard(),
                            const SizedBox(height: 20),

                            // ── Weekly Nutrient Trends ───────────────────
                            _sLabel('Weekly Nutrient Trends (Last 7 Days)'),
                            const SizedBox(height: 10),
                            _wCard(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Weekly totals header
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Total Intake',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _grey1,
                                        ),
                                      ),
                                      Text(
                                        'Avg/Day',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _grey3,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Calories
                                  _weeklyNutrientRow(
                                    'Calories',
                                    weeklyCalories,
                                    dailyCalorieGoal * 7,
                                    'kcal',
                                    Colors.orange,
                                  ),
                                  const SizedBox(height: 10),

                                  // Carbs
                                  _weeklyNutrientRow(
                                    'Carbs',
                                    weeklyCarbs,
                                    dailyCarbGoal * 7,
                                    'g',
                                    Colors.blue,
                                  ),
                                  const SizedBox(height: 10),

                                  // Protein
                                  _weeklyNutrientRow(
                                    'Protein',
                                    weeklyProtein,
                                    dailyProteinGoal * 7,
                                    'g',
                                    Colors.purple,
                                  ),
                                  const SizedBox(height: 10),

                                  // Fat
                                  _weeklyNutrientRow(
                                    'Fat',
                                    weeklyFat,
                                    dailyFatGoal * 7,
                                    'g',
                                    Colors.red,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ── Recent Food Scans ─────────────────────────
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _sLabel('Recent Food Scans'),
                                IconButton(
                                  icon: const Icon(
                                    Icons.calendar_today,
                                    size: 20,
                                  ),
                                  color: _green,
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                      builder: (context, child) {
                                        return Theme(
                                          data: Theme.of(context).copyWith(
                                            colorScheme:
                                                const ColorScheme.light(
                                                  primary: _green,
                                                  onPrimary: Colors.white,
                                                  onSurface: _grey1,
                                                ),
                                          ),
                                          child: child!,
                                        );
                                      },
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        scanDateFilter = 'Custom';
                                        filteredScans =
                                            recentScans.where((scan) {
                                              final ts =
                                                  scan['timestamp']
                                                      as DateTime?;
                                              if (ts == null) return false;
                                              return ts.year == picked.year &&
                                                  ts.month == picked.month &&
                                                  ts.day == picked.day;
                                            }).toList();
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Date filter chips
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children:
                                    ['All', 'Today', 'This Week', 'This Month']
                                        .map(
                                          (filter) => Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: FilterChip(
                                              label: Text(filter),
                                              selected:
                                                  scanDateFilter == filter,
                                              onSelected: (selected) {
                                                setState(() {
                                                  scanDateFilter = filter;
                                                  _applyDateFilter();
                                                });
                                              },
                                              selectedColor: _green.withOpacity(
                                                0.2,
                                              ),
                                              checkmarkColor: _green,
                                              labelStyle: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    scanDateFilter == filter
                                                        ? _green
                                                        : _grey3,
                                                fontWeight:
                                                    scanDateFilter == filter
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                              ),
                            ),
                            const SizedBox(height: 10),

                            filteredScans.isEmpty
                                ? _wCard(
                                  const Column(
                                    children: [
                                      Icon(
                                        Icons.qr_code_scanner_rounded,
                                        size: 36,
                                        color: _grey4,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'No food scanned yet',
                                        style: TextStyle(
                                          color: _grey3,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                : _wCard(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 300,
                                    ),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: filteredScans.length,
                                      separatorBuilder:
                                          (context, index) =>
                                              Divider(height: 1, color: _grey4),
                                      itemBuilder: (context, index) {
                                        return _scanRow(filteredScans[index]);
                                      },
                                    ),
                                  ),
                                ),
                            const SizedBox(height: 20),

                            // ── Do & Don't ────────────────────────────────
                            _sLabel("Do & Don't Eat"),
                            const SizedBox(height: 4),
                            Text(
                              'Based on your $diabetesType diabetes profile · portions personalized for you',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _grey3,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildDoDontCards(),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: StreamBuilder<QuerySnapshot>(
        stream:
            user == null
                ? const Stream.empty()
                : FirebaseFirestore.instance
                    .collection('users')
                    .doc(user!.uid)
                    .collection('feedback')
                    .where('reply', isNotEqualTo: '')
                    .snapshots(),
        builder: (context, fbSnap) {
          int unreadReplies = 0;
          for (final doc in fbSnap.data?.docs ?? []) {
            final d = doc.data() as Map<String, dynamic>;
            final reply = (d['reply'] ?? '').toString().trim();
            final seen = d['replyRead'] == true;
            if (reply.isNotEmpty && !seen) unreadReplies++;
          }
          return Container(
            decoration: BoxDecoration(
              color: _white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              selectedItemColor: _green,
              unselectedItemColor: _grey3,
              backgroundColor: Colors.transparent,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              selectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              onTap: (index) {
                setState(() => _currentIndex = index);
                if (index == 1) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FoodScannerScreen(),
                    ),
                  ).then((_) => _fetchDashboardData());
                } else if (index == 2) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MealLogScreen()),
                  ).then((_) => _fetchDashboardData());
                } else if (index == 3) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FeedbackScreen()),
                  ).then((_) => setState(() => _currentIndex = 0));
                }
              },
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.qr_code_scanner_rounded),
                  label: 'Scanner',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.edit_note_rounded),
                  label: 'Meal Log',
                ),
                BottomNavigationBarItem(
                  icon: _userBadgeIcon(
                    Icons.feedback_rounded,
                    unreadReplies,
                    _currentIndex == 3,
                  ),
                  label: 'Feedback',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────
  Widget _buildHeader(String name) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2C6E49), Color(0xFF4A9B6F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        ).then((_) {
                          _fetchUserProfile();
                          _fetchDashboardData();
                        }),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.6),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child:
                            profilePictureUrl != null &&
                                    profilePictureUrl!.isNotEmpty
                                ? Image.network(
                                  profilePictureUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) => const _DefaultAvatar(),
                                )
                                : const _DefaultAvatar(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, $name 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.monitor_heart,
                                size: 11,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$diabetesType Diabetes',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: _confirmLogout,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildProfileStatsRow(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Goals info strip ─────────────────────────────────────────────────────
  Widget _buildGoalsInfoStrip() {
    final isPersonalized = userHeight != null && userWeight != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _greenPal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPersonalized
                    ? Icons.auto_awesome_rounded
                    : Icons.info_outline_rounded,
                size: 13,
                color: _green,
              ),
              const SizedBox(width: 5),
              Text(
                '$diabetesType Diabetes',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _goalChip('🔥 ${dailyCalorieGoal.toInt()} kcal'),
              _goalChip('🍞 ${dailyCarbGoal.toInt()}g carbs'),
              _goalChip('💪 ${dailyProteinGoal.toInt()}g protein'),
              _goalChip('🧈 ${dailyFatGoal.toInt()}g fat'),
            ],
          ),
          if (isPersonalized) ...[
            const SizedBox(height: 4),
            Text(
              'Calculated from your height, weight & activity level',
              style: TextStyle(
                fontSize: 9,
                color: _green.withOpacity(0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _goalChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _green.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _green.withOpacity(0.3)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        color: _green,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  // ── Nutrient circle card ──────────────────────────────────────────────────
  Widget _nutrientCard(
    String label,
    double progress,
    Color color,
    String detail,
  ) {
    final dp = progress.clamp(0.0, 1.0);
    final isExceeded = progress >= _dangerThreshold;
    final isCaution = progress >= _cautionThreshold && !isExceeded;
    final c =
        isExceeded
            ? Colors.red
            : isCaution
            ? Colors.orange
            : color;
    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isExceeded
                  ? Colors.red.withOpacity(0.5)
                  : isCaution
                  ? Colors.orange.withOpacity(0.5)
                  : _grey4,
          width: isExceeded || isCaution ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: c.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 62,
                height: 62,
                child: CircularProgressIndicator(
                  value: dp,
                  strokeWidth: 6,
                  backgroundColor: _grey4,
                  valueColor: AlwaysStoppedAnimation(c),
                ),
              ),
              isExceeded
                  ? const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 22,
                  )
                  : isCaution
                  ? const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 20,
                  )
                  : Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: c,
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: const TextStyle(color: _grey3, fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
          if (isExceeded)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'EXCEEDED',
                style: TextStyle(
                  fontSize: 7,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else if (isCaution)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'CAUTION',
                style: TextStyle(
                  fontSize: 7,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Status banner ─────────────────────────────────────────────────────────
  Widget _buildStatusBanner() {
    final exceeded = <String>[];
    final caution = <String>[];
    void chk(double p, String n) {
      if (p >= _dangerThreshold)
        exceeded.add(n);
      else if (p >= _cautionThreshold)
        caution.add(n);
    }

    chk(caloriesProgress, 'Calories');
    chk(carbsProgress, 'Carbs');
    chk(fatProgress, 'Fat');
    chk(proteinProgress, 'Protein');
    if (exceeded.isEmpty && caution.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _greenPal,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _green.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: _green, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '✅ All nutrients within your daily limits today!',
                style: TextStyle(
                  fontSize: 12,
                  color: _green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (exceeded.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _redPal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.dangerous_outlined, color: _red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🚨 Limit exceeded: ${exceeded.join(', ')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (caution.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _amberPal,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _amber.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: _amber,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚠️ Approaching limit: ${caution.join(', ')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _amber,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Quick Log card ────────────────────────────────────────────────────────
  Widget _buildQuickLogCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C6E49), Color(0xFF4A9B6F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _green.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.add_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Log Your Meal',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              GestureDetector(
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MealLogScreen()),
                    ).then((_) => _fetchDashboardData()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'View All',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a meal to log food directly',
            style: TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _mealChip('🌅', 'Breakfast'),
              _mealChip('☀️', 'Lunch'),
              _mealChip('🌙', 'Dinner'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mealChip(String emoji, String label) {
    return GestureDetector(
      onTap: () => _openAddFoodFromDashboard(label),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30, width: 1.5),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _scanRow(Map<String, dynamic> scan) {
    final name = scan['name'] as String? ?? 'Unknown';
    final ts = scan['timestamp'] as DateTime?;
    String dateStr = '', timeStr = '';
    if (ts != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(ts.year, ts.month, ts.day);
      dateStr =
          day == today
              ? 'Today'
              : '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}/${ts.year}';
      final h12 = ts.hour % 12 == 0 ? 12 : ts.hour % 12;
      timeStr =
          '$h12:${ts.minute.toString().padLeft(2, '0')} ${ts.hour >= 12 ? 'PM' : 'AM'}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _tealPal,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: _teal,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _grey1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (dateStr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$dateStr  •  $timeStr',
                    style: const TextStyle(fontSize: 10, color: _grey3),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _tealPal,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Scanned',
              style: TextStyle(
                fontSize: 10,
                color: _teal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStatsRow() {
    if (userHeight == null && userWeight == null && activityLevel == null)
      return const SizedBox.shrink();
    final actCfg =
        activityLevel != null ? _activityConfig[activityLevel!] : null;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (userHeight != null)
          _headerPill(Icons.height, '${userHeight!.toStringAsFixed(0)} cm'),
        if (userWeight != null)
          _headerPill(
            Icons.monitor_weight,
            '${userWeight!.toStringAsFixed(0)} kg',
          ),
        if (activityLevel != null && actCfg != null)
          GestureDetector(
            onTap: _showActivityDetail,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    actCfg['icon'] as IconData,
                    size: 10,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    activityLevel!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.info_outline,
                    size: 9,
                    color: Colors.white60,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _headerPill(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: Colors.white),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  // ── Do / Don't cards ──────────────────────────────────────────────────────
  Widget _buildDoDontCards() {
    if (diabetesType == 'Not set' ||
        diabetesType == 'Error loading type' ||
        diabetesType == 'Loading...') {
      return _wCard(
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              diabetesType == 'Error loading type'
                  ? 'Failed to load recommendations'
                  : 'Loading food recommendations...',
              style: const TextStyle(color: _grey3, fontSize: 13),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 130,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('food_rules').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(
              child: CircularProgressIndicator(color: _green),
            );
          final docs = snapshot.data!.docs;
          final filtered =
              docs.where((doc) {
                final d = doc.data() as Map<String, dynamic>?;
                return d?['diabetesType']?.toString() == diabetesType;
              }).toList();
          filtered.sort((a, b) {
            final aT = a['createdAt'] as Timestamp?;
            final bT = b['createdAt'] as Timestamp?;
            if (aT == null && bT == null) return 0;
            if (aT == null) return 1;
            if (bT == null) return -1;
            return bT.compareTo(aT);
          });
          final doFoods = filtered.where((d) => d['category'] == 'Do').toList();
          final dontFoods =
              filtered.where((d) => d['category'] == "Don't").toList();
          return ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap:
                    () => _openDoDontScreen(
                      '✅ DO — Recommended Foods',
                      _buildFoodCardsFromDocs(doFoods),
                      doFoods.length,
                    ),
                child: _doDontChip(
                  '✅ DO',
                  '${doFoods.length} foods',
                  _green,
                  _greenPal,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap:
                    () => _openDoDontScreen(
                      "🚫 DON'T — Foods to Avoid",
                      _buildFoodCardsFromDocs(dontFoods),
                      dontFoods.length,
                    ),
                child: _doDontChip(
                  "🚫 DON'T",
                  '${dontFoods.length} foods',
                  _red,
                  _redPal,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _doDontChip(String title, String sub, Color color, Color pal) =>
      Container(
        width: 155,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pal,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.7)),
            ),
          ],
        ),
      );

  // ── Shared helpers ────────────────────────────────────────────────────────
  Widget _sLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: _grey1,
    ),
  );

  Widget _wCard(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );

  Widget _weeklyNutrientRow(
    String label,
    double weeklyTotal,
    double weeklyGoal,
    String unit,
    Color color,
  ) {
    // Calculate status
    final percentage = weeklyGoal > 0 ? (weeklyTotal / weeklyGoal) : 0.0;
    String status;
    Color statusColor;
    IconData statusIcon;

    if (percentage >= 0.9 && percentage <= 1.1) {
      status = 'Stable';
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (percentage < 0.9) {
      status = 'Lack';
      statusColor = Colors.orange;
      statusIcon = Icons.arrow_downward;
    } else {
      status = 'Over';
      statusColor = Colors.red;
      statusIcon = Icons.arrow_upward;
    }

    return Row(
      children: [
        Container(
          width: 4,
          height: 50,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _grey1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${weeklyTotal.toStringAsFixed(0)} / ${weeklyGoal.toStringAsFixed(0)} $unit',
                style: TextStyle(fontSize: 11, color: _grey3),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 4),
              Text(
                status,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendDot2(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 9, color: _grey3)),
    ],
  );

  void _openAddFoodFromDashboard(String mealType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddFoodSheet(preselectedMeal: mealType),
    ).then((_) => _fetchDashboardData());
  }

  void _openDoDontScreen(String title, List<Widget> cards, int count) {
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No foods in this category yet!'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoDontFoodsScreen(title: title, foodCards: cards),
      ),
    );
  }

  // ── UPGRADED: builds food cards with personalized nutrition ──────────────
  List<Widget> _buildFoodCardsFromDocs(List<QueryDocumentSnapshot> foodDocs) {
    return foodDocs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = data['name'] ?? 'Unknown Food';
      final imageUrl = data['imageUrl'] ?? data['imagePath'] ?? '';
      // Run BMR+TDEE calculation for this food
      final pn = NutritionCalculator.calculate(
        heightCm: userHeight,
        weightKg: userWeight,
        activityLevel: activityLevel ?? 'Light',
        diabetesType: diabetesType,
        calories100g: _d(data['calories']),
        carbs100g: _d(data['carbs']),
        protein100g: _d(data['protein']),
        fat100g: _d(data['fat']),
      );
      return _buildFoodCard(imageUrl, name, data, pn);
    }).toList();
  }

  Widget _buildFoodCard(
    String imageUrl,
    String foodName,
    Map<String, dynamic> data,
    PersonalizedNutrition pn,
  ) {
    final isPers = pn.isPersonalized;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child:
                  imageUrl.isNotEmpty
                      ? Image.network(
                        imageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        loadingBuilder:
                            (_, child, p) =>
                                p == null
                                    ? child
                                    : Container(
                                      width: 64,
                                      height: 64,
                                      color: _grey5,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _green,
                                        ),
                                      ),
                                    ),
                        errorBuilder:
                            (_, __, ___) => Container(
                              width: 64,
                              height: 64,
                              color: _grey5,
                              child: const Icon(
                                Icons.fastfood_rounded,
                                color: _grey3,
                                size: 28,
                              ),
                            ),
                      )
                      : Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: _grey5,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.fastfood_rounded,
                          color: _grey3,
                          size: 28,
                        ),
                      ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    foodName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _grey1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  // Personalized portion pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isPers ? _tealPal : _grey5,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isPers ? _teal.withOpacity(0.3) : _grey4,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPers
                              ? Icons.auto_awesome_rounded
                              : Icons.scale_rounded,
                          size: 10,
                          color: isPers ? _teal : _grey3,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isPers ? pn.portionLabel : '—',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isPers ? _teal : _grey2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Personalized nutrient chips
                  Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    children: [
                      _nutBadge(
                        'Cal',
                        '${pn.calories.toStringAsFixed(0)} kcal',
                      ),
                      _nutBadge('Carbs', '${pn.carbs.toStringAsFixed(1)}g'),
                      _nutBadge('Protein', '${pn.protein.toStringAsFixed(1)}g'),
                      _nutBadge('Fat', '${pn.fat.toStringAsFixed(1)}g'),
                    ],
                  ),
                  if (isPers) ...[
                    const SizedBox(height: 4),
                    Text(
                      '✨ Personalized for your profile',
                      style: TextStyle(
                        fontSize: 9,
                        color: _teal.withOpacity(0.8),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nutBadge(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: _grey5,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: const TextStyle(fontSize: 10, color: _grey3)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 10,
            color: _grey1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _userBadgeIcon(IconData icon, int count, bool isSelected) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: _red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Default avatar ────────────────────────────────────────────────────────────
class _DefaultAvatar extends StatelessWidget {
  const _DefaultAvatar();
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF2C6E49),
    child: const Icon(Icons.person, color: Colors.white, size: 28),
  );
}

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg = Color(0xFFF4F7F5);
const _white = Color(0xFFFFFFFF);
const _green = Color(0xFF2C6E49);
const _greenPal = Color(0xFFE8F5EE);
const _red = Color(0xFFD64045);
const _redPal = Color(0xFFFDECEC);
const _amber = Color(0xFFF09D18);
const _amberPal = Color(0xFFFFF4E0);
const _blue = Color(0xFF2979C6);
const _teal = Color(0xFF0D8A7C);
const _tealPal = Color(0xFFE3F5F3);
const _purp = Color(0xFF7B5EA7);
const _grey1 = Color(0xFF1A2E22);
const _grey2 = Color(0xFF4D6357);
const _grey3 = Color(0xFF8FA898);
const _grey4 = Color(0xFFD5E2DA);
const _grey5 = Color(0xFFF0F5F2);
