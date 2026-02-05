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
      debugPrint("⚠️ Error fetching profile picture: $e");
    }
  }

  Future<void> _fetchDashboardData() async {
    if (user == null) return;
    try {
      final scansSnapshot = await _firestore
          .collection('users')
          .doc(user!.uid)
          .collection('scanned_foods')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      double totalCalories = 0;
      double totalSugar = 0;
      double totalCarbs = 0;
      List<Map<String, dynamic>> scans = [];

      for (var doc in scansSnapshot.docs) {
        final data = doc.data();
        final nutrition = data['nutrition'] ?? {};
        totalCalories += (nutrition['calories'] ?? 0).toDouble();
        totalSugar += (nutrition['sugar'] ?? 0).toDouble();
        totalCarbs += (nutrition['carbs'] ?? 0).toDouble();

        scans.add({
          'name': data['name'] ?? 'Unknown',
          'image': data['imagePath'] ?? "assets/images/default.png",
        });
      }

      setState(() {
        caloriesProgress = (totalCalories / 2000).clamp(0.0, 1.0);
        sugarProgress = (totalSugar / 50).clamp(0.0, 1.0);
        carbsProgress = (totalCarbs / 300).clamp(0.0, 1.0);
        recentScans = scans;
        weeklyGoalProgress = (scans.length / 10).clamp(0.0, 1.0);
      });
    } catch (e) {
      debugPrint("⚠️ Error fetching dashboard data: $e");
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

    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          width: 60,
                          height: 60,
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
                                        child: const Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: 35,
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    color: const Color(0xFF2C6E49),
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white,
                                      size: 35,
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
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2C6E49)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Type: $diabetesType",
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Track your health progress",
                            style: TextStyle(color: Colors.black54, fontSize: 13),
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

              const SizedBox(height: 20),

              // Nutrient Tracking
              _sectionTitle("Nutrient Tracking"),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCircleStat("Calories", caloriesProgress, Colors.orange),
                  _buildCircleStat("Sugar", sugarProgress, Colors.redAccent),
                  _buildCircleStat("Carbs", carbsProgress, Colors.blueAccent),
                ],
              ),

              const SizedBox(height: 25),

              // Goal Progress
              _sectionTitle("Goal Progress"),
              GoalProgressScreen(
                weeklyGoalProgress: weeklyGoalProgress,
                goalText:
                    "Weekly goal: ${(weeklyGoalProgress * 100).toInt()}% completed",
              ),

              const SizedBox(height: 25),

              // Recent Scans
              _sectionTitle("Recent Scans"),
              SizedBox(
                height: 130,
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
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, index) {
                          final scan = recentScans[index];
                          return _buildScanCard(scan['name'], scan['image']);
                        },
                      ),
              ),

              const SizedBox(height: 25),

              // Do & Don't Eat
              _sectionTitle("Do & Don't Eat (Diabetic)"),
              const SizedBox(height: 8),
              const Text(
                "Foods added by admin will appear here instantly! 🎉",
                style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 12),
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

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C6E49)),
      );

  Widget _buildCircleStat(String label, double value, Color color) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Text("${(value * 100).toInt()}%",
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildScanCard(String foodName, String imagePath) {
    return Container(
      width: 120,
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
                    width: 120,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 120,
                      height: 80,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.fastfood, color: Colors.grey),
                    ),
                  )
                : Image.asset(
                    imagePath,
                    width: 120,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 120,
                      height: 80,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.fastfood, color: Colors.grey),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(foodName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildDoDontCards() {
    return SizedBox(
      height: 150,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('diabetic_foods')
            .orderBy('createdAt', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
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
                  Icon(Icons.restaurant_menu, size: 50, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  const Text(
                    'No foods available yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const Text(
                    'Admin will add foods soon!',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          final doFoods = docs.where((doc) => doc['category'] == 'Do').toList();
          final dontFoods = docs.where((doc) => doc['category'] == "Don't").toList();

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
              const SizedBox(width: 12),
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
    return Container(
      width: 180,
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
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
                fontSize: 12, color: Colors.white70),
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
        NutrientTile(label: 'Calories', value: '${data['calories'] ?? 0} kcal'),
      ];

      return _buildFoodCard(imageUrl, name, nutrients);
    }).toList();
  }

  Widget _buildFoodCard(
      String imageUrl, String foodName, List<NutrientTile> nutrients) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        width: 80,
                        height: 80,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.fastfood, color: Colors.grey, size: 40),
                      ),
                    )
                  : Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.fastfood, color: Colors.grey, size: 40),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    foodName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C6E49),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...nutrients,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}