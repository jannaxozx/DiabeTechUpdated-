import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_food_detail_screen.dart';

class AdminFoodRulesScreen extends StatefulWidget {
  const AdminFoodRulesScreen({Key? key}) : super(key: key);

  @override
  State<AdminFoodRulesScreen> createState() => _AdminFoodRulesScreenState();
}

class _AdminFoodRulesScreenState extends State<AdminFoodRulesScreen> {
  final _name = TextEditingController();
  final _portion = TextEditingController();
  final _calories = TextEditingController();
  final _carbs = TextEditingController();
  final _protein = TextEditingController();
  final _fat = TextEditingController();

  String _category = 'do';
  String _selectedDiabetesType = 'Mild'; // Add diabetes type selection
  bool _saving = false;

  Future<void> _addFood() async {
    if (_name.text.trim().isEmpty) return;

    setState(() => _saving = true);

    try {
      await FirebaseFirestore.instance
          .collection('food_rules')
          .doc(_name.text.trim().toLowerCase())
          .set({
        'name': _name.text.trim().toLowerCase(),
        'portionSize': _portion.text.trim(),
        'calories': int.tryParse(_calories.text) ?? 0,
        'carbs': int.tryParse(_carbs.text) ?? 0,
        'protein': int.tryParse(_protein.text) ?? 0,
        'fat': int.tryParse(_fat.text) ?? 0,
        'category': _category,
        'diabetesType': _selectedDiabetesType, // Add diabetes type
        'createdAt': FieldValue.serverTimestamp(),
      });

      _name.clear();
      _portion.clear();
      _calories.clear();
      _carbs.clear();
      _protein.clear();
      _fat.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Food added successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }

    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Image upload placeholder (you can add image upload logic here)
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 2),
                borderRadius: BorderRadius.circular(12),
                color: Colors.green.shade50,
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate, size: 60, color: Colors.green),
                  SizedBox(height: 8),
                  Text('Tap to add image (optional)',
                      style: TextStyle(color: Colors.green)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Input fields
            _input(_name, 'Food Name'),
            _input(_portion, 'Portion Size'),
            _input(_calories, 'Calories', number: true),
            _input(_carbs, 'Carbs (g)', number: true),
            _input(_protein, 'Protein (g)', number: true),
            _input(_fat, 'Fat (g)', number: true),

            const SizedBox(height: 10),

            // Category dropdown
            DropdownButtonFormField<String>(
              value: _category,
              items: const [
                DropdownMenuItem(value: 'do', child: Text('✅ Do (Recommended)')),
                DropdownMenuItem(value: 'dont', child: Text("❌ Don't")),
              ],
              onChanged: (v) => setState(() => _category = v!),
              decoration: InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
            ),

            const SizedBox(height: 10),

            // Diabetes Type dropdown
            DropdownButtonFormField<String>(
              value: _selectedDiabetesType,
              items: const [
                DropdownMenuItem(value: 'Mild', child: Text('🟢 Mild')),
                DropdownMenuItem(value: 'Moderate', child: Text('🟡 Moderate')),
                DropdownMenuItem(value: 'Severe', child: Text('🔴 Severe')),
              ],
              onChanged: (v) => setState(() => _selectedDiabetesType = v!),
              decoration: InputDecoration(
                labelText: 'Diabetes Type',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
            ),

            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _name.clear();
                      _portion.clear();
                      _calories.clear();
                      _carbs.clear();
                      _protein.clear();
                      _fat.clear();
                    },
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear Form'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _addFood,
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.add),
                    label: const Text('Add Food'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),
            const Divider(thickness: 2),
            const SizedBox(height: 10),

            // Manage Foods Header
            const Text(
              'Manage Foods',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 15),

            // Food List
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('food_rules')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No foods added yet.'),
                  );
                }

                return Column(
                  children: snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final category = data['category'] ?? 'do';
                    final categoryText = category == 'do' ? 'Do' : "Don't";
                    final foodName = (data['name'] ?? 'Unknown').toString();
                    final diabetesType = data['diabetesType'] ?? 'Mild';

                    // Get color for diabetes type
                    Color diabetesTypeColor = Colors.green;
                    String diabetesTypeIcon = '🟢';
                    if (diabetesType == 'Moderate') {
                      diabetesTypeColor = Colors.orange;
                      diabetesTypeIcon = '🟡';
                    } else if (diabetesType == 'Severe') {
                      diabetesTypeColor = Colors.red;
                      diabetesTypeIcon = '🔴';
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () {
                          print('🔍 Clicked on food: ${doc.id}');
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AdminFoodDetailScreen(
                                foodId: doc.id,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              // Food Icon/Image placeholder
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.restaurant,
                                  color: Colors.green,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 15),

                              // Food details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      foodName.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          categoryText,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: category == 'do'
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: diabetesTypeColor.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '$diabetesTypeIcon $diabetesType',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: diabetesTypeColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Arrow icon
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController c, String label, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          prefixIcon: _getIcon(label),
        ),
      ),
    );
  }

  Icon? _getIcon(String label) {
    if (label.contains('Food Name')) return const Icon(Icons.restaurant_menu);
    if (label.contains('Portion')) return const Icon(Icons.straighten);
    if (label.contains('Calories')) return const Icon(Icons.local_fire_department);
    if (label.contains('Carbs')) return const Icon(Icons.grain);
    if (label.contains('Protein')) return const Icon(Icons.fitness_center);
    if (label.contains('Fat')) return const Icon(Icons.water_drop);
    return null;
  }
}