// lib/health/nutrition_calculator.dart
//
// Personalized nutrition engine for DiabeTech.
//
// FORMULA CHAIN:
//   1. BMR  — Harris-Benedict Revised (gender-neutral average, age 35)
//   2. TDEE — BMR × activity multiplier
//   3. Diabetes-adjusted daily calorie target
//   4. Per-meal calorie budget  = daily target ÷ 3 meals
//   5. Portion grams            = limited by BOTH calorie budget AND max carbs/meal
//   6. Nutrient values          = scaled from per-100g admin data to portion grams
//
// DIABETES TYPE RULES:
//   Mild   → 90% of TDEE, max 50g carbs/meal, 3 meals/day
//   Severe → 80% of TDEE, max 30g carbs/meal, 3 meals/day
//
// ACTIVITY MULTIPLIERS (Ainsworth MET-based TDEE):
//   Sedentary   → ×1.20  (desk job, no exercise)
//   Light       → ×1.375 (light exercise 1-3 days/week)
//   Very Active → ×1.725 (hard exercise 6-7 days/week)

class NutritionCalculator {
  // ── Activity multipliers ────────────────────────────────────────────────────
  static const Map<String, double> _activityMult = {
    'Sedentary': 1.20,
    'Light': 1.375,
    'Very Active': 1.725,
  };

  // ── Diabetes-adjusted TDEE fraction ────────────────────────────────────────
  static const Map<String, double> _tdeeAdjustment = {
    'Mild': 0.90, // 90% of TDEE — less restricted
    'Severe': 0.80, // 80% of TDEE — more restricted
  };

  // ── Macro split by diabetes type (% of daily calories) ─────────────────────
  // Mild:   Carbs 45% | Protein 25% | Fat 30%
  // Severe: Carbs 35% | Protein 30% | Fat 35%
  static const Map<String, Map<String, double>> _macroSplit = {
    'Mild': {'carb': 0.45, 'protein': 0.25, 'fat': 0.30},
    'Severe': {'carb': 0.35, 'protein': 0.30, 'fat': 0.35},
  };

  // ── Max carbs per single meal ───────────────────────────────────────────────
  static const Map<String, double> _maxCarbsPerMeal = {
    'Mild': 45.0, // 45g/meal is safe for Mild
    'Severe': 15.0, // ≤15g/meal for Severe (very strict - ADA guideline)
  };

  // ── Meals per day ───────────────────────────────────────────────────────────
  static const int _mealsPerDay = 3;

