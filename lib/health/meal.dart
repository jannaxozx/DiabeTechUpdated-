import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MealLogScreen extends StatelessWidget {
  const MealLogScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('You must be logged in to view this page')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meal Log and Scanned Food History')),
      body: Container(
        // Adding the background image here
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/wood.png'),
                fit: BoxFit.cover,
              ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('scanned_foods')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('No scanned food logs found.'));
            }

            final foodLogs = snapshot.data!.docs;

            return ListView.builder(
              itemCount: foodLogs.length,
              itemBuilder: (context, index) {
                final data = foodLogs[index].data() as Map<String, dynamic>;
                final name = data['name'] ?? 'Unknown';
                final nutrition = data['nutrition'] ?? {};
                final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.restaurant_menu, color: Colors.teal),
                    title: Text(name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (nutrition['calories'] != null)
                          Text('Calories: ${nutrition['calories']} kcal'),
                        if (nutrition['carbs'] != null)
                          Text('Carbs: ${nutrition['carbs']}g'),
                        if (nutrition['protein'] != null)
                          Text('Protein: ${nutrition['protein']}g'),
                        if (nutrition['fat'] != null)
                          Text('Fat: ${nutrition['fat']}g'),
                        if (timestamp != null)
                          Text('Date: ${timestamp.toLocal().toString().split(' ')[0]}'),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
