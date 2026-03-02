import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetechapp/Screens/edit_profile.dart';
import 'package:diabetechapp/Screens/foodscanner.dart';
import 'package:diabetechapp/Screens/log_in.dart';
import 'package:diabetechapp/Screens/meal_log_screen.dart';
import 'package:diabetechapp/health/goal_progress.dart';
import 'package:diabetechapp/health/do_dont_foods_screen.dart';

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

  // Actual consumed values for display
  double todayCalories = 0;
  double todaySugar    = 0;
  double todayCarbs    = 0;
  double todayProtein  = 0;
  double todayFat      = 0;

  String diabetesType = "Loading...";
  String? profilePictureUrl;
  List<Map<String, dynamic>> recentScans = [];

  double dailyCalorieGoal = 2000;
  double dailySugarGoal   = 50;
  double dailyCarbGoal    = 300;
  double dailyProteinGoal = 60;
  double dailyFatGoal     = 65;
  double weeklyScanGoal   = 10;

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
      setState(() {
        diabetesType =
            doc.exists ? (doc.data()?['diabetesType'] ?? 'Not set') : 'Not set';
      });
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

  Future<void> _fetchDashboardData() async {
    if (user == null) return;
    try {
      final now   = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Fetch today's food logs
      final foodLogsSnapshot = await _firestore
          .collection('users')
          .doc(user!.uid)
          .collection('foodLogs')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(today))
          .where('timestamp',
              isLessThan:
                  Timestamp.fromDate(today.add(const Duration(days: 1))))
          .get();

      // Fetch user profile for goals
      final userDoc  = await _firestore.collection('users').doc(user!.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};

      final calGoal     = (userData['dailyCalorieGoal'] ?? 2000).toDouble();
      final carbGoal    = (userData['dailyCarbGoal']    ?? 300).toDouble();
      final sugarGoal   = (userData['dailySugarGoal']   ?? 50).toDouble();
      final proteinGoal = (userData['dailyProteinGoal'] ?? 60).toDouble();
      final fatGoal     = (userData['dailyFatGoal']     ?? 65).toDouble();
      final scanGoal    = (userData['weeklyScanGoal']   ?? 10).toDouble();

      double cal = 0, carbs = 0, sugar = 0, protein = 0, fat = 0;
      int weekScans = 0;

      for (var doc in foodLogsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // ── Read nutrition from the nested 'nutrition' map ──────────
        // This is what meal_log_screen.dart writes when user manually logs
        final nutrition = data['nutrition'] as Map<String, dynamic>? ?? {};
        cal     += _d(nutrition['calories']);
        carbs   += _d(nutrition['carbs']);
        sugar   += _d(nutrition['sugar']);
        protein += _d(nutrition['protein']);
        fat     += _d(nutrition['fat']);

        // Count scanned foods this week
        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
        if (timestamp != null &&
            (data['imagePath'] != null || data['scannedFood'] == true)) {
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          if (timestamp.isAfter(weekStart)) weekScans++;
        }
      }

      setState(() {
        dailyCalorieGoal = calGoal;
        dailyCarbGoal    = carbGoal;
        dailySugarGoal   = sugarGoal;
        dailyProteinGoal = proteinGoal;
        dailyFatGoal     = fatGoal;
        weeklyScanGoal   = scanGoal;

        todayCalories = cal;
        todayCarbs    = carbs;
        todaySugar    = sugar;
        todayProtein  = protein;
        todayFat      = fat;

        caloriesProgress  = calGoal     > 0 ? (cal     / calGoal).clamp(0.0, 1.0)     : 0.0;
        sugarProgress     = sugarGoal   > 0 ? (sugar   / sugarGoal).clamp(0.0, 1.0)   : 0.0;
        carbsProgress     = carbGoal    > 0 ? (carbs   / carbGoal).clamp(0.0, 1.0)    : 0.0;
        proteinProgress   = proteinGoal > 0 ? (protein / proteinGoal).clamp(0.0, 1.0) : 0.0;
        fatProgress       = fatGoal     > 0 ? (fat     / fatGoal).clamp(0.0, 1.0)     : 0.0;
        weeklyGoalProgress = scanGoal   > 0 ? (weekScans / scanGoal).clamp(0.0, 1.0)  : 0.0;

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
    } catch (e) {
      debugPrint("Error fetching dashboard data: $e");
    }
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
                // ── Header ──────────────────────────────────────────────
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
                            });
                          },
                          child: Container(
                            width:  isSmallScreen ? 45 : isMediumScreen ? 55 : 60,
                            height: isSmallScreen ? 45 : isMediumScreen ? 55 : 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFF2C6E49), width: 3),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4))
                              ],
                            ),
                            child: ClipOval(
                              child: profilePictureUrl != null &&
                                      profilePictureUrl!.isNotEmpty
                                  ? Image.network(
                                      profilePictureUrl!,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, progress) {
                                        if (progress == null) return child;
                                        return Container(
                                          color: Colors.grey.shade200,
                                          child: const Center(
                                              child:
                                                  CircularProgressIndicator(strokeWidth: 2)),
                                        );
                                      },
                                      errorBuilder: (context, error, _) =>
                                          Container(
                                            color: const Color(0xFF2C6E49),
                                            child: Icon(Icons.person,
                                                color: Colors.white,
                                                size: isSmallScreen ? 25 : isMediumScreen ? 30 : 35),
                                          ),
                                    )
                                  : Container(
                                      color: const Color(0xFF2C6E49),
                                      child: Icon(Icons.person,
                                          color: Colors.white,
                                          size: isSmallScreen ? 25 : isMediumScreen ? 30 : 35),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Hello, $name 👋",
                              style: TextStyle(
                                  fontSize: isSmallScreen ? 16 : isMediumScreen ? 19 : 22,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF2C6E49)),
                            ),
                            SizedBox(height: isSmallScreen ? 2 : 4),
                            Text("Type: $diabetesType",
                                style: TextStyle(
                                    fontSize: isSmallScreen ? 12 : isMediumScreen ? 14 : 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black54)),
                            SizedBox(height: isSmallScreen ? 2 : 4),
                            Text("Track your health progress",
                                style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: isSmallScreen ? 10 : isMediumScreen ? 12 : 13)),
                          ],
                        ),
                      ],
                    ),
                    _buildSquareButton(
                        icon: Icons.logout, onPressed: _confirmLogout),
                  ],
                ),

                SizedBox(height: isSmallScreen ? 12 : isMediumScreen ? 18 : 20),

                // ── Nutrient Tracking ────────────────────────────────────
                _sectionTitle("Today's Nutrient Tracking"),
                const SizedBox(height: 4),
                Text(
                  'Swipe to see all • Log meals to update',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
                SizedBox(height: isSmallScreen ? 8 : 12),
                SizedBox(
                  height: 140,
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

                SizedBox(height: isSmallScreen ? 15 : isMediumScreen ? 20 : 25),

                // ── Quick add meal shortcut ──────────────────────────────
                _buildQuickAddMealCard(isSmallScreen, isMediumScreen),

                SizedBox(height: isSmallScreen ? 15 : isMediumScreen ? 20 : 25),

                // ── Goal Progress ────────────────────────────────────────
                _sectionTitle("Goal Progress"),
                GoalProgressScreen(
                  weeklyGoalProgress: weeklyGoalProgress,
                  goalText:
                      "Weekly goal: ${(weeklyGoalProgress * 100).toInt()}% completed",
                ),

                SizedBox(height: isSmallScreen ? 15 : isMediumScreen ? 20 : 25),

                // ── Recent Scans ─────────────────────────────────────────
                _sectionTitle("Recent Scans"),
                SizedBox(
                  height: isSmallScreen ? 100 : isMediumScreen ? 115 : 130,
                  child: recentScans.isEmpty
                      ? Center(
                          child: Text("No recent scans yet",
                              style: TextStyle(color: Colors.grey.shade600)),
                        )
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

                // ── Do & Don't Eat ───────────────────────────────────────
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
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MealLogScreen()),
            ).then((_) => _fetchDashboardData()); // refresh after returning
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

  // ── Quick Add Meal Card ─────────────────────────────────────────────────
  // Opens the AddFoodSheet directly from the Dashboard
  void _openAddFoodFromDashboard(String mealType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddFoodSheet(preselectedMeal: mealType),
    ).then((_) => _fetchDashboardData()); // refresh charts after closing
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
          Row(
            children: [
              const Icon(Icons.add_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Log Your Meal',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 14 : 16)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MealLogScreen()),
                ).then((_) => _fetchDashboardData()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('View All',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a meal to log food directly',
            style: TextStyle(
                color: Colors.white60,
                fontSize: isSmallScreen ? 10 : 11),
          ),
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
      onTap: () => _openAddFoodFromDashboard(label), // ← opens sheet directly
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30, width: 1.5),
            ),
            child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  // ── Helper Widgets ──────────────────────────────────────────────────────
  Widget _buildSquareButton(
      {required IconData icon, required VoidCallback onPressed}) {
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

  Widget _buildCircleStat(
      String label, double value, Color color, String detailText) {
    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 7,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Text(
                "${(value * 100).toInt()}%",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            detailText,
            style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 2,
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
              blurRadius: 6,
              offset: const Offset(2, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: imagePath.startsWith("http")
                ? Image.network(imagePath,
                    width:  isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                    height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width:  isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                      height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                      color: Colors.grey.shade200,
                      child: Icon(Icons.fastfood,
                          color: Colors.grey,
                          size: isSmallScreen ? 20 : isMediumScreen ? 25 : 30),
                    ))
                : Image.asset(imagePath,
                    width:  isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                    height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width:  isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                      height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                      color: Colors.grey.shade200,
                      child: Icon(Icons.fastfood,
                          color: Colors.grey,
                          size: isSmallScreen ? 20 : isMediumScreen ? 25 : 30),
                    )),
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
                    fontSize:
                        isSmallScreen ? 9 : isMediumScreen ? 10 : 12)),
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
        stream: FirebaseFirestore.instance
            .collection('food_rules')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red)));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text('No foods available yet',
                  style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 14)),
            );
          }

          final docs = snapshot.data!.docs;
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
                    _buildFoodCardsFromDocs(doFoods),
                    doFoods.length),
                child: _buildDoDontCard(
                    "✅ DO", "(${doFoods.length} foods)", Colors.green.shade300),
              ),
              SizedBox(width: isSmallScreen ? 8 : 12),
              GestureDetector(
                onTap: () => _openDoDontScreen(
                    "🚫 DON'T - Foods to Avoid",
                    _buildFoodCardsFromDocs(dontFoods),
                    dontFoods.length),
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
    Navigator.push(context,
        MaterialPageRoute(
            builder: (_) =>
                DoDontFoodsScreen(title: title, foodCards: cards)));
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
        boxShadow: [
          BoxShadow(
              color: color.withAlpha((0.3 * 255).round()),
              blurRadius: 8,
              offset: const Offset(2, 4))
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: isSmallScreen ? 16 : isMediumScreen ? 18 : 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          SizedBox(height: isSmallScreen ? 2 : 4),
          Text(subtitle,
              style: TextStyle(
                  fontSize: isSmallScreen ? 10 : isMediumScreen ? 11 : 12,
                  color: Colors.white70)),
        ],
      ),
    );
  }

  List<Widget> _buildFoodCardsFromDocs(
      List<QueryDocumentSnapshot> foodDocs) {
    return foodDocs.map((doc) {
      final data     = doc.data() as Map<String, dynamic>;
      final name     = data['name'] ?? "Unknown Food";
      final imageUrl = data['imageUrl'] ?? data['imagePath'] ?? '';

      return _buildFoodCard(imageUrl, name, data);
    }).toList();
  }

  Widget _buildFoodCard(
      String imageUrl, String foodName, Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                        return Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey.shade200,
                            child: const Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)));
                      },
                      errorBuilder: (_, __, ___) => Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.fastfood,
                              color: Colors.grey, size: 30)))
                  : Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.fastfood,
                          color: Colors.grey, size: 30)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(foodName,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C6E49)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(data['portionSize'] ?? 'N/A',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      NutrientTile(label: 'Carbs',   value: '${data['carbs']   ?? 0}g'),
                      NutrientTile(label: 'Protein', value: '${data['protein'] ?? 0}g'),
                      NutrientTile(label: 'Fat',     value: '${data['fat']     ?? 0}g'),
                      NutrientTile(label: 'Sugar',   value: '${data['sugar']   ?? 0}g'),
                      NutrientTile(label: 'Cal',     value: '${data['calories'] ?? 0} kcal'),
                    ],
                  ),
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
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(3)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label ",
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black87,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}