  // ════════════════════════════════════════════════════════════════════════════
  // BMR — Harris-Benedict Revised (gender-neutral: average of male + female)
  // Age fixed at 35 (reasonable average for unknown age)
  // ════════════════════════════════════════════════════════════════════════════
  static double bmr(double heightCm, double weightKg) {
    const double age = 35.0;
    final double male =
        88.362 + (13.397 * weightKg) + (4.799 * heightCm) - (5.677 * age);
    final double female =
        447.593 + (9.247 * weightKg) + (3.098 * heightCm) - (4.330 * age);
    return (male + female) / 2.0;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TDEE = BMR × activity multiplier
  // ════════════════════════════════════════════════════════════════════════════
  static double tdee(double heightCm, double weightKg, String activityLevel) {
    final double mult = _activityMult[activityLevel] ?? 1.375;
    return bmr(heightCm, weightKg) * mult;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Daily calorie target — TDEE adjusted for diabetes type
  // ════════════════════════════════════════════════════════════════════════════
  static double dailyCalorieTarget(
    double heightCm,
    double weightKg,
    String activityLevel,
    String diabetesType,
  ) {
    final double t = tdee(heightCm, weightKg, activityLevel);
    final double adj = _tdeeAdjustment[diabetesType] ?? 0.85;
    return (t * adj).roundToDouble();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Daily macro targets in grams
  //   Carb:    4 kcal/g
  //   Protein: 4 kcal/g
  //   Fat:     9 kcal/g
  // ════════════════════════════════════════════════════════════════════════════
  static DailyGoals dailyGoals(
    double heightCm,
    double weightKg,
    String activityLevel,
    String diabetesType,
  ) {
    final double calTarget = dailyCalorieTarget(
      heightCm,
      weightKg,
      activityLevel,
      diabetesType,
    );
    final Map<String, double> split =
        _macroSplit[diabetesType] ?? _macroSplit['Severe']!;
    return DailyGoals(
      calories: calTarget,
      carbs: ((calTarget * split['carb']!) / 4).roundToDouble(),
      protein: ((calTarget * split['protein']!) / 4).roundToDouble(),
      fat: ((calTarget * split['fat']!) / 9).roundToDouble(),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Per-meal portion in grams for a specific food
  //
  // Logic:
  //   mealCalBudget   = dailyCalTarget / 3
  //   gramsByCalories = (mealCalBudget / calories100g) × 100
  //   gramsByCarbs    = (maxCarbsPerMeal / carbs100g) × 100  [if carbs > 0]
  //   portionGrams    = min(gramsByCalories, gramsByCarbs)
  //                     clamped to [30g, maxGrams], rounded to nearest 5g
  //
  // FRUIT/HIGH-CARB FOOD CAPS (ADA guideline):
  //   Severe: max 100g per portion for high-carb foods (carbs > 10g/100g)
  //   Mild:   max 150g per portion for high-carb foods (carbs > 10g/100g)
  // ════════════════════════════════════════════════════════════════════════════
  static double recommendedGrams({
    required double heightCm,
    required double weightKg,
    required String activityLevel,
    required String diabetesType,
    required double calories100g,
    required double carbs100g,
  }) {
    if (calories100g <= 0) return 100.0;

    final double calTarget = dailyCalorieTarget(
      heightCm,
      weightKg,
      activityLevel,
      diabetesType,
    );
    final double mealBudget = calTarget / _mealsPerDay;
    final double maxCarbs = _maxCarbsPerMeal[diabetesType] ?? 30.0;

    final double gramsByCal = (mealBudget / calories100g) * 100.0;
    final double gramsByCarb =
        carbs100g > 0 ? (maxCarbs / carbs100g) * 100.0 : gramsByCal;

    final double raw = gramsByCal < gramsByCarb ? gramsByCal : gramsByCarb;

    // ── Smart max cap for high-carb foods ────────────────────────────────────
    // If food has >10g carbs per 100g (fruits, bread, rice etc.)
    // apply a stricter max to prevent unrealistic large portions
    double maxGrams = 400.0;
    if (carbs100g > 10) {
      // High-carb food — apply diabetes-specific cap
      maxGrams = diabetesType == 'Severe' ? 100.0 : 150.0;
    } else if (carbs100g > 5) {
      // Medium-carb food
      maxGrams = diabetesType == 'Severe' ? 150.0 : 250.0;
    }
    // Low-carb foods (meat, fish, eggs, tofu) keep the 400g max

    return ((raw.clamp(30.0, maxGrams)) / 5).round() * 5.0;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Scale per-100g nutrients to given portion grams
  // ════════════════════════════════════════════════════════════════════════════
  static Map<String, double> scaleNutrients({
    required double grams,
    required double calories100g,
    required double carbs100g,
    required double protein100g,
    required double fat100g,
  }) {
    final double f = grams / 100.0;
    return {
      'calories': double.parse((calories100g * f).toStringAsFixed(1)),
      'carbs': double.parse((carbs100g * f).toStringAsFixed(1)),
      'protein': double.parse((protein100g * f).toStringAsFixed(1)),
      'fat': double.parse((fat100g * f).toStringAsFixed(1)),
    };
  }

  // ════════════════════════════════════════════════════════════════════════════
  // MAIN ENTRY POINT
  // Returns PersonalizedNutrition with portion + scaled macros + context
  // ════════════════════════════════════════════════════════════════════════════
  static PersonalizedNutrition calculate({
    required double? heightCm,
    required double? weightKg,
    required String activityLevel,
    required String diabetesType,
    required double calories100g,
    required double carbs100g,
    required double protein100g,
    required double fat100g,
  }) {
    // Fallback: profile incomplete → return raw 100g values
    if (heightCm == null ||
        weightKg == null ||
        heightCm <= 0 ||
        weightKg <= 0) {
      return PersonalizedNutrition(
        grams: 100,
        portionLabel: '100g (default)',
        calories: calories100g,
        carbs: carbs100g,
        protein: protein100g,
        fat: fat100g,
        isPersonalized: false,
        bmrValue: 0,
        tdeeValue: 0,
        dailyCalTarget: 0,
        mealCalBudget: 0,
      );
    }

    // Step 1 — BMR
    final double bmrVal = bmr(heightCm, weightKg);

    // Step 2 — TDEE
    final double tdeeVal = tdee(heightCm, weightKg, activityLevel);

    // Step 3 — Diabetes-adjusted daily calorie target
    final double dailyCal = dailyCalorieTarget(
      heightCm,
      weightKg,
      activityLevel,
      diabetesType,
    );

    // Step 4 — Per-meal calorie budget
    final double mealBudget = dailyCal / _mealsPerDay;

    // Step 5 — Portion grams (limited by calories AND carbs)
    final double grams = recommendedGrams(
      heightCm: heightCm,
      weightKg: weightKg,
      activityLevel: activityLevel,
      diabetesType: diabetesType,
      calories100g: calories100g,
      carbs100g: carbs100g,
    );

    // Step 6 — Scale nutrients to portion
    final Map<String, double> n = scaleNutrients(
      grams: grams,
      calories100g: calories100g,
      carbs100g: carbs100g,
      protein100g: protein100g,
      fat100g: fat100g,
    );

    return PersonalizedNutrition(
      grams: grams,
      portionLabel: '${grams.toInt()}g (for you)',
      calories: n['calories']!,
      carbs: n['carbs']!,
      protein: n['protein']!,
      fat: n['fat']!,
      isPersonalized: true,
      bmrValue: bmrVal,
      tdeeValue: tdeeVal,
      dailyCalTarget: dailyCal,
      mealCalBudget: mealBudget,
    );
  }
}

// ── Result model ──────────────────────────────────────────────────────────────
class PersonalizedNutrition {
  final double grams;
  final String portionLabel;
  final double calories;
  final double carbs;
  final double protein;
  final double fat;
  final bool isPersonalized;

  // Calculation context (shown in scanner breakdown panel)
  final double bmrValue;
  final double tdeeValue;
  final double dailyCalTarget;
  final double mealCalBudget;

  const PersonalizedNutrition({
    required this.grams,
    required this.portionLabel,
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.isPersonalized,
    required this.bmrValue,
    required this.tdeeValue,
    required this.dailyCalTarget,
    required this.mealCalBudget,
  });
}

// ── Daily macro goal model ────────────────────────────────────────────────────
class DailyGoals {
  final double calories;
  final double carbs;
  final double protein;
  final double fat;

  const DailyGoals({
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// AUTO-DETERMINE FOOD CATEGORY (Do/Don't) based on carbs and diabetes type
// ════════════════════════════════════════════════════════════════════════════
class FoodCategoryHelper {
  /// Determines if food is "Do" (safe) or "Don't" (avoid) for given diabetes type
  ///
  /// RULES:
  /// Severe Diabetes:
  ///   - Don't: carbs > 20g per 100g (high-carb foods like rice, bread, sweets)
  ///   - Do: carbs ≤ 20g per 100g (low-carb foods like vegetables, lean meat)
  ///
  /// Mild Diabetes:
  ///   - Don't: carbs > 35g per 100g (very high-carb foods like sweets, white bread)
  ///   - Do: carbs ≤ 35g per 100g (moderate-carb foods acceptable in portions)
  static String determineCategory(double carbs100g, String diabetesType) {
    if (diabetesType == 'Severe') {
      return carbs100g > 20 ? "Don't" : 'Do';
    } else if (diabetesType == 'Mild') {
      return carbs100g > 35 ? "Don't" : 'Do';
    }
    // Default: if diabetes type unknown, use Severe rules (safer)
    return carbs100g > 20 ? "Don't" : 'Do';
  }

  /// Determine which diabetes types this food is suitable for
  static List<String> determineSuitableTypes(double carbs100g) {
    List<String> suitable = [];

    // Check if suitable for Mild (carbs ≤ 35g)
    if (carbs100g <= 35) {
      suitable.add('Mild');
    }

    // Check if suitable for Severe (carbs ≤ 20g)
    if (carbs100g <= 20) {
      suitable.add('Severe');
    }

    // If not suitable for any, still add both but will be marked as "Don't"
    if (suitable.isEmpty) {
      suitable = ['Mild', 'Severe'];
    }

    return suitable;
  }

  /// Get user-friendly label for category
  static String getCategoryLabel(String category) {
    return category == 'Do' ? 'Safe to Eat' : 'Avoid This Food';
  }

  /// Get color for category
  static String getCategoryColor(String category) {
    return category == 'Do' ? 'green' : 'red';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PORTION DESCRIPTION GENERATOR
// ════════════════════════════════════════════════════════════════════════════
class PortionDescriptionHelper {
  /// Converts grams to human-readable portion description
  static String gramsToHumanPortion(double grams, String foodName) {
    final lower = foodName.toLowerCase();
    final g = grams.round();

    String fraction(double count) {
      final whole = count.floor();
      final rem = count - whole;
      if (whole == 0 && rem >= 0.35) return '½';
      if (rem >= 0.65) return '${whole + 1}';
      if (rem >= 0.35) return '$whole½';
      return '${whole < 1 ? 1 : whole}';
    }

    String natural(double unitGrams, String noun, String size) {
      final count = grams / unitGrams;
      final frac = fraction(count);
      final plural = (count >= 1.75) ? 's' : '';
      return '$frac $size $noun$plural';
    }

    String sliced(double sliceG, String noun, String thickness) {
      final count = grams / sliceG;
      final frac = fraction(count);
      final plural = (count >= 1.75) ? 's' : '';
      return '$frac $thickness slice$plural $noun';
    }

    // Fruits
    if (lower.contains('apple'))
      return natural(
        120,
        'apple',
        grams < 80
            ? 'small'
            : grams < 160
            ? 'medium'
            : 'large',
      );
    if (lower.contains('banana') || lower.contains('saging'))
      return natural(
        90,
        'banana',
        grams < 70
            ? 'small'
            : grams < 120
            ? 'medium'
            : 'large',
      );
    if (lower.contains('mango') || lower.contains('mangga'))
      return natural(
        200,
        'mango',
        grams < 150
            ? 'small'
            : grams < 280
            ? 'medium'
            : 'large',
      );
    if (lower.contains('orange') || lower.contains('dalandan'))
      return natural(
        130,
        'orange',
        grams < 100
            ? 'small'
            : grams < 180
            ? 'medium'
            : 'large',
      );
    if (lower.contains('watermelon') || lower.contains('pakwan'))
      return sliced(150, 'watermelon', grams < 100 ? 'thin' : 'thick');
    if (lower.contains('pineapple') || lower.contains('pinya'))
      return sliced(80, 'pineapple', grams < 60 ? 'thin' : 'medium');
    if (lower.contains('papaya'))
      return sliced(120, 'papaya', grams < 80 ? 'thin' : 'medium');
    if (lower.contains('avocado') || lower.contains('abukado'))
      return natural(150, 'avocado', grams < 100 ? 'small' : 'medium');
    if (lower.contains('grapes') || lower.contains('ubas'))
      return natural(5, 'grape', 'small');

    // Vegetables
    if (lower.contains('broccoli'))
      return '${(grams / 30).toStringAsFixed(1)} cups florets';
    if (lower.contains('carrot') || lower.contains('karot'))
      return natural(
        60,
        'carrot',
        grams < 50
            ? 'small'
            : grams < 100
            ? 'medium'
            : 'large',
      );
    if (lower.contains('cucumber') || lower.contains('pipino'))
      return natural(100, 'cucumber', grams < 80 ? 'small' : 'medium');
    if (lower.contains('tomato') || lower.contains('kamatis'))
      return natural(
        80,
        'tomato',
        grams < 60
            ? 'small'
            : grams < 120
            ? 'medium'
            : 'large',
      );
    if (lower.contains('lettuce') || lower.contains('salad'))
      return '${(grams / 50).toStringAsFixed(1)} cups';
    if (lower.contains('spinach'))
      return '${(grams / 30).toStringAsFixed(1)} cups';

    // Proteins
    if (lower.contains('chicken') || lower.contains('manok'))
      return '${g}g (${(grams / 85).toStringAsFixed(1)} palm-sized pieces)';
    if (lower.contains('fish') ||
        lower.contains('isda') ||
        lower.contains('salmon') ||
        lower.contains('tuna'))
      return '${g}g (${(grams / 85).toStringAsFixed(1)} palm-sized fillets)';
    if (lower.contains('beef') ||
        lower.contains('pork') ||
        lower.contains('baboy'))
      return '${g}g (${(grams / 85).toStringAsFixed(1)} palm-sized pieces)';
    if (lower.contains('egg') || lower.contains('itlog'))
      return '${(grams / 50).round()} medium egg${grams >= 75 ? 's' : ''}';
    if (lower.contains('tofu'))
      return '${g}g (${(grams / 80).toStringAsFixed(1)} cubes)';

    // Grains & Starches
    if (lower.contains('rice') || lower.contains('kanin'))
      return '${(grams / 158).toStringAsFixed(1)} cup${grams >= 237 ? 's' : ''} cooked';
    if (lower.contains('bread') || lower.contains('tinapay'))
      return '${(grams / 30).round()} slice${grams >= 45 ? 's' : ''}';
    if (lower.contains('pasta'))
      return '${(grams / 140).toStringAsFixed(1)} cup${grams >= 210 ? 's' : ''} cooked';
    if (lower.contains('potato') || lower.contains('patatas'))
      return natural(
        150,
        'potato',
        grams < 120
            ? 'small'
            : grams < 200
            ? 'medium'
            : 'large',
      );
    if (lower.contains('camote') ||
        lower.contains('kamote') ||
        lower.contains('sweet potato'))
      return natural(
        130,
        'camote',
        grams < 100
            ? 'small'
            : grams < 180
            ? 'medium'
            : 'large',
      );

    // Default: just show grams
    return '${g}g';
  }
}
