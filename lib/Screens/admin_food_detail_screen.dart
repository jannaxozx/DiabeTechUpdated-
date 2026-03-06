import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Detail screen for a single food
class AdminFoodDetailScreen extends StatefulWidget {
  final String foodId;

  const AdminFoodDetailScreen({Key? key, required this.foodId})
      : super(key: key);

  @override
  State<AdminFoodDetailScreen> createState() => _AdminFoodDetailScreenState();
}

class _AdminFoodDetailScreenState extends State<AdminFoodDetailScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Details'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete Food',
            onPressed: () => _deleteFood(context),
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('food_rules')
            .doc(widget.foodId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 20),
                  const Text('Food not found'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final category = (data['category'] ?? '').toString().toLowerCase().trim();
          final isRecommended = category.startsWith('do');
          final imageUrl = (data['imageUrl'] ?? data['imagePath'] ?? '') as String;
          final diabetesType = (data['diabetesType'] ?? 'Mild').toString();

          // Get color and icon for diabetes type
          Color diabetesTypeColor = Colors.green;
          String diabetesTypeIcon = '🟢';
          if (diabetesType == 'Severe') {
            diabetesTypeColor = Colors.red;
            diabetesTypeIcon = '🔴';
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                // Header with category badge
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: isRecommended ? Colors.green.shade50 : Colors.red.shade50,
                  ),
                  child: Column(
                    children: [
                      // Food image or icon
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: isRecommended ? Colors.green : Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: imageUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(60),
                                child: Image.network(
                                  imageUrl,
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.restaurant,
                                    size: 60,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.restaurant,
                                size: 60,
                                color: Colors.white,
                              ),
                      ),
                      const SizedBox(height: 15),

                      // Food name
                      Text(
                        (data['name'] ?? 'Unknown').toString().toUpperCase(),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),

                      // Category chip
                      Chip(
                        label: Text(
                          isRecommended
                              ? '✅ Do (Recommended)'
                              : "❌ Don't (Avoid)",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        backgroundColor:
                            isRecommended ? Colors.green.shade100 : Colors.red.shade100,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      const SizedBox(height: 8),

                      // Diabetes Type chip
                      Chip(
                        label: Text(
                          '$diabetesTypeIcon $diabetesType Diabetes',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        backgroundColor: diabetesTypeColor.withOpacity(0.2),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Nutritional Information
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nutritional Information',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),

                      _detailCard(
                        'Portion Size',
                        data['portionSize'] ?? 'N/A',
                        Icons.straighten,
                        Colors.blue,
                      ),
                      _detailCard(
                        'Calories',
                        '${data['calories'] ?? 0} kcal',
                        Icons.local_fire_department,
                        Colors.orange,
                      ),
                      _detailCard(
                        'Carbohydrates',
                        '${data['carbs'] ?? 0} g',
                        Icons.grain,
                        Colors.brown,
                      ),
                      _detailCard(
                        'Protein',
                        '${data['protein'] ?? 0} g',
                        Icons.fitness_center,
                        Colors.red,
                      ),
                      _detailCard(
                        'Fat',
                        '${data['fat'] ?? 0} g',
                        Icons.water_drop,
                        Colors.yellow.shade700,
                      ),

                      const SizedBox(height: 20),

                      // Summary card
                      Card(
                        color: Colors.blue.shade50,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.summarize, color: Colors.blue),
                                  SizedBox(width: 10),
                                  Text(
                                    'Nutritional Summary',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              _summaryRow(
                                'Total Macros',
                                '${(data['carbs'] ?? 0) + (data['protein'] ?? 0) + (data['fat'] ?? 0)}g',
                              ),
                              _summaryRow(
                                'Category',
                                isRecommended ? 'Recommended' : 'Avoid',
                              ),
                              _summaryRow(
                                'Calories per 100g',
                                '${data['calories'] ?? 0} kcal',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// --- Helper Widgets ---
  Widget _detailCard(String label, String value, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// --- Delete Food Function ---
  Future<void> _deleteFood(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Food?'),
        content: const Text(
          'Are you sure you want to delete this food item? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('food_rules')
            .doc(widget.foodId)
            .delete();

        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Food deleted successfully')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting food: $e')),
          );
        }
      }
    }
  }
}