import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetechapp/Screens/landing_page.dart';
import 'package:diabetechapp/Screens/user_food_log_screen.dart';
import 'package:diabetechapp/Screens/edit_user_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  String searchQuery = "";

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LandingPage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Logout failed: $e")),
      );
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Logout"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _logout(context);
            },
            child: const Text(
              "Logout",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("users").snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No users found"));
        }

        final users = snapshot.data!.docs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          String role = data["role"] ?? "user";
          String name = (data['name'] ?? "").toString().toLowerCase();
          String email = (data['email'] ?? "").toString().toLowerCase();
          if (role == "admin") return false;
          return name.contains(searchQuery) || email.contains(searchQuery);
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: users.length,
          itemBuilder: (context, index) {
            var user = users[index];
            var data = user.data() as Map<String, dynamic>? ?? {};
            String name = data['name'] ?? "No Name";
            String email = data['email'] ?? "No Email";
            String role = data['role'] ?? "user";

            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: Icon(Icons.person, color: Colors.green.shade700),
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text("$email\nRole: $role"),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == "viewLogs") {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserFoodLogScreen(
                            userId: user.id,
                            userName: name,
                          ),
                        ),
                      );
                    } else if (value == "editUser") {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditUserScreen(
                            userId: user.id,
                            userData: data,
                          ),
                        ),
                      );
                    } else if (value == "deleteUser") {
                      FirebaseFirestore.instance
                          .collection("users")
                          .doc(user.id)
                          .delete();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("User deleted")),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: "viewLogs", child: Text("View Food Logs")),
                    const PopupMenuItem(
                        value: "editUser", child: Text("Edit User")),
                    const PopupMenuItem(
                        value: "deleteUser", child: Text("Delete User")),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFoodDataTab() {
    TextEditingController nameController = TextEditingController();
    String category = "Do";

    Future<void> addFood() async {
      if (nameController.text.isEmpty) return;

      await FirebaseFirestore.instance.collection("diabetic_foods").add({
        "name": nameController.text,
        "category": category,
        "createdAt": Timestamp.now(),
      });

      nameController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Food added successfully")),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: "Enter food name",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: category,
                items: const [
                  DropdownMenuItem(
                      value: "Do", child: Text("Do (Recommended)")),
                  DropdownMenuItem(value: "Don't", child: Text("Don't (Avoid)")),
                ],
                onChanged: (value) {
                  setState(() => category = value!);
                },
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: addFood,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Add"),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection("diabetic_foods")
                .orderBy("createdAt", descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final foods = snapshot.data!.docs;

              return ListView.builder(
                itemCount: foods.length,
                itemBuilder: (context, index) {
                  final food = foods[index];
                  final data = food.data() as Map<String, dynamic>;

                  return ListTile(
                    title: Text(data["name"] ?? ""),
                    subtitle: Text("Category: ${data["category"]}"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        FirebaseFirestore.instance
                            .collection("diabetic_foods")
                            .doc(food.id)
                            .delete();
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReportsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("food_logs").snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final logs = snapshot.data!.docs;
        int totalLogs = logs.length;

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Total Food Logs: $totalLogs",
                  style: TextStyle(
                      fontSize: 22,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("More reports coming soon...",
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboard() {
    return Padding(
      padding: const EdgeInsets.all(18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection("users").snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return _buildStatCard("Total Users", "0", Colors.green);
                    int totalUsers = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return (data['role'] ?? 'user') != 'admin';
                    }).length;
                    return _buildStatCard("Total Users", "$totalUsers", Colors.green);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection("food_logs").snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return _buildStatCard("Total Food Logs", "0", Colors.orange);
                    int totalLogs = snapshot.data!.docs.length;
                    return _buildStatCard("Total Food Logs", "$totalLogs", Colors.orange);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text("User Accounts",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800)),
          const SizedBox(height: 10),
          Expanded(child: _buildUserList()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryGreen = Colors.green.shade700;

    final List<Widget> pages = [
      _buildDashboard(),
      _buildUserList(),
      _buildFoodDataTab(),
      _buildReportsTab(),
    ];

    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        backgroundColor: primaryGreen,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: primaryGreen,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: "Users"),
          BottomNavigationBarItem(
              icon: Icon(Icons.restaurant_menu), label: "Food Data"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Reports"),
        ],
      ),
    );
  }
}
