import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetechapp/Screens/edit_profile.dart';
import 'package:diabetechapp/Screens/foodscanner.dart';
import 'package:diabetechapp/Screens/log_in.dart';
import 'package:diabetechapp/Screens/meal_log_screen.dart';
import 'package:diabetechapp/health/goal_progress.dart';
import 'package:diabetechapp/health/do_dont_foods_screen.dart';

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

const Map<String, _DiabetesNutrientGoals> _diabetesGoals = {
  'Mild':   _DiabetesNutrientGoals(calories: 1800, carbs: 150, protein: 65, fat: 55),
  'Severe': _DiabetesNutrientGoals(calories: 1400, carbs: 100, protein: 60, fat: 45),
};

const _defaultGoals = _DiabetesNutrientGoals(
  calories: 1800, carbs: 150, protein: 60, fat: 50,
);

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  User? user;
  int _currentIndex = 0;

  double caloriesProgress   = 0.0;
  double carbsProgress      = 0.0;
  double proteinProgress    = 0.0;
  double fatProgress        = 0.0;
  double weeklyGoalProgress = 0.0;

  double todayCalories = 0;
  double todayCarbs    = 0;
  double todayProtein  = 0;
  double todayFat      = 0;

  String  diabetesType      = 'Loading...';
  String? profilePictureUrl;
  List<Map<String, dynamic>> recentScans = [];

  double? userHeight;
  double? userWeight;
  String? activityLevel;

  double dailyCalorieGoal = 1800;
  double dailyCarbGoal    = 150;
  double dailyProteinGoal = 60;
  double dailyFatGoal     = 50;
  double weeklyScanGoal   = 10;

  static const double _cautionThreshold = 0.75;
  static const double _dangerThreshold  = 1.0;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Map<String, Map<String, dynamic>> _activityConfig = {
    'Sedentary':   {'icon': Icons.weekend,        'color': Color(0xFF9E9E9E)},
    'Light':       {'icon': Icons.directions_walk, 'color': Color(0xFF42A546)},
    'Very Active': {'icon': Icons.directions_run,  'color': Color(0xFFE53935)},
  };

  static const Map<String, Map<String, String>> _activityDetails = {
    'Sedentary': {
      'desc':     'Little or no physical activity. Mostly sitting or lying down throughout the day.',
      'examples': '🛋️ Resting  •  📺 Watching TV  •  💻 Desk work with no movement',
    },
    'Light': {
      'desc':     'Minimal movement with light physical tasks during the day.',
      'examples': '🏢 Office work  •  🚗 Driving  •  🧹 Light house chores',
    },
    'Very Active': {
      'desc':     'Extensive and rapid movements with high physical demands all day.',
      'examples': '🏃 Running  •  🏗️ Heavy labor  •  📦 Carrying heavy objects extensively',
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
      final doc  = await _firestore.collection('users').doc(user!.uid).get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      setState(() {
        diabetesType  = (data['diabetesType'] ?? 'Not set').toString();
        userHeight    = double.tryParse(data['height']?.toString() ?? '');
        userWeight    = double.tryParse(data['weight']?.toString() ?? '');
        activityLevel = data['activityLevel']?.toString();
        profilePictureUrl =
            data['profilePictureUrl'] ??
            data['photoUrl']          ??
            data['profilePicture']    ??
            data['profileImage']      ??
            data['imageUrl'];
      });
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      setState(() => diabetesType = 'Error loading type');
    }
  }

  _DiabetesNutrientGoals _resolveGoals(String type, Map<String, dynamic> userData) {
    if (userData.containsKey('dailyCalorieGoal')) {
      return _DiabetesNutrientGoals(
        calories: (userData['dailyCalorieGoal'] ?? _defaultGoals.calories).toDouble(),
        carbs:    (userData['dailyCarbGoal']    ?? _defaultGoals.carbs).toDouble(),
        protein:  (userData['dailyProteinGoal'] ?? _defaultGoals.protein).toDouble(),
        fat:      (userData['dailyFatGoal']     ?? _defaultGoals.fat).toDouble(),
      );
    }
    return _diabetesGoals[type] ?? _defaultGoals;
  }

  Future<void> _fetchDashboardData() async {
    if (user == null) return;

    final now              = DateTime.now();
    final todayMidnight    = DateTime(now.year, now.month, now.day);
    final tomorrowMidnight = todayMidnight.add(const Duration(days: 1));

    // ── STEP 1: Fetch foodLogs (nutrition tracking) ──────────────────
    double cal = 0, carbs = 0, protein = 0, fat = 0;
    int weekScans = 0;
    _DiabetesNutrientGoals goals = _defaultGoals;
    double scanGoal = 10;

    try {
      final userDoc  = await _firestore.collection('users').doc(user!.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      final type     = (userData['diabetesType'] ?? diabetesType).toString();
      goals    = _resolveGoals(type, userData);
      scanGoal = (userData['weeklyScanGoal'] ?? 10).toDouble();

      final foodLogsSnap = await _firestore
          .collection('users')
          .doc(user!.uid)
          .collection('foodLogs')
          .get();

      for (var doc in foodLogsSnap.docs) {
        final data      = doc.data() as Map<String, dynamic>;
        final ts        = (data['timestamp'] as Timestamp?)?.toDate();
        final entryTime = ts ?? now; // treat null as now — never excluded

        // Only count today's food (resets at midnight)
        final isToday = !entryTime.isBefore(todayMidnight) &&
                         entryTime.isBefore(tomorrowMidnight);

        if (isToday) {
          final nutrition = data['nutrition'] as Map<String, dynamic>? ?? {};
          cal     += _d(nutrition['calories']);
          carbs   += _d(nutrition['carbs']);
          protein += _d(nutrition['protein']);
          fat     += _d(nutrition['fat']);
        }

        // Weekly scan count
        if (ts != null &&
            (data['imagePath'] != null || data['scannedFood'] == true)) {
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          if (ts.isAfter(weekStart)) weekScans++;
        }
      }

      // Update nutrition charts
      if (mounted) {
        setState(() {
          dailyCalorieGoal   = goals.calories;
          dailyCarbGoal      = goals.carbs;
          dailyProteinGoal   = goals.protein;
          dailyFatGoal       = goals.fat;
          weeklyScanGoal     = scanGoal;
          todayCalories      = cal;
          todayCarbs         = carbs;
          todayProtein       = protein;
          todayFat           = fat;
          caloriesProgress   = goals.calories > 0 ? (cal     / goals.calories).clamp(0.0, 1.5) : 0.0;
          carbsProgress      = goals.carbs    > 0 ? (carbs   / goals.carbs).clamp(0.0, 1.5)    : 0.0;
          proteinProgress    = goals.protein  > 0 ? (protein / goals.protein).clamp(0.0, 1.5)  : 0.0;
          fatProgress        = goals.fat      > 0 ? (fat     / goals.fat).clamp(0.0, 1.5)      : 0.0;
          weeklyGoalProgress = scanGoal > 0 ? (weekScans / scanGoal).clamp(0.0, 1.0) : 0.0;
        });
        _checkNutrientWarnings(cal, carbs, fat, goals);
      }
    } catch (e) {
      debugPrint('❌ Error fetching foodLogs: $e');
    }

    // ── STEP 2: Fetch recent scans SEPARATELY so it never breaks charts ──
    try {
      final scannedFoodsSnap = await _firestore
          .collection('users')
          .doc(user!.uid)
          .collection('scanned_foods')
          .get(); // No orderBy — avoids index requirement

      final fetchedScans = scannedFoodsSnap.docs.map((doc) {
        final d  = doc.data() as Map<String, dynamic>;
        final ts = (d['timestamp'] as Timestamp?)?.toDate();
        return {'name': d['food'] ?? d['foodName'] ?? d['name'] ?? 'Unknown', 'timestamp': ts};
      }).toList();

      // Sort in code instead of Firestore (no index needed)
      fetchedScans.sort((a, b) {
        final aTs = a['timestamp'] as DateTime?;
        final bTs = b['timestamp'] as DateTime?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });

      final limited = fetchedScans.take(10).toList();

      if (mounted) {
        setState(() => recentScans = limited);
      }
    } catch (e) {
      debugPrint('❌ Error fetching scanned_foods: $e');
    }
  }

  void _checkNutrientWarnings(double cal, double carbs, double fat,
      _DiabetesNutrientGoals goals) {
    final exceeded = <String>[];
    if (cal   > goals.calories) exceeded.add('🔥 Calories (${cal.toStringAsFixed(0)} / ${goals.calories.toInt()} kcal)');
    if (carbs > goals.carbs)    exceeded.add('🍞 Carbs (${carbs.toStringAsFixed(1)} / ${goals.carbs.toInt()} g)');
    if (fat   > goals.fat)      exceeded.add('🧈 Fat (${fat.toStringAsFixed(1)} / ${goals.fat.toInt()} g)');
    if (exceeded.isEmpty || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Nutrient Alert!',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You exceeded your $diabetesType diabetes daily limits:',
                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 10),
              ...exceeded.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.circle, color: Colors.red, size: 8),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e, style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red))),
                ]),
              )),
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
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C6E49),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Logout')),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  Color _nutrientColor(double progress, Color defaultColor) {
    if (progress >= _dangerThreshold)  return Colors.red;
    if (progress >= _cautionThreshold) return Colors.orange;
    return defaultColor;
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'Mild':   return Colors.green;
      case 'Severe': return Colors.red;
      default:       return const Color(0xFF2C6E49);
    }
  }

  void _showActivityDetail() {
    if (activityLevel == null) return;
    final cfg    = _activityConfig[activityLevel!];
    final detail = _activityDetails[activityLevel!];
    if (cfg == null || detail == null) return;
    final color = cfg['color'] as Color;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 20),
            Container(width: 64, height: 64,
                decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(cfg['icon'] as IconData, color: color, size: 32)),
            const SizedBox(height: 14),
            Text(activityLevel!, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 8),
            Text(detail['desc']!, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Examples:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 6),
                Text(detail['examples']!, style: TextStyle(fontSize: 13, color: color.withOpacity(0.9), height: 1.6)),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it', style: TextStyle(color: Colors.white, fontSize: 15)),
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
      body: Column(children: [
        // ── Gradient header ───────────────────────────────────────────
        _buildHeader(name),
        // ── Body ─────────────────────────────────────────────────────
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _fetchUserProfile();
              await _fetchDashboardData();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              child: Column(children: [
                // Curved body
                Transform.translate(
                  offset: const Offset(0, -20),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24)),
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
                      Row(children: [
                        Expanded(child: Text(
                            'Swipe to see all  •  Log meals to update',
                            style: TextStyle(
                                fontSize: 10,
                                color: _grey3))),
                        _legendDot2(Colors.green,  'OK'),
                        const SizedBox(width: 6),
                        _legendDot2(Colors.orange, 'Caution'),
                        const SizedBox(width: 6),
                        _legendDot2(Colors.red,    'Exceeded'),
                      ]),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 150,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          children: [
                            _nutrientCard('Calories', caloriesProgress,
                                Colors.orange,
                                '${todayCalories.toStringAsFixed(0)}\n${dailyCalorieGoal.toInt()} kcal'),
                            _nutrientCard('Carbs', carbsProgress,
                                _blue,
                                '${todayCarbs.toStringAsFixed(1)}\n${dailyCarbGoal.toInt()}g'),
                            _nutrientCard('Protein', proteinProgress,
                                _purp,
                                '${todayProtein.toStringAsFixed(1)}\n${dailyProteinGoal.toInt()}g'),
                            _nutrientCard('Fat', fatProgress,
                                _amber,
                                '${todayFat.toStringAsFixed(1)}\n${dailyFatGoal.toInt()}g'),
                          ],
                        ),
                      ),
                      _buildStatusBanner(),
                      const SizedBox(height: 20),

                      // ── Quick Log ─────────────────────────────────
                      _buildQuickLogCard(),
                      const SizedBox(height: 20),

                      // ── Goal Progress ─────────────────────────────
                      _sLabel('Goal Progress'),
                      const SizedBox(height: 10),
                      _wCard(Column(children: [
                        Row(children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Weekly Scan Goal',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _grey1)),
                              const SizedBox(height: 4),
                              Text(
                                '${(weeklyGoalProgress * 100).toInt()}% completed',
                                style: const TextStyle(
                                    fontSize: 11, color: _grey3)),
                            ],
                          )),
                          Text(
                            '${(weeklyGoalProgress * 100).toInt()}%',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: _green)),
                        ]),
                        const SizedBox(height: 10),
                        Stack(children: [
                          Container(height: 8,
                              decoration: BoxDecoration(
                                  color: _grey4,
                                  borderRadius: BorderRadius.circular(4))),
                          FractionallySizedBox(
                            widthFactor: weeklyGoalProgress.clamp(0.0, 1.0),
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                  color: _green,
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        GoalProgressScreen(
                          weeklyGoalProgress: weeklyGoalProgress,
                          goalText:
                              'Weekly goal: ${(weeklyGoalProgress * 100).toInt()}% completed',
                        ),
                      ])),
                      const SizedBox(height: 20),

                      // ── Recent Food Scans ─────────────────────────
                      _sLabel('Recent Food Scans'),
                      const SizedBox(height: 10),
                      recentScans.isEmpty
                          ? _wCard(Column(children: [
                              const Icon(Icons.qr_code_scanner_rounded,
                                  size: 36, color: _grey4),
                              const SizedBox(height: 8),
                              const Text('No food scanned yet',
                                  style: TextStyle(
                                      color: _grey3, fontSize: 13)),
                            ]))
                          : _wCard(Column(
                              children: recentScans
                                  .asMap()
                                  .entries
                                  .map((e) => Column(children: [
                                        _scanRow(e.value),
                                        if (e.key <
                                            recentScans.length - 1)
                                          Divider(
                                              height: 1,
                                              color: _grey4),
                                      ]))
                                  .toList(),
                            )),
                      const SizedBox(height: 20),

                      // ── Do & Don't ────────────────────────────────
                      _sLabel("Do & Don't Eat"),
                      const SizedBox(height: 4),
                      Text('Based on your $diabetesType diabetes profile',
                          style: const TextStyle(
                              fontSize: 11,
                              color: _grey3,
                              fontStyle: FontStyle.italic)),
                      const SizedBox(height: 10),
                      _buildDoDontCards(),
                      const SizedBox(height: 8),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: _white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, -2)),
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
              fontSize: 11, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          onTap: (index) {
            setState(() => _currentIndex = index);
            if (index == 1) {
              Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const FoodScannerScreen()))
                  .then((_) => _fetchDashboardData());
            } else if (index == 2) {
              Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const MealLogScreen()))
                  .then((_) => _fetchDashboardData());
            }
          },
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.qr_code_scanner_rounded),
                label: 'Scanner'),
            BottomNavigationBarItem(
                icon: Icon(Icons.edit_note_rounded),
                label: 'Meal Log'),
          ],
        ),
      ),
    );
  }

  // ── Gradient header ─────────────────────────────────────────────────────
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
            // Top row: avatar + name + logout
            Row(children: [
              // Avatar
              GestureDetector(
                onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const EditProfileScreen()))
                    .then((_) {
                  _fetchUserProfile();
                  _fetchDashboardData();
                }),
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.6),
                        width: 2),
                  ),
                  child: ClipOval(
                    child: profilePictureUrl != null &&
                            profilePictureUrl!.isNotEmpty
                        ? Image.network(profilePictureUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _DefaultAvatar())
                        : const _DefaultAvatar(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                  Text('Hello, $name 👋',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                Colors.white.withOpacity(0.3)),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        const Icon(Icons.monitor_heart,
                            size: 11, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text('$diabetesType Diabetes',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                ]),
              ),
              // Logout button
              InkWell(
                onTap: _confirmLogout,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.logout_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            // Stats pills row
            _buildProfileStatsRow(),
          ]),
        ),
      ),
    );
  }

  // ── Goals info strip ────────────────────────────────────────────────────
  Widget _buildGoalsInfoStrip() {
    final goals = _diabetesGoals[diabetesType];
    if (goals == null) return const SizedBox.shrink();
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _greenPal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withOpacity(0.25)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(children: [
          const Icon(Icons.info_outline_rounded,
              size: 13, color: _green),
          const SizedBox(width: 5),
          Text('$diabetesType Diabetes — Daily Limits',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _green)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _goalChip('🔥 ${goals.calories.toInt()} kcal'),
          _goalChip('🍞 ${goals.carbs.toInt()}g carbs'),
          _goalChip('💪 ${goals.protein.toInt()}g protein'),
          _goalChip('🧈 ${goals.fat.toInt()}g fat'),
        ]),
      ]),
    );
  }

  Widget _goalChip(String label) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: _green.withOpacity(0.3)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: _green,
                fontWeight: FontWeight.w600)),
      );

  // ── Nutrient circle card ────────────────────────────────────────────────
  Widget _nutrientCard(String label, double progress,
      Color color, String detail) {
    final dp         = progress.clamp(0.0, 1.0);
    final isExceeded = progress >= _dangerThreshold;
    final isCaution  = progress >= _cautionThreshold && !isExceeded;
    final c = isExceeded
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
          color: isExceeded
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
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
        Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 62, height: 62,
            child: CircularProgressIndicator(
              value: dp,
              strokeWidth: 6,
              backgroundColor: _grey4,
              valueColor: AlwaysStoppedAnimation(c),
            ),
          ),
          isExceeded
              ? const Icon(Icons.warning_amber_rounded,
                  color: Colors.red, size: 22)
              : isCaution
                  ? const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 20)
                  : Text('${(progress * 100).toInt()}%',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: c)),
        ]),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: c,
                fontWeight: FontWeight.w700,
                fontSize: 11)),
        const SizedBox(height: 2),
        Text(detail,
            style: const TextStyle(
                color: _grey3, fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 2),
        if (isExceeded)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('EXCEEDED',
                style: TextStyle(
                    fontSize: 7,
                    color: Colors.red,
                    fontWeight: FontWeight.bold)),
          )
        else if (isCaution)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('CAUTION',
                style: TextStyle(
                    fontSize: 7,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold)),
          ),
      ]),
    );
  }

  // ── Nutrient status banner ──────────────────────────────────────────────
  Widget _buildStatusBanner() {
    final exceeded = <String>[];
    final caution  = <String>[];
    void chk(double p, String n) {
      if (p >= _dangerThreshold) exceeded.add(n);
      else if (p >= _cautionThreshold) caution.add(n);
    }
    chk(caloriesProgress, 'Calories');
    chk(carbsProgress,    'Carbs');
    chk(fatProgress,      'Fat');
    chk(proteinProgress,  'Protein');

    if (exceeded.isEmpty && caution.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _greenPal,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: _green.withOpacity(0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded,
              color: _green, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '✅ All nutrients within your daily limits today!',
              style: TextStyle(
                  fontSize: 12,
                  color: _green,
                  fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }
    return Column(children: [
      if (exceeded.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _redPal,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _red.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.dangerous_outlined,
                color: _red, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '🚨 Limit exceeded: ${exceeded.join(', ')}',
                style: const TextStyle(
                    fontSize: 12,
                    color: _red,
                    fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ],
      if (caution.isNotEmpty) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _amberPal,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _amber.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: _amber, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚠️ Approaching limit: ${caution.join(', ')}',
                style: const TextStyle(
                    fontSize: 12,
                    color: _amber,
                    fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ],
    ]);
  }

  // ── Quick Log card ──────────────────────────────────────────────────────
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
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(children: [
          const Icon(Icons.add_circle_rounded,
              color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Log Your Meal',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const MealLogScreen()))
                .then((_) => _fetchDashboardData()),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('View All',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        const Text('Tap a meal to log food directly',
            style: TextStyle(
                color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceAround,
          children: [
            _mealChip('🌅', 'Breakfast'),
            _mealChip('☀️', 'Lunch'),
            _mealChip('🌙', 'Dinner'),
          ],
        ),
      ]),
    );
  }

  Widget _mealChip(String emoji, String label) {
    return GestureDetector(
      onTap: () => _openAddFoodFromDashboard(label),
      child: Column(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white30, width: 1.5),
          ),
          child: Center(
              child: Text(emoji,
                  style: const TextStyle(fontSize: 22))),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 10)),
      ]),
    );
  }

  // ── Scan list row ────────────────────────────────────────────────────────
  Widget _scanRow(Map<String, dynamic> scan) {
    final name = scan['name'] as String? ?? 'Unknown';
    final ts   = scan['timestamp'] as DateTime?;
    String dateStr = '', timeStr = '';
    if (ts != null) {
      final now   = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final day   = DateTime(ts.year, ts.month, ts.day);
      dateStr = day == today
          ? 'Today'
          : '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}/${ts.year}';
      final h12 = ts.hour % 12 == 0 ? 12 : ts.hour % 12;
      timeStr = '$h12:${ts.minute.toString().padLeft(2, '0')} ${ts.hour >= 12 ? 'PM' : 'AM'}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 4, vertical: 10),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: _tealPal,
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.qr_code_scanner_rounded,
              color: _teal, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(name,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: _grey1),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (dateStr.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('$dateStr  •  $timeStr',
                style: const TextStyle(
                    fontSize: 10, color: _grey3)),
          ],
        ])),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _tealPal,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('Scanned',
              style: TextStyle(
                  fontSize: 10,
                  color: _teal,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  // ── Profile stats row ────────────────────────────────────────────────────
  Widget _buildProfileStatsRow() {
    if (userHeight == null &&
        userWeight == null &&
        activityLevel == null) return const SizedBox.shrink();
    final actCfg = activityLevel != null
        ? _activityConfig[activityLevel!]
        : null;
    final actColor = actCfg != null
        ? actCfg['color'] as Color
        : Colors.grey;

    return Wrap(spacing: 6, runSpacing: 4, children: [
      if (userHeight != null)
        _headerPill(Icons.height,
            '${userHeight!.toStringAsFixed(0)} cm'),
      if (userWeight != null)
        _headerPill(Icons.monitor_weight,
            '${userWeight!.toStringAsFixed(0)} kg'),
      if (activityLevel != null && actCfg != null)
        GestureDetector(
          onTap: _showActivityDetail,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: Colors.white.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min,
                children: [
              Icon(actCfg['icon'] as IconData,
                  size: 10, color: Colors.white),
              const SizedBox(width: 3),
              Text(activityLevel!,
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 2),
              const Icon(Icons.info_outline,
                  size: 9, color: Colors.white60),
            ]),
          ),
        ),
    ]);
  }

  Widget _headerPill(IconData icon, String label) =>
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.white.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min,
            children: [
          Icon(icon, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ]),
      );

  // ── Do / Don't cards ────────────────────────────────────────────────────
  Widget _buildDoDontCards() {
    if (diabetesType == 'Not set' ||
        diabetesType == 'Error loading type' ||
        diabetesType == 'Loading...') {
      return _wCard(Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            diabetesType == 'Error loading type'
                ? 'Failed to load recommendations'
                : 'Loading food recommendations...',
            style: const TextStyle(
                color: _grey3, fontSize: 13)),
        ),
      ));
    }
    return SizedBox(
      height: 130,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('food_rules')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(
                child: CircularProgressIndicator(
                    color: _green));
          final docs = snapshot.data!.docs;
          final filtered = docs.where((doc) {
            final d = doc.data() as Map<String, dynamic>?;
            return d?['diabetesType']?.toString() ==
                diabetesType;
          }).toList();

          filtered.sort((a, b) {
            final aT = a['createdAt'] as Timestamp?;
            final bT = b['createdAt'] as Timestamp?;
            if (aT == null && bT == null) return 0;
            if (aT == null) return 1;
            if (bT == null) return -1;
            return bT.compareTo(aT);
          });

          final doFoods = filtered
              .where((d) => d['category'] == 'Do')
              .toList();
          final dontFoods = filtered
              .where((d) => d['category'] == "Don't")
              .toList();

          return ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap: () => _openDoDontScreen(
                    '✅ DO — Recommended Foods',
                    _buildFoodCardsFromDocs(doFoods),
                    doFoods.length),
                child: _doDontChip(
                    '✅ DO',
                    '${doFoods.length} foods',
                    _green,
                    _greenPal),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _openDoDontScreen(
                    "🚫 DON'T — Foods to Avoid",
                    _buildFoodCardsFromDocs(dontFoods),
                    dontFoods.length),
                child: _doDontChip(
                    "🚫 DON'T",
                    '${dontFoods.length} foods',
                    _red,
                    _redPal),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _doDontChip(
      String title, String sub, Color color, Color pal) =>
      Container(
        width: 155,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pal,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Text(title,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 4),
          Text(sub,
              style: TextStyle(
                  fontSize: 11, color: color.withOpacity(0.7))),
        ]),
      );

  // ── Shared helpers ───────────────────────────────────────────────────────
  Widget _sLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: _grey1));

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
                offset: const Offset(0, 2)),
          ],
        ),
        child: child,
      );

  Widget _legendDot2(Color color, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle)),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 9, color: _grey3)),
      ]);

  // ── Keep legacy helpers that other methods call ──────────────────────────
  Widget _buildQuickAddMealCard(
          bool isSmallScreen, bool isMediumScreen) =>
      _buildQuickLogCard();

  Widget _mealShortcut(String emoji, String label) =>
      _mealChip(emoji, label);

  Widget _buildCircleStat(String label, double progress,
      Color color, String detail) =>
      _nutrientCard(label, progress, color, detail);

  Widget _buildNutrientStatusBanner() => _buildStatusBanner();

  Widget _sectionTitle(String t) => _sLabel(t);

  Widget _buildScanListItem(Map<String, dynamic> scan) =>
      _scanRow(scan);

  Widget _statPill(
          {required IconData icon,
          required String label,
          required Color color}) =>
      _headerPill(icon, label);

  Widget _legendDot(Color color, String label) =>
      _legendDot2(color, label);

  Widget _buildSquareButton(
          {required IconData icon,
          required VoidCallback onPressed}) =>
      InkWell(
        onTap: onPressed,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );

  // ── Missing methods ───────────────────────────────────────────────────

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No foods in this category yet!'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => DoDontFoodsScreen(title: title, foodCards: cards)));
  }

  List<Widget> _buildFoodCardsFromDocs(List<QueryDocumentSnapshot> foodDocs) {
    return foodDocs.map((doc) {
      final data     = doc.data() as Map<String, dynamic>;
      final name     = data['name']     ?? 'Unknown Food';
      final imageUrl = data['imageUrl'] ?? data['imagePath'] ?? '';
      return _buildFoodCard(imageUrl, name, data);
    }).toList();
  }

  Widget _buildFoodCard(String imageUrl, String foodName,
      Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl.isNotEmpty
                ? Image.network(imageUrl,
                    width: 60, height: 60, fit: BoxFit.cover,
                    loadingBuilder: (_, child, p) => p == null ? child
                        : Container(width: 60, height: 60, color: _grey4,
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    errorBuilder: (_, __, ___) => Container(
                        width: 60, height: 60, color: _grey4,
                        child: const Icon(Icons.fastfood_rounded, color: _grey3, size: 28)))
                : Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(color: _grey4, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.fastfood_rounded, color: _grey3, size: 28)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(foodName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _grey1),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(data['portionSize'] ?? 'N/A',
                  style: const TextStyle(fontSize: 12, color: _grey3)),
              const SizedBox(height: 6),
              Wrap(spacing: 5, runSpacing: 3, children: [
                _nutBadge('Carbs',   '${data['carbs']    ?? 0}g'),
                _nutBadge('Protein', '${data['protein']  ?? 0}g'),
                _nutBadge('Fat',     '${data['fat']      ?? 0}g'),
                _nutBadge('Cal',     '${data['calories'] ?? 0} kcal'),
              ]),
            ],
          )),
        ]),
      ),
    );
  }

  Widget _nutBadge(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: _grey5, borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label ', style: const TextStyle(fontSize: 10, color: _grey3)),
          Text(value,    style: const TextStyle(fontSize: 10, color: _grey1, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ── Default avatar ──────────────────────────────────────────────────────────
class _DefaultAvatar extends StatelessWidget {
  const _DefaultAvatar();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF2C6E49),
        child: const Icon(Icons.person,
            color: Colors.white, size: 28),
      );
}

// ── Palette — same as admin ──────────────────────────────────────────────────
const _bg      = Color(0xFFF4F7F5);
const _white   = Color(0xFFFFFFFF);
const _green   = Color(0xFF2C6E49);
const _greenPal= Color(0xFFE8F5EE);
const _red     = Color(0xFFD64045);
const _redPal  = Color(0xFFFDECEC);
const _amber   = Color(0xFFF09D18);
const _amberPal= Color(0xFFFFF4E0);
const _blue    = Color(0xFF2979C6);
const _teal    = Color(0xFF0D8A7C);
const _tealPal = Color(0xFFE3F5F3);
const _purp    = Color(0xFF7B5EA7);
const _grey1   = Color(0xFF1A2E22);
const _grey2   = Color(0xFF4D6357);
const _grey3   = Color(0xFF8FA898);
const _grey4   = Color(0xFFD5E2DA);
const _grey5   = Color(0xFFF0F5F2);