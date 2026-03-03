import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetechapp/Screens/edit_profile.dart';
import 'package:diabetechapp/Screens/foodscanner.dart';
import 'package:diabetechapp/Screens/log_in.dart';
import 'package:diabetechapp/Screens/meal_log_screen.dart';
import 'package:diabetechapp/health/goal_progress.dart';
import 'package:diabetechapp/health/do_dont_foods_screen.dart';

// ── Nutrient goals per diabetes type ──────────────────────────────────────
// Stricter limits as severity increases
class _DiabetesNutrientGoals {
  final double calories;
  final double carbs;
  final double sugar;
  final double protein;
  final double fat;

  const _DiabetesNutrientGoals({
    required this.calories,
    required this.carbs,
    required this.sugar,
    required this.protein,
    required this.fat,
  });
}

const Map<String, _DiabetesNutrientGoals> _diabetesGoals = {
  'Mild': _DiabetesNutrientGoals(
    calories: 1800,
    carbs:    150,
    sugar:    25,
    protein:  65,
    fat:      55,
  ),
  'Moderate': _DiabetesNutrientGoals(
    calories: 1600,
    carbs:    120,
    sugar:    20,
    protein:  60,
    fat:      45,
  ),
  'Severe': _DiabetesNutrientGoals(
    calories: 1400,
    carbs:    100,
    sugar:    15,
    protein:  55,
    fat:      40,
  ),
};

