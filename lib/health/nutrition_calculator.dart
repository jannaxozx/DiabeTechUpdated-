// lib/health/nutrition_calculator.dart
//
// Calculates a personalized recommended portion (grams) and scaled nutrients
// for a diabetic user based on height, weight, activity level, and
// diabetes type.  Admin always inputs nutrients per 100g of food.
// Supported diabetes types: Mild | Severe

class NutritionCalculator {
  // ── Activity multipliers (TDEE factor) ─────────────────────────────────────
  static const Map<String, double> _activityMultiplier = {
    'Sedentary':   1.20,
    'Light':       1.375,
    'Very Active': 1.725,
  };

  // ── Per-meal calorie fraction by diabetes severity ──────────────────────────
  // Mild:   30% of TDEE per meal  (less restricted)
  // Severe: 24% of TDEE per meal  (more restricted)
  static const Map<String, double> _mealCalorieFraction = {
    'Mild':   0.30,
    'Severe': 0.24,
  };

  // ── Max carbs per meal (grams) ──────────────────────────────────────────────
  static const Map<String, double> _maxCarbsPerMeal = {
    'Mild':   50.0,
    'Severe': 30.0,
  };

  // ── BMR – Mifflin-St Jeor, gender-neutral average (age = 40) ───────────────
  static double _bmr(double heightCm, double weightKg) {
    final male   = 10 * weightKg + 6.25 * heightCm - 5 * 40 + 5;
    final female = 10 * weightKg + 6.25 * heightCm - 5 * 40 - 161;
    return (male + female) / 2;
  }

  static double _tdee(double heightCm, double weightKg, String activityLevel) {
    final mult = _activityMultiplier[activityLevel] ?? 1.375;
    return _bmr(heightCm, weightKg) * mult;
  }

  /// Returns recommended grams of this food for one meal.
  static double recommendedGrams({
    required double heightCm,
    required double weightKg,
    required String activityLevel,
    required String diabetesType,
    required double calories100g,
    required double carbs100g,
  }) {
    if (calories100g <= 0) return 100.0;
    final tdee        = _tdee(heightCm, weightKg, activityLevel);
    final calFraction = _mealCalorieFraction[diabetesType] ?? 0.24; // default Severe
    final maxCarbs    = _maxCarbsPerMeal[diabetesType]     ?? 30.0;

    final gramsByCalories = (tdee * calFraction / calories100g) * 100;
    final gramsByCarbs    =
        carbs100g > 0 ? (maxCarbs / carbs100g) * 100 : gramsByCalories;

    final raw = gramsByCalories < gramsByCarbs ? gramsByCalories : gramsByCarbs;
    return ((raw.clamp(30.0, 300.0)) / 5).round() * 5.0;
  }

  /// Scale per-100g nutrients to a specific gram amount.
  static Map<String, double> scaleNutrients({
    required double grams,
    required double calories100g,
    required double carbs100g,
    required double protein100g,
    required double fat100g,
  }) {
    final f = grams / 100.0;
    return {
      'calories': double.parse((calories100g * f).toStringAsFixed(1)),
      'carbs':    double.parse((carbs100g    * f).toStringAsFixed(1)),
      'protein':  double.parse((protein100g  * f).toStringAsFixed(1)),
      'fat':      double.parse((fat100g      * f).toStringAsFixed(1)),
    };
  }

  /// Main entry point → returns [PersonalizedNutrition]
  static PersonalizedNutrition calculate({
    required double? heightCm,
    required double? weightKg,
    required String  activityLevel,
    required String  diabetesType,
    required double  calories100g,
    required double  carbs100g,
    required double  protein100g,
    required double  fat100g,
  }) {
    // If profile incomplete → return raw 100g as fallback
    if (heightCm == null || weightKg == null || heightCm <= 0 || weightKg <= 0) {
      return PersonalizedNutrition(
        grams:          100,
        portionLabel:   '100g (default)',
        calories:       calories100g,
        carbs:          carbs100g,
        protein:        protein100g,
        fat:            fat100g,
        isPersonalized: false,
      );
    }

    final grams = recommendedGrams(
      heightCm:      heightCm,
      weightKg:      weightKg,
      activityLevel: activityLevel,
      diabetesType:  diabetesType,
      calories100g:  calories100g,
      carbs100g:     carbs100g,
    );

    final n = scaleNutrients(
      grams:        grams,
      calories100g: calories100g,
      carbs100g:    carbs100g,
      protein100g:  protein100g,
      fat100g:      fat100g,
    );

    return PersonalizedNutrition(
      grams:          grams,
      portionLabel:   '${grams.toInt()}g (for you)',
      calories:       n['calories']!,
      carbs:          n['carbs']!,
      protein:        n['protein']!,
      fat:            n['fat']!,
      isPersonalized: true,
    );
  }
}

class PersonalizedNutrition {
  final double grams;
  final String portionLabel;
  final double calories;
  final double carbs;
  final double protein;
  final double fat;
  final bool   isPersonalized;

  const PersonalizedNutrition({
    required this.grams,
    required this.portionLabel,
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.isPersonalized,
  });
}