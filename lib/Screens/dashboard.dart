import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diabetechapp/Screens/edit_profile.dart';
import 'package:diabetechapp/Screens/foodscanner.dart';
import 'package:diabetechapp/Screens/log_in.dart';
import 'package:diabetechapp/health/meal.dart';
import 'package:diabetechapp/health/nutrient_summary.dart';
import 'package:diabetechapp/health/goal_progress.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({Key? key}) : super(key: key);

  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  User? user;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
  }

  void reloadUser() {
    setState(() {
      user = FirebaseAuth.instance.currentUser;
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
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Logout"),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
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

    String name = user?.displayName ?? "User";

    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔹 Header Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Hello, $name 👋",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C6E49),
                        ),
                      ),
                      const Text(
                        "Track your diabetic health progress",
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _buildSquareButton(
                        icon: Icons.person,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const EditProfileScreen()),
                          ).then((_) => reloadUser());
                        },
                      ),
                      const SizedBox(width: 10),
                      _buildSquareButton(
                        icon: Icons.logout,
                        onPressed: _confirmLogout,
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 🔹 Nutrient Summary Section
              _sectionTitle("Nutrient Tracking"),
              _buildNutrientRow(),

              const SizedBox(height: 25),

              // 🔹 Goal Progress Section
              _sectionTitle("Goal Progress"),
              _buildProgressCard(),

              const SizedBox(height: 25),

              // 🔹 Recent Scans Section
              _sectionTitle("Recent Scans"),
              _buildRecentScans(),

              const SizedBox(height: 25),

              // 🔹 Do & Don’t Eat Section
              _sectionTitle("Do & Don't Eat (Diabetic)"),
              _buildDoDontCards(),
            ],
          ),
        ),
      ),

      // 🔹 Bottom Navigation
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF2C6E49),
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        onTap: (index) {
          setState(() => _currentIndex = index);

          if (index == 0) {
            // Home
          } else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FoodScannerScreen()),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MealLogScreen()),
            );
          } else if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NutrientSummaryScreen()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ""),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: ""),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: ""),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: ""),
        ],
      ),
    );
  }

  // 🔸 Helper Widgets
  Widget _buildSquareButton({required IconData icon, required VoidCallback onPressed}) {
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
              color: Colors.teal.withOpacity(0.3),
              blurRadius: 5,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C6E49)),
      );

  Widget _buildNutrientRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildCircleStat("Calories", 0.7, Colors.orange),
        _buildCircleStat("Sugar", 0.4, Colors.redAccent),
        _buildCircleStat("Carbs", 0.6, Colors.blueAccent),
      ],
    );
  }

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
            Text("${(value * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildProgressCard() {
    return Card(
      color: Colors.teal.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: const ListTile(
        leading: Icon(Icons.flag, color: Colors.teal),
        title: Text("Weekly goal: 80% completed"),
        subtitle: Text("Keep going! You’re doing great."),
      ),
    );
  }

  Widget _buildRecentScans() {
    return SizedBox(
      height: 120,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildScanCard("Apple", "Healthy choice", Colors.green.shade300),
          const SizedBox(width: 12),
          _buildScanCard("Coke", "Avoid high sugar", Colors.red.shade300),
          const SizedBox(width: 12),
          _buildScanCard("Brown Rice", "Good for diabetics", Colors.orange.shade300),
        ],
      ),
    );
  }

  Widget _buildScanCard(String title, String subtitle, Color color) {
    return Container(
      width: 150,
      decoration: BoxDecoration(
        color: color.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildDoDontCards() {
    return SizedBox(
      height: 130,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildDoDontCard("✅ Eat", ["Avocado", "Fish", "Whole Grains"], Colors.green.shade300),
          const SizedBox(width: 12),
          _buildDoDontCard("🚫 Avoid", ["Soda", "White Rice", "Candy"], Colors.red.shade300),
        ],
      ),
    );
  }

  // 🔸 Updated: Do & Don't items clickable
  Widget _buildDoDontCard(String title, List<String> items, Color color) {
    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: color.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (var item in items)
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("You tapped on $item")),
                );
                // You can add navigation to detail page here
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text("• $item", style: const TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}