// Fallback if diabetes type is unknown/not set
const _defaultGoals = _DiabetesNutrientGoals(
  calories: 1800,
  carbs:    150,
  sugar:    25,
  protein:  60,
  fat:      50,
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
  double sugarProgress    = 0.0;
  double carbsProgress    = 0.0;
  double proteinProgress  = 0.0;
  double fatProgress      = 0.0;
  double weeklyGoalProgress = 0.0;

  double todayCalories = 0;
  double todaySugar    = 0;
  double todayCarbs    = 0;
  double todayProtein  = 0;
  double todayFat      = 0;

  String diabetesType = "Loading...";
  String? profilePictureUrl;
  List<Map<String, dynamic>> recentScans = [];

  // These are set dynamically from _diabetesGoals based on user's type
  double dailyCalorieGoal = 1800;
  double dailySugarGoal   = 25;
  double dailyCarbGoal    = 150;
  double dailyProteinGoal = 60;
  double dailyFatGoal     = 50;
  double weeklyScanGoal   = 10;

  static const double _cautionThreshold = 0.75;
  static const double _dangerThreshold  = 1.0;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _fetchDashboardData();
      _fetchUserDiabetesType();
      _fetchProfilePicture();
    }
  }

  Future<void> _fetchUserDiabetesType() async {
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user!.uid).get();
      final type = doc.exists ? (doc.data()?['diabetesType'] ?? 'Not set') : 'Not set';
      setState(() => diabetesType = type);
    } catch (e) {
      setState(() => diabetesType = "Error loading type");
      debugPrint("⚠️ Error fetching diabetes type: $e");
    }
  }

  Future<void> _fetchProfilePicture() async {
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user!.uid).get();
      if (doc.exists) {
        final data = doc.data();
        final pictureUrl = data?['profilePictureUrl'] ??
            data?['profilePicture'] ??
            data?['photoUrl'] ??
            data?['profileImage'] ??
            data?['imageUrl'];
        setState(() => profilePictureUrl = pictureUrl);
      }
    } catch (e) {
      debugPrint("Error fetching profile picture: $e");
    }
  }

  // ── Resolve goals for this user's diabetes type ────────────────────────
  _DiabetesNutrientGoals _resolveGoals(String type, Map<String, dynamic> userData) {
    // Check if user has set custom goals in Firestore — respect those first
    if (userData.containsKey('dailyCalorieGoal')) {
      return _DiabetesNutrientGoals(
        calories: (userData['dailyCalorieGoal'] ?? _defaultGoals.calories).toDouble(),
        carbs:    (userData['dailyCarbGoal']    ?? _defaultGoals.carbs).toDouble(),
        sugar:    (userData['dailySugarGoal']   ?? _defaultGoals.sugar).toDouble(),
        protein:  (userData['dailyProteinGoal'] ?? _defaultGoals.protein).toDouble(),
        fat:      (userData['dailyFatGoal']     ?? _defaultGoals.fat).toDouble(),
      );
    }
    // Otherwise use the diabetes-type standard
    return _diabetesGoals[type] ?? _defaultGoals;
  }

  Future<void> _fetchDashboardData() async {
    if (user == null) return;
    try {
      final now   = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final foodLogsSnapshot = await _firestore
          .collection('users')
          .doc(user!.uid)
          .collection('foodLogs')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(today))
          .where('timestamp',
              isLessThan: Timestamp.fromDate(today.add(const Duration(days: 1))))
          .get();

      final userDoc  = await _firestore.collection('users').doc(user!.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};

      // Get current diabetes type from Firestore
      final type   = (userData['diabetesType'] ?? diabetesType).toString();
      final goals  = _resolveGoals(type, userData);
      final scanGoal = (userData['weeklyScanGoal'] ?? 10).toDouble();

      double cal = 0, carbs = 0, sugar = 0, protein = 0, fat = 0;
      int weekScans = 0;

      for (var doc in foodLogsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final nutrition = data['nutrition'] as Map<String, dynamic>? ?? {};
        cal     += _d(nutrition['calories']);
        carbs   += _d(nutrition['carbs']);
        sugar   += _d(nutrition['sugar']);
        protein += _d(nutrition['protein']);
        fat     += _d(nutrition['fat']);

        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
        if (timestamp != null &&
            (data['imagePath'] != null || data['scannedFood'] == true)) {
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          if (timestamp.isAfter(weekStart)) weekScans++;
        }
      }

      setState(() {
        dailyCalorieGoal = goals.calories;
        dailyCarbGoal    = goals.carbs;
        dailySugarGoal   = goals.sugar;
        dailyProteinGoal = goals.protein;
        dailyFatGoal     = goals.fat;
        weeklyScanGoal   = scanGoal;

        todayCalories = cal;
        todayCarbs    = carbs;
        todaySugar    = sugar;
        todayProtein  = protein;
        todayFat      = fat;

        caloriesProgress  = goals.calories > 0 ? (cal     / goals.calories).clamp(0.0, 1.5) : 0.0;
        sugarProgress     = goals.sugar    > 0 ? (sugar   / goals.sugar).clamp(0.0, 1.5)    : 0.0;
        carbsProgress     = goals.carbs    > 0 ? (carbs   / goals.carbs).clamp(0.0, 1.5)    : 0.0;
        proteinProgress   = goals.protein  > 0 ? (protein / goals.protein).clamp(0.0, 1.5)  : 0.0;
        fatProgress       = goals.fat      > 0 ? (fat     / goals.fat).clamp(0.0, 1.5)      : 0.0;
        weeklyGoalProgress = scanGoal      > 0 ? (weekScans / scanGoal).clamp(0.0, 1.0)     : 0.0;

        recentScans = foodLogsSnapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['imagePath'] != null || data['scannedFood'] == true;
        }).map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'name':  data['foodName'] ?? data['name'] ?? 'Unknown',
            'image': data['imagePath'] ?? "assets/images/default.png",
          };
        }).take(5).toList();
      });

      _checkNutrientWarnings(cal, carbs, sugar, fat, goals);

    } catch (e) {
      debugPrint("Error fetching dashboard data: $e");
    }
  }

  // ── Warning popup ──────────────────────────────────────────────────────
  void _checkNutrientWarnings(
    double cal, double carbs, double sugar, double fat,
    _DiabetesNutrientGoals goals,
  ) {
    final exceeded = <String>[];
    if (cal   > goals.calories) exceeded.add('🔥 Calories (${cal.toStringAsFixed(0)} / ${goals.calories.toInt()} kcal)');
    if (sugar > goals.sugar)    exceeded.add('🍬 Sugar (${sugar.toStringAsFixed(1)} / ${goals.sugar.toInt()} g)');
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
              Text(
                'You exceeded your $diabetesType diabetes daily limits:',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 10),
              ...exceeded.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.circle, color: Colors.red, size: 8),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(e,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.red)),
                  ),
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
                  '⚠️ As a $diabetesType diabetic, exceeding these limits may significantly spike your blood sugar. Please eat lighter meals for the rest of the day.',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C6E49),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Logout")),
        ],
      ),
    );
    if (shouldLogout == true) {
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
    if (progress >= _dangerThreshold)  return Colors.red;
    if (progress >= _cautionThreshold) return Colors.orange;
    return defaultColor;
  }

  // ── Badge color for diabetes type label ───────────────────────────────
  Color _typeColor(String type) {
    switch (type) {
      case 'Mild':     return Colors.green;
      case 'Moderate': return Colors.orange;
      case 'Severe':   return Colors.red;
      default:         return const Color(0xFF2C6E49);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("No user is logged in. Please log in.")),
      );
    }

    final name        = user?.displayName ?? "User";
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen  = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchDashboardData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(isSmallScreen ? 12 : isMediumScreen ? 16 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ─────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const EditProfileScreen()),
                            ).then((_) {
                              _fetchUserDiabetesType();
                              _fetchProfilePicture();
                              _fetchDashboardData();
                            });
                          },
                          child: Container(
                            width:  isSmallScreen ? 45 : isMediumScreen ? 55 : 60,
                            height: isSmallScreen ? 45 : isMediumScreen ? 55 : 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF2C6E49), width: 3),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4))
                              ],
                            ),
                            child: ClipOval(
                              child: profilePictureUrl != null && profilePictureUrl!.isNotEmpty
                                  ? Image.network(profilePictureUrl!, fit: BoxFit.cover,
                                      loadingBuilder: (context, child, progress) {
                                        if (progress == null) return child;
                                        return Container(color: Colors.grey.shade200,
                                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
                                      },
                                      errorBuilder: (context, error, _) => Container(
                                          color: const Color(0xFF2C6E49),
                                          child: Icon(Icons.person, color: Colors.white,
                                              size: isSmallScreen ? 25 : isMediumScreen ? 30 : 35)))
                                  : Container(color: const Color(0xFF2C6E49),
                                      child: Icon(Icons.person, color: Colors.white,
                                          size: isSmallScreen ? 25 : isMediumScreen ? 30 : 35)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Hello, $name 👋",
                                style: TextStyle(
                                    fontSize: isSmallScreen ? 16 : isMediumScreen ? 19 : 22,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF2C6E49))),
                            SizedBox(height: isSmallScreen ? 2 : 4),
                            // ── Diabetes type badge with severity color ──
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _typeColor(diabetesType).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: _typeColor(diabetesType).withOpacity(0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.monitor_heart,
                                          size: 11, color: _typeColor(diabetesType)),
                                      const SizedBox(width: 3),
                                      Text("$diabetesType Diabetes",
                                          style: TextStyle(
                                              fontSize: isSmallScreen ? 10 : 12,
                                              fontWeight: FontWeight.w700,
                                              color: _typeColor(diabetesType))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: isSmallScreen ? 2 : 4),
                            Text("Track your health progress",
                                style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: isSmallScreen ? 10 : isMediumScreen ? 12 : 13)),
                          ],
                        ),
                      ],
                    ),
                    _buildSquareButton(icon: Icons.logout, onPressed: _confirmLogout),
                  ],
                ),

                SizedBox(height: isSmallScreen ? 12 : isMediumScreen ? 18 : 20),

                // ── Nutrient Tracking ───────────────────────────────────
                Row(
                  children: [
                    Expanded(child: _sectionTitle("Today's Nutrient Tracking")),
                  ],
                ),
                const SizedBox(height: 4),

                // ── Per-type goals info strip ───────────────────────────
                _buildGoalsInfoStrip(),

                SizedBox(height: isSmallScreen ? 8 : 10),

                // Legend
                Row(
                  children: [
                    Expanded(
                      child: Text('Swipe to see all • Log meals to update',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    ),
                    _legendDot(Colors.green, 'OK'),
                    const SizedBox(width: 6),
                    _legendDot(Colors.orange, 'Caution'),
                    const SizedBox(width: 6),
                    _legendDot(Colors.red, 'Exceeded'),
                  ],
                ),
                SizedBox(height: isSmallScreen ? 8 : 10),

                SizedBox(
                  height: isSmallScreen ? 155 : isMediumScreen ? 160 : 165,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    children: [
                      _buildCircleStat("Calories", caloriesProgress, Colors.orange,
                          "${todayCalories.toStringAsFixed(0)}\n${dailyCalorieGoal.toInt()} kcal"),
                      _buildCircleStat("Carbs", carbsProgress, Colors.blueAccent,
                          "${todayCarbs.toStringAsFixed(1)}\n${dailyCarbGoal.toInt()}g"),
                      _buildCircleStat("Protein", proteinProgress, Colors.purple,
                          "${todayProtein.toStringAsFixed(1)}\n${dailyProteinGoal.toInt()}g"),
                      _buildCircleStat("Fat", fatProgress, Colors.brown,
                          "${todayFat.toStringAsFixed(1)}\n${dailyFatGoal.toInt()}g"),
                      _buildCircleStat("Sugar", sugarProgress, Colors.redAccent,
                          "${todaySugar.toStringAsFixed(1)}\n${dailySugarGoal.toInt()}g"),
                    ],
                  ),
                ),

                // Status banner
                _buildNutrientStatusBanner(),

                SizedBox(height: isSmallScreen ? 15 : isMediumScreen ? 20 : 25),

                _buildQuickAddMealCard(isSmallScreen, isMediumScreen),

                SizedBox(height: isSmallScreen ? 15 : isMediumScreen ? 20 : 25),

                _sectionTitle("Goal Progress"),
                GoalProgressScreen(
                  weeklyGoalProgress: weeklyGoalProgress,
                  goalText: "Weekly goal: ${(weeklyGoalProgress * 100).toInt()}% completed",
                ),

                SizedBox(height: isSmallScreen ? 15 : isMediumScreen ? 20 : 25),

                _sectionTitle("Recent Scans"),
                SizedBox(
                  height: isSmallScreen ? 100 : isMediumScreen ? 115 : 130,
                  child: recentScans.isEmpty
                      ? Center(child: Text("No recent scans yet",
                          style: TextStyle(color: Colors.grey.shade600)))
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: recentScans.length,
                          separatorBuilder: (_, __) =>
                              SizedBox(width: isSmallScreen ? 8 : 12),
                          itemBuilder: (_, index) {
                            final scan = recentScans[index];
                            return _buildScanCard(scan['name'], scan['image']);
                          },
                        ),
                ),

                SizedBox(height: isSmallScreen ? 15 : isMediumScreen ? 20 : 25),

                _sectionTitle("Do & Don't Eat (Diabetic)"),
                SizedBox(height: isSmallScreen ? 6 : 8),
                Text(
                  "Foods added by admin will appear here instantly! 🎉",
                  style: TextStyle(
                      fontSize: isSmallScreen ? 10 : 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic),
                ),
                SizedBox(height: isSmallScreen ? 8 : 12),
                _buildDoDontCards(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF2C6E49),
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 1) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FoodScannerScreen()));
          } else if (index == 2) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MealLogScreen()))
                .then((_) => _fetchDashboardData());
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home),       label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: "Scanner"),
          BottomNavigationBarItem(icon: Icon(Icons.book),       label: "Meal Log"),
        ],
      ),
    );
  }

  // ── Goals info strip showing current type's limits ─────────────────────
  Widget _buildGoalsInfoStrip() {
    final goals = _diabetesGoals[diabetesType];
    if (goals == null) return const SizedBox.shrink();

    final color = _typeColor(diabetesType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.info_outline, size: 13, color: color),
            const SizedBox(width: 5),
            Text('$diabetesType Diabetes — Your Daily Limits',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _goalChip('🔥 ${goals.calories.toInt()} kcal', color),
              _goalChip('🍞 ${goals.carbs.toInt()}g carbs', color),
              _goalChip('🍬 ${goals.sugar.toInt()}g sugar', color),
              _goalChip('💪 ${goals.protein.toInt()}g protein', color),
              _goalChip('🧈 ${goals.fat.toInt()}g fat', color),
            ],
          ),
        ],
      ),
    );
  }

  Widget _goalChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
      ],
    );
  }

  // ── Status banner below charts ─────────────────────────────────────────
  Widget _buildNutrientStatusBanner() {
    final exceeded = <String>[];
    final caution  = <String>[];

    void check(double p, String name) {
      if (p >= _dangerThreshold)       exceeded.add(name);
      else if (p >= _cautionThreshold) caution.add(name);
    }

    check(caloriesProgress, 'Calories');
    check(carbsProgress,    'Carbs');
    check(sugarProgress,    'Sugar');
    check(fatProgress,      'Fat');
    check(proteinProgress,  'Protein');

    if (exceeded.isEmpty && caution.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text('✅ All nutrients within your diabetic-safe limits today!',
                style: TextStyle(
                    fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }

    return Column(children: [
      if (exceeded.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Row(children: [
            const Icon(Icons.dangerous_outlined, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '🚨 Limit exceeded: ${exceeded.join(', ')} — reduce intake now!',
                style: const TextStyle(
                    fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ],
      if (caution.isNotEmpty) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚠️ Approaching limit: ${caution.join(', ')} — eat carefully!',
                style: const TextStyle(
                    fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }

  void _openAddFoodFromDashboard(String mealType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddFoodSheet(preselectedMeal: mealType),
    ).then((_) => _fetchDashboardData());
  }

  Widget _buildQuickAddMealCard(bool isSmallScreen, bool isMediumScreen) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C6E49), Color(0xFF4CAF50)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF2C6E49).withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.add_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('Log Your Meal',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: isSmallScreen ? 14 : 16)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MealLogScreen()))
                  .then((_) => _fetchDashboardData()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('View All',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Tap a meal to log food directly',
              style: TextStyle(
                  color: Colors.white60, fontSize: isSmallScreen ? 10 : 11)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _mealShortcut('🌅', 'Breakfast'),
              _mealShortcut('☀️', 'Lunch'),
              _mealShortcut('🌙', 'Dinner'),
              _mealShortcut('🍎', 'Snack'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mealShortcut(String emoji, String label) {
    return GestureDetector(
      onTap: () => _openAddFoodFromDashboard(label),
      child: Column(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white30, width: 1.5),
          ),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ]),
    );
  }

  Widget _buildSquareButton({required IconData icon, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF2C6E49),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: const Color.fromRGBO(0, 128, 128, 0.3),
                blurRadius: 5,
                offset: const Offset(2, 2))
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    final screenWidth    = MediaQuery.of(context).size.width;
    final isSmallScreen  = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;
    return Text(title,
        style: TextStyle(
            fontSize: isSmallScreen ? 14 : isMediumScreen ? 16 : 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF2C6E49)));
  }

  // ── Circle stat with dynamic warning states ────────────────────────────
  Widget _buildCircleStat(
      String label, double progress, Color defaultColor, String detailText) {
    final displayProgress = progress.clamp(0.0, 1.0);
    final color      = _nutrientColor(progress, defaultColor);
    final isExceeded = progress >= _dangerThreshold;
    final isCaution  = progress >= _cautionThreshold && !isExceeded;

    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.18),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
        border: Border.all(
          color: isExceeded ? Colors.red : isCaution ? Colors.orange : color.withOpacity(0.15),
          width: isExceeded || isCaution ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 64, height: 64,
                child: CircularProgressIndicator(
                  value: displayProgress,
                  strokeWidth: 7,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              if (isExceeded)
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.07), shape: BoxShape.circle),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 24),
                )
              else if (isCaution)
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.07), shape: BoxShape.circle),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 22),
                )
              else
                Text("${(progress * 100).toInt()}%",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12, color: color)),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold, fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
              if (isExceeded) ...[
                const SizedBox(width: 2),
                const Icon(Icons.error, color: Colors.red, size: 11),
              ] else if (isCaution) ...[
                const SizedBox(width: 2),
                const Icon(Icons.info, color: Colors.orange, size: 11),
              ],
            ],
          ),
          if (isExceeded || isCaution)
            Text("${(progress * 100).toInt()}%",
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 10, color: color)),
          const SizedBox(height: 1),
          Text(detailText,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 2),
          if (isExceeded)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('EXCEEDED',
                  style: TextStyle(
                      fontSize: 7, color: Colors.red, fontWeight: FontWeight.bold)),
            )
          else if (isCaution)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('CAUTION',
                  style: TextStyle(
                      fontSize: 7, color: Colors.orange, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _buildScanCard(String foodName, String imagePath) {
    final screenWidth    = MediaQuery.of(context).size.width;
    final isSmallScreen  = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;
    return Container(
      width: isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color.fromRGBO(128, 128, 128, 0.2),
              blurRadius: 6, offset: const Offset(2, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: imagePath.startsWith("http")
                ? Image.network(imagePath,
                    width:  isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                    height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width:  isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                        height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                        color: Colors.grey.shade200,
                        child: Icon(Icons.fastfood, color: Colors.grey,
                            size: isSmallScreen ? 20 : isMediumScreen ? 25 : 30)))
                : Image.asset(imagePath,
                    width:  isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                    height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width:  isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                        height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                        color: Colors.grey.shade200,
                        child: Icon(Icons.fastfood, color: Colors.grey,
                            size: isSmallScreen ? 20 : isMediumScreen ? 25 : 30))),
          ),
          SizedBox(height: isSmallScreen ? 4 : 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 4 : 6),
            child: Text(foodName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isSmallScreen ? 9 : isMediumScreen ? 10 : 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildDoDontCards() {
    final screenWidth    = MediaQuery.of(context).size.width;
    final isSmallScreen  = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;

    if (diabetesType == 'Not set' ||
        diabetesType == "Error loading type" ||
        diabetesType == "Loading...") {
      return SizedBox(
        height: isSmallScreen ? 120 : isMediumScreen ? 135 : 150,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restaurant_menu,
                  size: isSmallScreen ? 35 : isMediumScreen ? 42 : 50,
                  color: Colors.grey.shade400),
              SizedBox(height: isSmallScreen ? 6 : 8),
              Text(
                diabetesType == "Error loading type"
                    ? 'Failed to load recommendations'
                    : 'Loading food recommendations...',
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: isSmallScreen ? 12 : isMediumScreen ? 14 : 16),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: isSmallScreen ? 120 : isMediumScreen ? 135 : 150,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('food_rules').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red)));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No foods available yet',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14)));
          }

          final docs     = snapshot.data!.docs;
          final filtered = docs.where((doc) {
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

          final doFoods   = filtered.where((d) => d['category'] == 'Do').toList();
          final dontFoods = filtered.where((d) => d['category'] == "Don't").toList();

          return ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap: () => _openDoDontScreen(
                    "✅ DO - Recommended Foods",
                    _buildFoodCardsFromDocs(doFoods), doFoods.length),
                child: _buildDoDontCard(
                    "✅ DO", "(${doFoods.length} foods)", Colors.green.shade300),
              ),
              SizedBox(width: isSmallScreen ? 8 : 12),
              GestureDetector(
                onTap: () => _openDoDontScreen(
                    "🚫 DON'T - Foods to Avoid",
                    _buildFoodCardsFromDocs(dontFoods), dontFoods.length),
                child: _buildDoDontCard(
                    "🚫 DON'T", "(${dontFoods.length} foods)", Colors.red.shade300),
              ),
            ],
          );
        },
      ),
    );
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

  Widget _buildDoDontCard(String title, String subtitle, Color color) {
    final screenWidth    = MediaQuery.of(context).size.width;
    final isSmallScreen  = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;
    return Container(
      width: isSmallScreen ? 140 : isMediumScreen ? 160 : 180,
      decoration: BoxDecoration(
        color: color.withAlpha((0.8 * 255).round()),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: color.withAlpha((0.3 * 255).round()),
            blurRadius: 8, offset: const Offset(2, 4))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: isSmallScreen ? 16 : isMediumScreen ? 18 : 20,
                  fontWeight: FontWeight.bold, color: Colors.white)),
          SizedBox(height: isSmallScreen ? 2 : 4),
          Text(subtitle,
              style: TextStyle(
                  fontSize: isSmallScreen ? 10 : isMediumScreen ? 11 : 12,
                  color: Colors.white70)),
        ],
      ),
    );
  }

  List<Widget> _buildFoodCardsFromDocs(List<QueryDocumentSnapshot> foodDocs) {
    return foodDocs.map((doc) {
      final data     = doc.data() as Map<String, dynamic>;
      final name     = data['name'] ?? "Unknown Food";
      final imageUrl = data['imageUrl'] ?? data['imagePath'] ?? '';
      return _buildFoodCard(imageUrl, name, data);
    }).toList();
  }

  Widget _buildFoodCard(String imageUrl, String foodName, Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: imageUrl.isNotEmpty
                  ? Image.network(imageUrl,
                      width: 60, height: 60, fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(width: 60, height: 60,
                            color: Colors.grey.shade200,
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
                      },
                      errorBuilder: (_, __, ___) => Container(width: 60, height: 60,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.fastfood, color: Colors.grey, size: 30)))
                  : Container(width: 60, height: 60,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.fastfood, color: Colors.grey, size: 30)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(foodName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold,
                          color: Color(0xFF2C6E49)),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(data['portionSize'] ?? 'N/A',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 2, children: [
                    NutrientTile(label: 'Carbs',   value: '${data['carbs']    ?? 0}g'),
                    NutrientTile(label: 'Protein', value: '${data['protein']  ?? 0}g'),
                    NutrientTile(label: 'Fat',     value: '${data['fat']      ?? 0}g'),
                    NutrientTile(label: 'Sugar',   value: '${data['sugar']    ?? 0}g'),
                    NutrientTile(label: 'Cal',     value: '${data['calories'] ?? 0} kcal'),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NutrientTile extends StatelessWidget {
  final String label;
  final String value;
  const NutrientTile({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
          color: Colors.grey.shade100, borderRadius: BorderRadius.circular(3)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label ",
              style: const TextStyle(
                  fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500)),
          Text(value,
              style: const TextStyle(
                  fontSize: 10, color: Colors.black87, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}