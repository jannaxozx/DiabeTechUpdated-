import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:diabetechapp/Screens/edit_profile.dart';
import 'package:diabetechapp/Screens/foodscanner.dart';
import 'package:diabetechapp/Screens/log_in.dart';

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
            // Navigate to login screen after sign out
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const Login_Screen()), // Assuming you have a LoginScreen widget
            );
          },
        ),

        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            Text("Welcome, $name", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 30),
            buildProfileCard(name, email),
            const SizedBox(height: 30),
            buildDailyNutrientCard(),
            buildMealHistoryCard(),
            buildProgressTrackingCard(),
            buildHealthTipsCard(),
            const Text("More features coming soon...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const FoodScannerScreen()));
        },
        child: const Icon(Icons.camera_alt),
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

  Widget buildDailyNutrientCard() {
    return buildSection(
      title: "Daily Nutrient Summary",
      icon: Icons.restaurant_menu,
      iconColor: Colors.teal,
      cardTitle: "Calories: 1340 kcal",
      cardSubtitle: "Carbs: 120g | Protein: 75g | Fats: 50g",
    );
  }

  Widget buildMealHistoryCard() {
    return buildSection(
      title: "Meal Log History",
      icon: Icons.fastfood,
      iconColor: Colors.teal,
      cardTitle: "Chicken Salad",
      cardSubtitle: "Logged on: 2025-04-23",
    );
  }

  Widget buildProgressTrackingCard() {
    return buildSection(
      title: "Progress Tracking",
      icon: Icons.show_chart,
      iconColor: Colors.teal,
      cardTitle: "Goal Progress",
      cardSubtitle: "Calories: 1340 / 2000 kcal",
    );
  }

  Widget buildHealthTipsCard() {
    return buildSection(
      title: "Health Tips",
      icon: Icons.notifications,
      iconColor: Colors.teal,
      cardTitle: "Drink more water!",
      cardSubtitle: "Staying hydrated is important for managing diabetes.",
    );
  }

  Widget buildSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String cardTitle,
    required String cardSubtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          elevation: 4,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: ListTile(
            leading: Icon(icon, size: 40, color: iconColor),
            title: Text(cardTitle),
            subtitle: Text(cardSubtitle),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
