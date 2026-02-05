import 'dart:convert';
import 'package:http/http.dart' as http;

class NutritionService {
  final String appId = 'YOUR_EDAMAM_APP_ID';
  final String appKey = 'YOUR_EDAMAM_APP_KEY';

  Future<Map<String, dynamic>?> fetchNutrition(String foodName) async {
    try {
      final uri = Uri.parse(
        'https://api.edamam.com/api/nutrition-data'
        '?app_id=$appId&app_key=$appKey&ingr=${Uri.encodeComponent(foodName)}',
      );

      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);

      return {
        'calories': data['calories'] ?? 0,
        'carbs':
            data['totalNutrients']?['CHOCDF']?['quantity']?.toDouble() ?? 0,
        'protein':
            data['totalNutrients']?['PROCNT']?['quantity']?.toDouble() ?? 0,
        'fat':
            data['totalNutrients']?['FAT']?['quantity']?.toDouble() ?? 0,
      };
    } catch (e) {
      return null;
    }
  }
}
