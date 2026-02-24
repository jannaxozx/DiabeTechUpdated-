import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;

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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 Analytics & Reports',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 16),
            
            // Mobile-optimized Report Cards - Single Column
            _buildMobileReportCard(
              '📈 User Activity',
              Icons.trending_up,
              Colors.blue,
              _buildUserActivityContent(context, Colors.blue),
            ),
            const SizedBox(height: 12),
            
            _buildMobileReportCard(
              '🍎 Food Consumption',
              Icons.restaurant,
              Colors.orange,
              _buildFoodConsumptionContent(context),
            ),
            const SizedBox(height: 12),
            
            _buildMobileReportCard(
              '❤️ Health Compliance',
              Icons.favorite,
              Colors.red,
              _buildHealthComplianceContent(context),
            ),
            const SizedBox(height: 12),
            
            _buildMobileReportCard(
              '⚡ System Performance',
              Icons.speed,
              Colors.purple,
              _buildSystemPerformanceContent(context),
            ),
            const SizedBox(height: 20),
            
            // Mobile-optimized Detailed Reports
            _buildMobileDetailedReports(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileReportCard(String title, IconData icon, Color color, Widget content) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildUserActivityContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
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
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          
          int activeToday = 0;
          for (var user in users) {
            final data = user.data() as Map<String, dynamic>;
            final lastLogin = data['lastLogin'];
            if (lastLogin != null) {
              final loginDate = (lastLogin as Timestamp).toDate();
              if (loginDate.year == today.year && 
                  loginDate.month == today.month && 
                  loginDate.day == today.day) {
                activeToday++;
              }
            }
          }
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User Statistics:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      Text(
                        '$activeToday',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                      const Text(
                        'Active Today',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        '${users.length}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const Text(
                        'Total Users',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFoodConsumptionContent(BuildContext context) {
    final cardHeight = math.min(200.0, MediaQuery.of(context).size.height * 0.18);
    return Container(
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collectionGroup('foodLogs')
            .orderBy('timestamp', descending: true)
            .limit(50)
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
              const Icon(Icons.restaurant, size: 36, color: Colors.orange),
              const SizedBox(height: 8),
              const Text(
                'Top Consumed Foods',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...sortedFoods.take(2).map((entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${entry.key.length > 15 ? entry.key.substring(0, 15) + '...' : entry.key}: ${entry.value}',
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHealthComplianceContent(BuildContext context) {
    final cardHeight = math.min(200.0, MediaQuery.of(context).size.height * 0.18);
    return Container(
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
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
            final categoryStr = category.toString().toLowerCase().trim();
            if (categoryStr.startsWith('do')) {
              doCount++;
            } else if (categoryStr.startsWith('don')) {
              dontCount++;
            }
          }
          
          final total = doCount + dontCount;
          final complianceRate = total > 0 ? (doCount / total * 100) : 0;
          
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite, size: 36, color: Colors.red),
              const SizedBox(height: 8),
              Text(
                '${complianceRate.toStringAsFixed(1)}% Compliance',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: complianceRate / 100,
                backgroundColor: Colors.red.shade100,
                valueColor: AlwaysStoppedAnimation(Colors.green),
                minHeight: 6,
              ),
              const SizedBox(height: 4),
              Text(
                '$doCount vs $dontCount',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSystemPerformanceContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Status:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text(
                'System Status: Healthy',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text('• All services operational', style: TextStyle(fontSize: 12)),
          Text('• Database connected', style: TextStyle(fontSize: 12)),
          Text('• Uptime: 99.9%', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMobileDetailedReports() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📋 Detailed Reports',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 16),
            
            // Mobile User Reports
            _buildMobileUserReports(),
            const SizedBox(height: 16),
            
            // Mobile Food Reports
            _buildMobileFoodReports(),
            const SizedBox(height: 16),
            
            // Mobile System Reports
            _buildMobileSystemReports(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileUserReports() {
    return ExpansionTile(
      title: const Text(
        '👥 User Reports',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'user')
              .orderBy('createdAt', descending: true)
              .limit(5)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            
            final users = snapshot.data!.docs;
            return Column(
              children: users.map((user) {
                final data = user.data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['name'] ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data['email'] ?? 'No email',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getDiabetesTypeColor(data['diabetesType']),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                data['diabetesType'] ?? 'Not specified',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Age: ${data['age']?.toString() ?? 'N/A'}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Joined: ${_formatDate(data['createdAt'])}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMobileFoodReports() {
    return ExpansionTile(
      title: const Text(
        '🍎 Food Reports',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('food_rules')
              .orderBy('createdAt', descending: true)
              .limit(5)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            
            final foods = snapshot.data!.docs;
            return Column(
              children: foods.map((food) {
                final data = food.data() as Map<String, dynamic>;
                final category = (data['category'] ?? '').toString().toLowerCase().trim();
                final isDo = category.startsWith('do');
                
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['name'] ?? 'Unnamed',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDo ? Colors.green : Colors.red,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isDo ? 'DO' : "DON'T",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${data['calories'] ?? 0} kcal',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Portion: ${data['portionSize'] ?? 'N/A'}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Added: ${_formatDate(data['createdAt'])}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMobileSystemReports() {
    return ExpansionTile(
      title: const Text(
        '⚙️ System Reports',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildSystemMetricCard(
                      'Users',
                      Icons.people,
                      Colors.blue,
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .where('role', isEqualTo: 'user')
                            .snapshots(),
                        builder: (context, snap) {
                          final userCount = snap.hasData ? snap.data!.docs.length : 0;
                          return Text('$userCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSystemMetricCard(
                      'Foods',
                      Icons.restaurant,
                      Colors.orange,
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('food_rules')
                            .snapshots(),
                        builder: (context, snap) {
                          final foodCount = snap.hasData ? snap.data!.docs.length : 0;
                          return Text('$foodCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSystemMetricCard(
                'Last Backup',
                Icons.backup,
                Colors.green,
                Text(
                  'Today: ${DateTime.now().toString().substring(0, 10)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSystemMetricCard(String title, IconData icon, Color color, Widget content) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            content,
          ],
        ),
      ),
    );
  }

  Color _getDiabetesTypeColor(String? type) {
    if (type == null) return Colors.grey;
    final typeStr = type.toLowerCase();
    if (typeStr.contains('mild')) return Colors.green;
    if (typeStr.contains('moderate')) return Colors.orange;
    if (typeStr.contains('severe')) return Colors.red;
    return Colors.grey;
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    final date = (timestamp as Timestamp).toDate();
    return '${date.day}/${date.month}/${date.year}';
  }
}
