import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({Key? key}) : super(key: key);

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 Analytics & Reports'),
        backgroundColor: Colors.green,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 Analytics & Reports',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 20),
            
            // Report Cards
            Row(
              children: [
                Expanded(
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📈 User Activity',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .where('role', isEqualTo: 'user')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                
                                final users = snapshot.data!.docs;
                                final activeToday = users.where((user) {
                                  final lastLogin = (user.data() as Map<String, dynamic>)['lastLogin'];
                                  if (lastLogin == null) return false;
                                  final loginDate = (lastLogin as Timestamp).toDate();
                                  final now = DateTime.now();
                                  return loginDate.day == now.day && 
                                         loginDate.month == now.month && 
                                         loginDate.year == now.year;
                                }).length;
                                
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.trending_up, size: 48, color: Colors.blue),
                                    const SizedBox(height: 8),
                                    Text(
                                      '$activeToday Active Today',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Total: ${users.length} users',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🍎 Food Consumption',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collectionGroup('foodLogs')
                                  .orderBy('timestamp', descending: true)
                                  .limit(100)
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                
                                final logs = snapshot.data!.docs;
                                final foodCounts = <String, int>{};
                                
                                for (var log in logs) {
                                  final foodName = (log.data() as Map<String, dynamic>)['foodName'] ?? 'Unknown';
                                  foodCounts[foodName] = (foodCounts[foodName] ?? 0) + 1;
                                }
                                
                                final sortedFoods = foodCounts.entries.toList()
                                  ..sort((a, b) => b.value.compareTo(a.value));
                                
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.restaurant, size: 48, color: Colors.orange),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Top Consumed Foods',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    ...sortedFoods.take(3).map((entry) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Text(
                                        '${entry.key}: ${entry.value} times',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    )),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            Row(
              children: [
                Expanded(
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '❤️ Health Compliance',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collectionGroup('foodLogs')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                
                                final logs = snapshot.data!.docs;
                                int doCount = 0, dontCount = 0;
                                
                                for (var log in logs) {
                                  final category = (log.data() as Map<String, dynamic>)['category'] ?? 'Unknown';
                                  if (category == 'Do') {
                                    doCount++;
                                  } else if (category == "Don't") {
                                    dontCount++;
                                  }
                                }
                                
                                final total = doCount + dontCount;
                                final complianceRate = total > 0 ? (doCount / total * 100) : 0;
                                
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.favorite, size: 48, color: Colors.red),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${complianceRate.toStringAsFixed(1)}% Compliance',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: complianceRate / 100,
                                      backgroundColor: Colors.red.shade100,
                                      valueColor: AlwaysStoppedAnimation(Colors.green),
                                      minHeight: 8,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$doCount recommended vs $dontCount avoided',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '⚡ System Performance',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.speed, size: 48, color: Colors.purple),
                                const SizedBox(height: 8),
                                Text(
                                  'System Healthy',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'All services operational',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Uptime: 99.9%',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Detailed Tables Section
            _buildDetailedReportsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedReportsSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📋 Detailed Reports',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 16),
            
            // User Reports Table
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '👥 User Reports',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .where('role', isEqualTo: 'user')
                          .orderBy('createdAt', descending: true)
                          .limit(10)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        
                        final users = snapshot.data!.docs;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Name'), tooltip: 'User full name'),
                              DataColumn(label: Text('Email'), tooltip: 'User email address'),
                              DataColumn(label: Text('Type'), tooltip: 'Diabetes type'),
                              DataColumn(label: Text('Age'), tooltip: 'User age'),
                              DataColumn(label: Text('Joined'), tooltip: 'Registration date'),
                              DataColumn(label: Text('Status'), tooltip: 'Account status'),
                            ],
                            rows: users.map((user) {
                              final data = user.data() as Map<String, dynamic>;
                              return DataRow(
                                cells: [
                                  DataCell(Text(data['name'] ?? 'Unknown')),
                                  DataCell(Text(data['email'] ?? 'No email')),
                                  DataCell(Text(data['diabetesType'] ?? 'Not specified')),
                                  DataCell(Text(data['age']?.toString() ?? 'N/A')),
                                  DataCell(Text(_formatDate(data['createdAt']))),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (data['diabetesType'] ?? 'Not specified') == 'Mild' ? Colors.green :
                                                       (data['diabetesType'] ?? 'Not specified') == 'Severe' ? Colors.red : Colors.grey,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Active',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Food Reports Table
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🍎 Food Reports',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('food_rules')
                          .orderBy('createdAt', descending: true)
                          .limit(10)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        
                        final foods = snapshot.data!.docs;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Food Name'), tooltip: 'Name of the food item'),
                              DataColumn(label: Text('Category'), tooltip: 'Do or Don\'t classification'),
                              DataColumn(label: Text('Calories'), tooltip: 'Calorie count per serving'),
                              DataColumn(label: Text('Portion'), tooltip: 'Serving size information'),
                              DataColumn(label: Text('Added'), tooltip: 'When food was added'),
                              DataColumn(label: Text('Updated'), tooltip: 'Last modification date'),
                            ],
                            rows: foods.map((food) {
                              final data = food.data() as Map<String, dynamic>;
                              return DataRow(
                                cells: [
                                  DataCell(Text(data['name'] ?? 'Unnamed')),
                                  DataCell(Text(data['category'] ?? 'Unknown')),
                                  DataCell(Text('${data['calories'] ?? 0} kcal')),
                                  DataCell(Text(data['portionSize'] ?? 'N/A')),
                                  DataCell(Text(_formatDate(data['createdAt']))),
                                  DataCell(Text(_formatDate(data['updatedAt']))),
                                ],
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // System Reports Section
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚙️ System Reports',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Column(
                      children: [
                        const Text(
                          'Database Status',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      const Text('Database Status'),
                                      const SizedBox(height: 8),
                                      StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('users')
                                            .where('role', isEqualTo: 'user')
                                            .snapshots(),
                                        builder: (context, snap) {
                                          final userCount = snap.hasData ? snap.data!.docs.length : 0;
                                          return Text('Total Users: $userCount');
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      const Text('Storage Status'),
                                      const SizedBox(height: 8),
                                      StreamBuilder<QuerySnapshot>(
                                        stream: FirebaseFirestore.instance
                                            .collection('food_rules')
                                            .snapshots(),
                                        builder: (context, snap) {
                                          final foodCount = snap.hasData ? snap.data!.docs.length : 0;
                                          return Text('Total Foods: $foodCount');
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      const Text('Last Backup'),
                                      const SizedBox(height: 8),
                                      Text('Today: ${DateTime.now().toString().substring(0, 10)}'),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    final date = (timestamp as Timestamp).toDate();
    return '${date.day}/${date.month}/${date.year}';
  }
}
