import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../health/nutrition_calculator.dart';

class AdminDataMigrationScreen extends StatefulWidget {
  const AdminDataMigrationScreen({Key? key}) : super(key: key);

  @override
  State<AdminDataMigrationScreen> createState() =>
      _AdminDataMigrationScreenState();
}

class _AdminDataMigrationScreenState extends State<AdminDataMigrationScreen> {
  bool _isAdmin = false;
  bool _checkingAdmin = true;
  bool _isMigrating = false;
  List<Map<String, dynamic>> _foods = [];
  String _log = '';

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _checkingAdmin = false);
      return;
    }

    final adminDoc =
        await FirebaseFirestore.instance
            .collection('admins')
            .doc(user.uid)
            .get();

    setState(() {
      _isAdmin = adminDoc.exists;
      _checkingAdmin = false;
    });

    if (_isAdmin) {
      _loadFoods();
    }
  }

  Future<void> _loadFoods() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('food_rules').get();

    final foods =
        snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

    setState(() {
      _foods = foods;
      _log = '✅ Loaded ${foods.length} foods from database\n\n';

      for (var food in foods) {
        _log += '📦 ${food['name']}\n';
        _log += '   diabetesType: ${food['diabetesType']}\n';
        _log += '   category: ${food['category']}\n';
        _log += '   suitableFor: ${food['suitableFor']}\n';
        _log += '   categories: ${food['categories']}\n';
        _log += '   carbs: ${food['carbs']}g\n\n';
      }
    });
  }

  Future<void> _migrateData() async {
    setState(() {
      _isMigrating = true;
      _log = '🔄 Starting migration...\n\n';
    });

    int updated = 0;
    int skipped = 0;

    for (var food in _foods) {
      final id = food['id'];
      final name = food['name'] ?? 'Unknown';
      final carbs = (food['carbs'] ?? 0).toDouble();

      // Check if already migrated
      if (food['suitableFor'] != null && food['categories'] != null) {
        setState(() {
          _log += '⏭️  Skipped: $name (already migrated)\n';
        });
        skipped++;
        continue;
      }

      // Auto-determine suitable diabetes types
      final suitableTypes = FoodCategoryHelper.determineSuitableTypes(carbs);

      // Auto-calculate categories for each diabetes type
      final Map<String, String> categories = {};
      for (final type in ['Mild', 'Severe']) {
        categories[type] = FoodCategoryHelper.determineCategory(carbs, type);
      }

      // Auto-calculate portion sizes for each diabetes type
      final Map<String, String> portionSizes = {};
      for (final type in ['Mild', 'Severe']) {
        final grams = NutritionCalculator.recommendedGrams(
          heightCm: 160,
          weightKg: 60,
          activityLevel: 'Light',
          diabetesType: type,
          calories100g: (food['calories'] ?? 0).toDouble(),
          carbs100g: carbs,
        );
        portionSizes[type] = PortionDescriptionHelper.gramsToHumanPortion(
          grams,
          name,
        );
      }

      // Update in Firestore
      await FirebaseFirestore.instance.collection('food_rules').doc(id).update({
        'suitableFor': suitableTypes,
        'categories': categories,
        'portionSizes': portionSizes,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _log += '✅ Updated: $name\n';
        _log += '   suitableFor: $suitableTypes\n';
        _log += '   categories: $categories\n';
        _log += '   portionSizes: $portionSizes\n\n';
      });

      updated++;
    }

    setState(() {
      _isMigrating = false;
      _log += '\n🎉 Migration complete!\n';
      _log += '   Updated: $updated foods\n';
      _log += '   Skipped: $skipped foods\n';
    });

    // Reload foods
    await _loadFoods();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAdmin) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(child: Text('Admin access required')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Migration Tool'),
        backgroundColor: const Color(0xFF2C6E49),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Database Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Total foods: ${_foods.length}'),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isMigrating ? null : _migrateData,
                        icon:
                            _isMigrating
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(Icons.sync),
                        label: Text(
                          _isMigrating
                              ? 'Migrating...'
                              : 'Migrate Old Data to New Structure',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2C6E49),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Migration Log:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _log.isEmpty ? 'No logs yet...' : _log,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
