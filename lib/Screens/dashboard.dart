import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetechapp/Screens/edit_profile.dart';
import 'package:diabetechapp/Screens/foodscanner.dart';
import 'package:diabetechapp/Screens/log_in.dart';
import 'package:diabetechapp/health/meal.dart';
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
  double sugarProgress = 0.0;
  double carbsProgress = 0.0;
  double weeklyGoalProgress = 0.0;

  String diabetesType = "Loading...";
  String? profilePictureUrl; // ✅ Added profile picture URL
  List<Map<String, dynamic>> recentScans = [];
  
  // User goals - accessible throughout the class
  double dailyCalorieGoal = 2000;
  double dailySugarGoal = 50;
  double dailyCarbGoal = 300;
  double weeklyScanGoal = 10;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _fetchDashboardData();
      _fetchUserDiabetesType();
      _fetchProfilePicture(); // ✅ Fetch profile picture
    }
  }

  Future<void> _fetchUserDiabetesType() async {
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user!.uid).get();
      setState(() {
        diabetesType = doc.exists
            ? (doc.data()?['diabetesType'] ?? 'Not set')
            : 'Not set';
      });
    } catch (e) {
      setState(() {
        diabetesType = "Error loading type";
      });
      debugPrint("⚠️ Error fetching diabetes type: $e");
    }
  }

  // ✅ NEW: Fetch profile picture from Firestore
  Future<void> _fetchProfilePicture() async {
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user!.uid).get();
      if (doc.exists) {
        final data = doc.data();
        
        // Check multiple possible field names
        final pictureUrl = data?['profilePictureUrl'] ?? 
                          data?['profilePicture'] ?? 
                          data?['photoUrl'] ?? 
                          data?['profileImage'] ?? 
                          data?['imageUrl'];
        
        setState(() {
          profilePictureUrl = pictureUrl;
        });
        
        debugPrint("✅ Profile picture URL: $profilePictureUrl");
        debugPrint("📋 All user data fields: ${data?.keys.toList()}");
      }
    } catch (e) {
      debugPrint(" Error fetching profile picture: $e");
    }
  }

  Future<void> _fetchDashboardData() async {
    if (user == null) return;
    try {
      // Fetch user's food logs
      final foodLogsSnapshot = await _firestore
          .collection('users')
          .doc(user!.uid)
          .collection('foodLogs')
          .orderBy('timestamp', descending: true)
          .limit(50) // Get recent logs
          .get();

      // Fetch user's profile for goals
      final userDoc = await _firestore.collection('users').doc(user!.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      
      // Get user's daily goals
      final dailyCalorieGoal = (userData['dailyCalorieGoal'] ?? 2000).toDouble();
      final dailyCarbGoal = (userData['dailyCarbGoal'] ?? 300).toDouble();
      final dailySugarGoal = (userData['dailySugarGoal'] ?? 50).toDouble();
      final weeklyScanGoal = (userData['weeklyScanGoal'] ?? 10).toDouble();

      // Calculate today's totals
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      double todayCalories = 0;
      double todayCarbs = 0;
      double todaySugar = 0;
      int thisWeekScans = 0;
      
      for (var doc in foodLogsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
        
        if (timestamp != null) {
          final logDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
          
          // Today's nutrition
          if (logDate.year == today.year && logDate.month == today.month && logDate.day == today.day) {
            final nutrition = data['nutrition'] ?? {};
            todayCalories += (nutrition['calories'] ?? 0).toDouble();
            todayCarbs += (nutrition['carbs'] ?? 0).toDouble();
            todaySugar += (nutrition['sugar'] ?? 0).toDouble();
          }
          
          // This week's scans (count logs with images/scans)
          if (data['imagePath'] != null || data['scannedFood'] == true) {
            final weekStart = now.subtract(Duration(days: now.weekday - 1));
            if (timestamp.isAfter(weekStart)) {
              thisWeekScans++;
            }
          }
        }
      }

      setState(() {
        // Calculate progress based on actual goals
        caloriesProgress = dailyCalorieGoal > 0 ? (todayCalories / dailyCalorieGoal).clamp(0.0, 1.0) : 0.0;
        sugarProgress = dailySugarGoal > 0 ? (todaySugar / dailySugarGoal).clamp(0.0, 1.0) : 0.0;
        carbsProgress = dailyCarbGoal > 0 ? (todayCarbs / dailyCarbGoal).clamp(0.0, 1.0) : 0.0;
        weeklyGoalProgress = weeklyScanGoal > 0 ? (thisWeekScans / weeklyScanGoal).clamp(0.0, 1.0) : 0.0;
        
        // Update recent scans for display
        recentScans = foodLogsSnapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['imagePath'] != null || data['scannedFood'] == true;
        }).map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'name': data['foodName'] ?? data['name'] ?? 'Unknown',
            'image': data['imagePath'] ?? "assets/images/default.png",
          };
        }).take(5).toList();
      });
    } catch (e) {
      debugPrint(" Error fetching dashboard data: $e");
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

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("No user is logged in. Please log in.")),
      );
    }

    final name = user?.displayName ?? "User";
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Responsive screen detection for universal compatibility
    final isSmallScreen = screenWidth < 360;     // Budget phones like Infinix
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;   // Standard phones
    final isLargeScreen = screenWidth >= 400;    // Samsung A15 and larger phones

    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isSmallScreen ? 12 : isMediumScreen ? 16 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ UPDATED: Header with Profile Picture
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // ✅ Profile Picture Avatar
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const EditProfileScreen()),
                          ).then((_) {
                            _fetchUserDiabetesType();
                            _fetchProfilePicture(); // Refresh profile picture after edit
                          });
                        },
                        child: Container(
                          width: isSmallScreen ? 45 : isMediumScreen ? 55 : 60,
                          height: isSmallScreen ? 45 : isMediumScreen ? 55 : 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF2C6E49),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: profilePictureUrl != null &&
                                    profilePictureUrl!.isNotEmpty
                                ? Image.network(
                                    profilePictureUrl!,
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        color: Colors.grey.shade200,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      debugPrint("❌ Error loading profile image: $error");
                                      debugPrint("Image URL: $profilePictureUrl");
                                      return Container(
                                        color: const Color(0xFF2C6E49),
                                        child: Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: isSmallScreen ? 25 : isMediumScreen ? 30 : 35,
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    color: const Color(0xFF2C6E49),
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                      size: isSmallScreen ? 25 : isMediumScreen ? 30 : 35,
                                    ),
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
                          Text(
                            "Type: $diabetesType",
                            style: TextStyle(
                                fontSize: isSmallScreen ? 12 : isMediumScreen ? 14 : 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54),
                          ),
                          SizedBox(height: isSmallScreen ? 2 : 4),
                          Text(
                            "Track your health progress",
                            style: TextStyle(
                                color: Colors.black54, 
                                fontSize: isSmallScreen ? 10 : isMediumScreen ? 12 : 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _buildSquareButton(
                    icon: Icons.logout,
                    onPressed: _confirmLogout,
                  ),
                ],
              ),

              SizedBox(height: isSmallScreen ? 12 : isMediumScreen ? 18 : 20),

              // Nutrient Tracking
              _sectionTitle("Nutrient Tracking"),
              SizedBox(
                height: isSmallScreen ? 100 : isMediumScreen ? 110 : 120,
                child: isSmallScreen 
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildCircleStat("Calories", caloriesProgress, Colors.orange, 
                            "${(caloriesProgress * 100).toInt()}% of ${(dailyCalorieGoal ?? 2000).toInt()} kcal"),
                          const SizedBox(width: 12),
                          _buildCircleStat("Sugar", sugarProgress, Colors.redAccent,
                            "${(sugarProgress * 100).toInt()}% of ${(dailySugarGoal ?? 50).toInt()}g"),
                          const SizedBox(width: 12),
                          _buildCircleStat("Carbs", carbsProgress, Colors.blueAccent,
                            "${(carbsProgress * 100).toInt()}% of ${(dailyCarbGoal ?? 300).toInt()}g"),
                        ],
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCircleStat("Calories", caloriesProgress, Colors.orange, 
                          "${(caloriesProgress * 100).toInt()}% of ${(dailyCalorieGoal ?? 2000).toInt()} kcal"),
                        _buildCircleStat("Sugar", sugarProgress, Colors.redAccent,
                          "${(sugarProgress * 100).toInt()}% of ${(dailySugarGoal ?? 50).toInt()}g"),
                        _buildCircleStat("Carbs", carbsProgress, Colors.blueAccent,
                          "${(carbsProgress * 100).toInt()}% of ${(dailyCarbGoal ?? 300).toInt()}g"),
                      ],
                    ),
              ),

              SizedBox(height: isSmallScreen ? 15 : isMediumScreen ? 20 : 25),

              // Goal Progress
              _sectionTitle("Goal Progress"),
              GoalProgressScreen(
                weeklyGoalProgress: weeklyGoalProgress,
                goalText:
                    "Weekly goal: ${(weeklyGoalProgress * 100).toInt()}% completed",
              ),

              SizedBox(height: isSmallScreen ? 15 : isMediumScreen ? 20 : 25),

              // Recent Scans
              _sectionTitle("Recent Scans"),
              SizedBox(
                height: isSmallScreen ? 100 : isMediumScreen ? 115 : 130,
                child: recentScans.isEmpty
                    ? Center(
                        child: Text(
                          "No recent scans yet",
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: recentScans.length,
                        separatorBuilder: (_, __) => SizedBox(width: isSmallScreen ? 8 : 12),
                        itemBuilder: (_, index) {
                          final scan = recentScans[index];
                          return _buildScanCard(scan['name'], scan['image']);
                        },
                      ),
              ),

              SizedBox(height: isSmallScreen ? 15 : isMediumScreen ? 20 : 25),

              // Do & Don't Eat
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF2C6E49),
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 1) {
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => const FoodScannerScreen()));
          } else if (index == 2) {
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => const MealLogScreen()));
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: "Scanner"),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: "Meal Log"),
        ],
      ),
    );
  }

  // --- Helper Widgets ---
  Widget _buildSquareButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF2C6E49),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Color.fromRGBO(0, 128, 128, 0.3),
                blurRadius: 5,
                offset: const Offset(2, 2))
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;
    
    return Text(
      title,
      style: TextStyle(
          fontSize: isSmallScreen ? 14 : isMediumScreen ? 16 : 18, 
          fontWeight: FontWeight.bold, 
          color: const Color(0xFF2C6E49)),
    );
  }

  Widget _buildCircleStat(String label, double value, Color color, String detailText) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;
    
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
              height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: isSmallScreen ? 6 : isMediumScreen ? 7 : 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Text("${(value * 100).toInt()}%",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isSmallScreen ? 10 : isMediumScreen ? 11 : 12,
                )),
          ],
        ),
        SizedBox(height: isSmallScreen ? 4 : 6),
        Text(label,
            style: TextStyle(
              color: color, 
              fontWeight: FontWeight.w500,
              fontSize: isSmallScreen ? 10 : isMediumScreen ? 11 : 12,
            )),
        SizedBox(height: isSmallScreen ? 2 : 4),
        Text(
          detailText,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: isSmallScreen ? 9 : isMediumScreen ? 10 : 11,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildScanCard(String foodName, String imagePath) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;
    
    return Container(
      width: isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Color.fromRGBO(128, 128, 128, 0.2),
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
                ? Image.network(
                    imagePath,
                    width: isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                    height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                      height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                      color: Colors.grey.shade200,
                      child: Icon(Icons.fastfood, color: Colors.grey, size: isSmallScreen ? 20 : isMediumScreen ? 25 : 30),
                    ),
                  )
                : Image.asset(
                    imagePath,
                    width: isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                    height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: isSmallScreen ? 90 : isMediumScreen ? 105 : 120,
                      height: isSmallScreen ? 60 : isMediumScreen ? 70 : 80,
                      color: Colors.grey.shade200,
                      child: Icon(Icons.fastfood, color: Colors.grey, size: isSmallScreen ? 20 : isMediumScreen ? 25 : 30),
                    ),
                  ),
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
                  fontSize: isSmallScreen ? 9 : isMediumScreen ? 10 : 12,
                )),
          ),
        ],
      ),
    );
  }

  Widget _buildDoDontCards() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;
    
    // Show loading or error state if diabetes type is not available
    debugPrint("🔍 Diabetes type check: diabetesType = '$diabetesType'");
    if (diabetesType == null || diabetesType == 'Not set' || diabetesType == "Error loading type" || diabetesType == "Loading...") {
      debugPrint("🔍 Showing loading/error state for diabetes type: $diabetesType");
      return SizedBox(
        height: isSmallScreen ? 120 : isMediumScreen ? 135 : 150,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restaurant_menu, size: isSmallScreen ? 35 : isMediumScreen ? 42 : 50, color: Colors.grey.shade400),
              SizedBox(height: isSmallScreen ? 6 : 8),
              Text(
                diabetesType == "Error loading type" ? 'Failed to load recommendations' : 'Loading food recommendations...',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: isSmallScreen ? 12 : isMediumScreen ? 14 : 16,
                ),
              ),
              if (diabetesType == "Error loading type") ...[
                SizedBox(height: isSmallScreen ? 6 : 8),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => diabetesType = "Loading...");
                    _fetchUserDiabetesType();
                  },
                  icon: Icon(Icons.refresh, size: isSmallScreen ? 14 : 16),
                  label: Text('Retry', style: TextStyle(fontSize: isSmallScreen ? 12 : 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: Size(isSmallScreen ? 80 : 100, isSmallScreen ? 30 : 35),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    
    debugPrint("🔍 Building StreamBuilder with diabetesType: $diabetesType");
    return SizedBox(
      height: isSmallScreen ? 120 : isMediumScreen ? 135 : 150,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('food_rules')
            .snapshots(), // Fetch all foods, filter client-side
        builder: (context, snapshot) {
          try {
            debugPrint("🔍 StreamBuilder state: ${snapshot.connectionState}, hasError: ${snapshot.hasError}");
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              debugPrint("❌ StreamBuilder error: ${snapshot.error}");
              return Center(
                child: Text(
                  'Error loading foods: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restaurant_menu, size: isSmallScreen ? 35 : isMediumScreen ? 42 : 50, color: Colors.grey.shade400),
                    SizedBox(height: isSmallScreen ? 6 : 8),
                    Text(
                      'No foods available yet',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: isSmallScreen ? 12 : isMediumScreen ? 14 : 16,
                      ),
                    ),
                    Text(
                      'Admin will add foods for $diabetesType diabetes soon!',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10 : isMediumScreen ? 11 : 12, 
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }

            final docs = snapshot.data!.docs;
            debugPrint("🔍 Found ${docs.length} total foods in database");
            
            // Filter foods by user's diabetes type (client-side)
            final filteredDocs = docs.where((doc) {
              final docData = doc.data() as Map<String, dynamic>?;
              if (docData == null) return false;
              
              final docDiabetesType = docData['diabetesType']?.toString();
              debugPrint("🔍 Food: ${docData['name']} - DiabetesType: $docDiabetesType");
              return docDiabetesType == diabetesType;
            }).toList();
            
            debugPrint("🔍 After filtering: ${filteredDocs.length} foods match user's diabetes type ($diabetesType)");
            
            // Sort client-side by createdAt (newest first)
            filteredDocs.sort((a, b) {
              final aTime = a['createdAt'] as Timestamp?;
              final bTime = b['createdAt'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime); // Descending order
            });
            
            final doFoods = filteredDocs.where((doc) => doc['category'] == 'Do').toList();
            final dontFoods = filteredDocs.where((doc) => doc['category'] == "Don't").toList();

          return ListView(
            scrollDirection: Axis.horizontal,
            children: [
              GestureDetector(
                onTap: () => _openDoDontScreen(
                  "✅ DO - Recommended Foods",
                  _buildFoodCardsFromDocs(doFoods),
                  doFoods.length,
                ),
                child: _buildDoDontCard(
                  "✅ DO",
                  "(${doFoods.length} foods)",
                  Colors.green.shade300,
                ),
              ),
              SizedBox(width: isSmallScreen ? 8 : 12),
              GestureDetector(
                onTap: () => _openDoDontScreen(
                  "🚫 DON'T - Foods to Avoid",
                  _buildFoodCardsFromDocs(dontFoods),
                  dontFoods.length,
                ),
                child: _buildDoDontCard(
                  "🚫 DON'T",
                  "(${dontFoods.length} foods)",
                  Colors.red.shade300,
                ),
              ),
            ],
          );
          } catch (e) {
            debugPrint("❌ Unexpected error in StreamBuilder: $e");
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: isSmallScreen ? 35 : isMediumScreen ? 42 : 50, color: Colors.red.shade400),
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  Text(
                    'Something went wrong',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: isSmallScreen ? 12 : isMediumScreen ? 14 : 16,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 4 : 6),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {});
                    },
                    icon: Icon(Icons.refresh, size: isSmallScreen ? 14 : 16),
                    label: Text('Retry', style: TextStyle(fontSize: isSmallScreen ? 12 : 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: Size(isSmallScreen ? 80 : 100, isSmallScreen ? 30 : 35),
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
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

  Widget _buildDoDontCard(String title, String subtitle, Color color) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
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
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
                fontSize: isSmallScreen ? 16 : isMediumScreen ? 18 : 20, 
                fontWeight: FontWeight.bold, 
                color: Colors.white),
          ),
          SizedBox(height: isSmallScreen ? 2 : 4),
          Text(
            subtitle,
            style: TextStyle(
                fontSize: isSmallScreen ? 10 : isMediumScreen ? 11 : 12, 
                color: Colors.white70),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFoodCardsFromDocs(List<QueryDocumentSnapshot> foodDocs) {
    return foodDocs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = data['name'] ?? "Unknown Food";
      final imageUrl = data['imageUrl'] ?? data['imagePath'] ?? '';
      
      final nutrients = <NutrientTile>[
        NutrientTile(label: 'Portion', value: data['portionSize'] ?? 'N/A'),
        NutrientTile(label: 'Carbs', value: '${data['carbs'] ?? 0}g'),
        NutrientTile(label: 'Protein', value: '${data['protein'] ?? 0}g'),
        NutrientTile(label: 'Fat', value: '${data['fat'] ?? 0}g'),
        NutrientTile(label: 'Sugar', value: '${data['sugar'] ?? 0}g'),
        NutrientTile(label: 'Calories', value: '${data['calories'] ?? 0} kcal'),
      ];

      return _buildFoodCard(imageUrl, name, nutrients, data);
    }).toList();
  }

  Widget _buildFoodCard(
      String imageUrl, String foodName, List<NutrientTile> nutrients, Map<String, dynamic> data) {
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
                  ? Image.network(
                      imageUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.fastfood, color: Colors.grey, size: 30),
                      ),
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.fastfood, color: Colors.grey, size: 30),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    foodName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C6E49),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data['portionSize'] ?? 'N/A',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 30,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        NutrientTile(label: 'Carbs', value: '${data['carbs'] ?? 0}g'),
                        NutrientTile(label: 'Protein', value: '${data['protein'] ?? 0}g'),
                        NutrientTile(label: 'Fat', value: '${data['fat'] ?? 0}g'),
                        NutrientTile(label: 'Sugar', value: '${data['sugar'] ?? 0}g'),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Calories: ",
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${data['calories'] ?? 0} kcal',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$label ",
            style: const TextStyle(
              fontSize: 10,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}