import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diabetechapp/Screens/edit_profile.dart';
import 'package:diabetechapp/Screens/foodscanner.dart';
import 'package:diabetechapp/Screens/log_in.dart';
import 'package:diabetechapp/health/healthtips.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({Key? key}) : super(key: key);

  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  User? user;

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

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('No user is logged in. Please log in.'),
        ),
      );
    }

    String name = user?.displayName ?? 'User';
    String email = user?.email ?? 'No email available';

    return Scaffold(
      appBar: AppBar(
        title: const Text('DiabeTech Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EditProfileScreen()),
              ).then((_) => reloadUser());
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logged out successfully')),
              );
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const Login_Screen()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/dash.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ListView(
              children: [
                Text(
                  "Welcome, $name",
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
                buildProfileCard(name, email),
                const SizedBox(height: 30),
                buildFoodScannerCard(),
                const SizedBox(height: 30),
                buildDailyNutrientCard(),
                buildMealHistoryCard(),
                buildProgressTrackingCard(),
                buildHealthTipsCard(),
                const Text(
                  "More features coming soon...",
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildProfileCard(String name, String email) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          radius: 30,
          backgroundImage: NetworkImage(user?.photoURL ?? 'https://via.placeholder.com/150'),
        ),
        title: Text(name),
        subtitle: Text(email),
      ),
    );
  }

  Widget buildFoodScannerCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const FoodScannerScreen()));
        },
        leading: const Icon(Icons.camera_alt, size: 40, color: Colors.teal),
        title: const Text(
          "Scan Your Meal",
          style: TextStyle(color: Colors.teal),
        ),
        subtitle: const Text("Tap to open the camera and scan your food."),
        trailing: const Icon(Icons.arrow_forward_ios),
      ),
    );
  }

  Widget buildDailyNutrientCard() {
    return buildSection(
      title: "Daily Nutrient Summary",
      icon: Icons.restaurant_menu,
      iconColor: Colors.teal,
      cardTitle: "Calories: 1340 kcal",
      cardSubtitle: "Carbs: 120g | Protein: 75g | Fats: 50g",
      titleColor: Colors.teal,
      subtitleColor: Colors.black,
    );
  }

  Widget buildMealHistoryCard() {
    return buildSection(
      title: "Meal Log History",
      icon: Icons.fastfood,
      iconColor: Colors.teal,
      cardTitle: "Chicken Salad",
      cardSubtitle: "Logged on: 2025-04-23",
      titleColor: Colors.teal,
      subtitleColor: Colors.black,
    );
  }

  Widget buildProgressTrackingCard() {
    return buildSection(
      title: "Progress Tracking",
      icon: Icons.show_chart,
      iconColor: Colors.teal,
      cardTitle: "Goal Progress",
      cardSubtitle: "Calories: 1340 / 2000 kcal",
      titleColor: Colors.teal,
      subtitleColor: Colors.black,
    );
  }

  Widget buildHealthTipsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "FOOD TIPS",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 4,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: ListTile(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HealthTipsScreen()),
              );
            },
            leading: const Icon(Icons.notifications, size: 40, color: Colors.teal),
            title: const Text(
              "DO AND DON'T",
              style: TextStyle(color: Colors.teal),
            ),
            subtitle: const Text(
              "Do and Don't foods are important for managing diabetes.",
              style: TextStyle(color: Colors.black),
            ),
            trailing: const Icon(Icons.arrow_forward_ios),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget buildSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String cardTitle,
    required String cardSubtitle,
    Color titleColor = Colors.white,
    Color subtitleColor = Colors.grey,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 4,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: ListTile(
            leading: Icon(icon, size: 40, color: iconColor),
            title: Text(
              cardTitle,
              style: TextStyle(color: titleColor),
            ),
            subtitle: Text(
              cardSubtitle,
              style: TextStyle(color: subtitleColor),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
