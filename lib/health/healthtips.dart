import 'package:flutter/material.dart';

class HealthTipsScreen extends StatelessWidget {
  const HealthTipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FOOD TIPS'),
        backgroundColor: const Color.fromARGB(255, 167, 255, 167),
      ),
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/images/wood.png', // Your background image
              fit: BoxFit.cover,
            ),
          ),
          // Scrollable Content
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/images/health.png',
                    height: 230,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Eat balanced meals, and monitor your sugar intake regularly. '
                  'Include fiber-rich foods and exercise daily to manage diabetes effectively.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 30),

                const Text(
                  'FOOD BREAKDOWN',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),

                const Text(
                  '✅ DO',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.green),
                ),
                const SizedBox(height: 10),

                _buildFoodCard(
                  imagePath: 'assets/images/apple.png',
                  foodName: 'APPLE',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '13.8g'),
                    NutrientTile(label: 'Fats', value: '0.2g'),
                    NutrientTile(label: 'Proteins', value: '0.3g'),
                    NutrientTile(label: 'Calories', value: '52 kcal'),
                    NutrientTile(label: 'Sugar', value: '10.4g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/BREAST.PNG',
                  foodName: 'CHICKEN',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '0g'),
                    NutrientTile(label: 'Fats', value: '2.6g'),
                    NutrientTile(label: 'Proteins', value: '22.5g'),
                    NutrientTile(label: 'Calories', value: '120 kcal'),
                    NutrientTile(label: 'Sugar', value: '0g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/TILAPIA.png',
                  foodName: 'TILAPIA',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '0g'),
                    NutrientTile(label: 'Fats', value: '1.7g'),
                    NutrientTile(label: 'Proteins', value: '20g'),
                    NutrientTile(label: 'Calories', value: '96 kcal'),
                    NutrientTile(label: 'Sugar', value: '0g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/TOFU.PNG',
                  foodName: 'FIRM TOFU',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '3.9g'),
                    NutrientTile(label: 'Fats', value: '8g'),
                    NutrientTile(label: 'Proteins', value: '15.5g'),
                    NutrientTile(label: 'Calories', value: '144 kcal'),
                    NutrientTile(label: 'Sugar', value: '0.6g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/SHRIMP.PNG',
                  foodName: 'SHRIMP',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '0.2g'),
                    NutrientTile(label: 'Fats', value: '0.3g'),
                    NutrientTile(label: 'Proteins', value: '24g'),
                    NutrientTile(label: 'Calories', value: '99 kcal'),
                    NutrientTile(label: 'Sugar', value: '0g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/BEEF.PNG',
                  foodName: 'BEEF',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '0g'),
                    NutrientTile(label: 'Fats', value: '6g'),
                    NutrientTile(label: 'Proteins', value: '21g'),
                    NutrientTile(label: 'Calories', value: '150 kcal'),
                    NutrientTile(label: 'Sugar', value: '0g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/PAPAYA.png',
                  foodName: 'PAPAYA',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '10.8g'),
                    NutrientTile(label: 'Fats', value: '0.3g'),
                    NutrientTile(label: 'Proteins', value: '0.5g'),
                    NutrientTile(label: 'Calories', value: '43 kcal'),
                    NutrientTile(label: 'Sugar', value: '5.9g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/GUAVA.png',
                  foodName: 'GUAVA',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '14g'),
                    NutrientTile(label: 'Fats', value: '0.9g'),
                    NutrientTile(label: 'Proteins', value: '2.6g'),
                    NutrientTile(label: 'Calories', value: '68 kcal'),
                    NutrientTile(label: 'Sugar', value: '9g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/AVOCADO.PNG',
                  foodName: 'AVOCADO',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '8.5g'),
                    NutrientTile(label: 'Fats', value: '15g'),
                    NutrientTile(label: 'Proteins', value: '2g'),
                    NutrientTile(label: 'Calories', value: '160 kcal'),
                    NutrientTile(label: 'Sugar', value: '7g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/POMELO.PNG',
                  foodName: 'POMELO',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '9.6g'),
                    NutrientTile(label: 'Fats', value: '0.04g'),
                    NutrientTile(label: 'Proteins', value: '0.8g'),
                    NutrientTile(label: 'Calories', value: '38 kcal'),
                    NutrientTile(label: 'Sugar', value: '7g'),
                  ],
                ),

                const SizedBox(height: 30),
                const Text(
                  '🚫 DON\'T',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.red),
                ),
                const SizedBox(height: 10),

                _buildFoodCard(
                  imagePath: 'assets/images/SODA.PNG',
                  foodName: 'SODA',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '39g'),
                    NutrientTile(label: 'Fats', value: '0g'),
                    NutrientTile(label: 'Proteins', value: '0g'),
                    NutrientTile(label: 'Calories', value: '150kcal'),
                    NutrientTile(label: 'Sugar', value: '39g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/rice.png',
                  foodName: 'WHITE RICE',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '45g'),
                    NutrientTile(label: 'Fats', value: '0.4g'),
                    NutrientTile(label: 'Proteins', value: '4.2g'),
                    NutrientTile(label: 'Calories', value: '206kcal'),
                    NutrientTile(label: 'Sugar', value: '0.1g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/tocino.png',
                  foodName: 'TOCINO',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '10g'),
                    NutrientTile(label: 'Fats', value: '15g'),
                    NutrientTile(label: 'Proteins', value: '8g'),
                    NutrientTile(label: 'Calories', value: '210kcal'),
                    NutrientTile(label: 'Sugar', value: '9g'),
                  ],
                ),_buildFoodCard(
                  imagePath: 'assets/images/noodles.png',
                  foodName: 'NOODLES',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '40g'),
                    NutrientTile(label: 'Fats', value: '13g'),
                    NutrientTile(label: 'Proteins', value: '5g'),
                    NutrientTile(label: 'Calories', value: '290kcal'),
                    NutrientTile(label: 'Sugar', value: '2g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/BANANA.PNG',
                  foodName: 'BANANA',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '23g'),
                    NutrientTile(label: 'Fats', value: '0.3g'),
                    NutrientTile(label: 'Proteins', value: '1.1g'),
                    NutrientTile(label: 'Calories', value: '89kcal'),
                    NutrientTile(label: 'Sugar', value: '12g'),
                  ],
                ),
                _buildFoodCard(
                  imagePath: 'assets/images/MANGO.PNG',
                  foodName: 'MANGO',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '15g'),
                    NutrientTile(label: 'Fats', value: '0.4g'),
                    NutrientTile(label: 'Proteins', value: '0.8g'),
                    NutrientTile(label: 'Calories', value: '60kcal'),
                    NutrientTile(label: 'Sugar', value: '13.7g'),
                  ],
                ),_buildFoodCard(
                  imagePath: 'assets/images/PINE.PNG',
                  foodName: 'PINEAPPLE',
                  nutrients: const [
                    NutrientTile(label: 'Carbohydrates', value: '13g'),
                    NutrientTile(label: 'Fats', value: '0.1g'),
                    NutrientTile(label: 'Proteins', value: '0.5g'),
                    NutrientTile(label: 'Calories', value: '50kcal'),
                    NutrientTile(label: 'Sugar', value: '10g'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodCard({
    required String imagePath,
    required String foodName,
    required List<NutrientTile> nutrients,
  }) {
    return Card(
      color: Colors.white.withOpacity(0.85),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                imagePath,
                width: 120,
                height: 150,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    foodName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 4, 80, 116),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...nutrients,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NutrientTile extends StatelessWidget {
  final String label;
  final String value;

  const NutrientTile({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 16, color: Color.fromARGB(255, 4, 80, 116)),
              const SizedBox(width: 6),
              Text(label),
            ],
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
