import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  final String userId;
  final String userName;

  const AppDrawer({super.key, required this.userId, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(userName),
            accountEmail: Text(userId), // change to email if you have it
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: Colors.purple),
            ),
            decoration: const BoxDecoration(
              color: Colors.purple,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pushReplacementNamed(context, '/dashboard');
            },
          ),
          ListTile(
            leading: const Icon(Icons.fastfood),
            title: const Text('Food Logs'),
            onTap: () {
              Navigator.pushReplacementNamed(
                context,
                '/food_logs',
                arguments: {"userId": userId, "userName": userName},
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.analytics),
            title: const Text('Nutrition Summary'),
            onTap: () {
              Navigator.pushReplacementNamed(context, '/nutrition_summary');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout'),
            onTap: () {
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
    );
  }
}
