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
//   Severe → 80% of TDEE, max 20g carbs/meal, 3 meals/day
//            + High-carb foods (>12g/100g) get 50% portion reduction
//
// ACTIVITY MULTIPLIERS (Ainsworth MET-based TDEE):
//   Sedentary  → ×1.20  (desk job, no exercise)
//   Light      → ×1.375 (light exercise 1-3 days/week)
//   Very Active→ ×1.725 (hard exercise 6-7 days/week)

class NutritionCalculator {

  // ── Activity multipliers ────────────────────────────────────────────────────
  static const Map<String, double> _activityMult = {
    'Sedentary':   1.20,
    'Light':       1.375,
    'Very Active': 1.725,
  };

  // ── Diabetes-adjusted TDEE fraction (how much of TDEE is the daily target) ──
  static const Map<String, double> _tdeeAdjustment = {
    'Mild':   0.90,   // 90 % of TDEE — less restricted
    'Severe': 0.80,   // 80 % of TDEE — more restricted
  };

  // ── Macro split by diabetes type (% of daily calories) ─────────────────────
  // Mild:   Carbs 45% | Protein 25% | Fat 30%
  // Severe: Carbs 35% | Protein 30% | Fat 35%  ← lower carbs for Severe
  static const Map<String, Map<String, double>> _macroSplit = {
    'Mild':   {'carb': 0.45, 'protein': 0.25, 'fat': 0.30},
    'Severe': {'carb': 0.35, 'protein': 0.30, 'fat': 0.35},
  };

  // ── Max carbs per single meal ───────────────────────────────────────────────
  static const Map<String, double> _maxCarbsPerMeal = {
    'Mild':   50.0,   // 45-60 g/meal is safe for Mild
    'Severe': 20.0,   // ≤20 g/meal for Severe (stricter control)
  };

  // ── High-carb food threshold (g carbs per 100g) ─────────────────────────────
  // If food has more carbs than this, apply extra restrictions for Severe
  static const double _highCarbThreshold = 12.0;  // >12g carbs/100g = high-carb

  // ── Meals per day ───────────────────────────────────────────────────────────
  static const int _mealsPerDay = 3;

  // ════════════════════════════════════════════════════════════════════════════
  // BMR — Harris-Benedict Revised (gender-neutral: average of male + female)
  // Age fixed at 35 (reasonable average for unknown age)
  // ════════════════════════════════════════════════════════════════════════════
  static double bmr(double heightCm, double weightKg) {
    const age  = 35.0;
    final male   = 88.362  + (13.397 * weightKg) + (4.799 * heightCm) - (5.677 * age);
    final female = 447.593 + ( 9.247 * weightKg) + (3.098 * heightCm) - (4.330 * age);
    return (male + female) / 2.0;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TDEE — Total Daily Energy Expenditure = BMR × activity multiplier
  // ════════════════════════════════════════════════════════════════════════════
  static double tdee(double heightCm, double weightKg, String activityLevel) {
    final mult = _activityMult[activityLevel] ?? 1.375;
    return bmr(heightCm, weightKg) * mult;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Daily calorie target — TDEE adjusted for diabetes type
  // ════════════════════════════════════════════════════════════════════════════
  static double dailyCalorieTarget(
      double heightCm, double weightKg, String activityLevel, String diabetesType) {
    final t    = tdee(heightCm, weightKg, activityLevel);
    final adj  = _tdeeAdjustment[diabetesType] ?? 0.85;
    return (t * adj).roundToDouble();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Daily macro targets in grams
  //   Carb:    4 kcal/g
  //   Protein: 4 kcal/g
  //   Fat:     9 kcal/g
  // ════════════════════════════════════════════════════════════════════════════
  static DailyGoals dailyGoals(
      double heightCm, double weightKg, String activityLevel, String diabetesType) {
    final calTarget = dailyCalorieTarget(heightCm, weightKg, activityLevel, diabetesType);
    final split     = _macroSplit[diabetesType] ?? _macroSplit['Severe']!;
    return DailyGoals(
      calories: calTarget,
      carbs:    ((calTarget * split['carb']!)    / 4).roundToDouble(),
      protein:  ((calTarget * split['protein']!) / 4).roundToDouble(),
      fat:      ((calTarget * split['fat']!)     / 9).roundToDouble(),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Per-meal portion in grams for a specific food
  //
  // Logic:
  //   mealCalBudget  = dailyCalTarget / 3
  //   gramsByCalories= (mealCalBudget / calories100g) × 100
  //   gramsByCarbs   = (maxCarbsPerMeal / carbs100g) × 100   [if carbs present]
  //   portionGrams   = min(gramsByCalories, gramsByCarbs)
  //                    clamped to [30g, 400g], rounded to nearest 5g
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

    final calTarget   = dailyCalorieTarget(heightCm, weightKg, activityLevel, diabetesType);
    final mealBudget  = calTarget / _mealsPerDay;
    final maxCarbs    = _maxCarbsPerMeal[diabetesType] ?? 20.0;

    final gramsByCal  = (mealBudget / calories100g) * 100.0;
    final gramsByCarb = carbs100g > 0
        ? (maxCarbs / carbs100g) * 100.0
        : gramsByCal;

    var raw = gramsByCal < gramsByCarb ? gramsByCal : gramsByCarb;

    // ── SEVERE DIABETES: Extra restriction for high-carb foods ────────────────
    if (diabetesType == 'Severe' && carbs100g > _highCarbThreshold) {
      // High-carb foods (>12g/100g) get cut to 50% of normal portion for Severe
      raw = raw * 0.5;
    }

    return ((raw.clamp(30.0, 250.0)) / 5).round() * 5.0;  // Max 250g for safety
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Scale per-100g nutrients to given grams
  // ════════════════════════════════════════════════════════════════════════════
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

  // ════════════════════════════════════════════════════════════════════════════
  // MAIN ENTRY POINT
  // Returns PersonalizedNutrition with portion + scaled macros + context
  // ════════════════════════════════════════════════════════════════════════════
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
    // ── Fallback: profile incomplete → return raw 100g values ────────────────
    if (heightCm == null || weightKg == null ||
        heightCm <= 0    || weightKg <= 0) {
      return PersonalizedNutrition(
        grams:          100,
        portionLabel:   '100g (default)',
        calories:       calories100g,
        carbs:          carbs100g,
        protein:        protein100g,
        fat:            fat100g,
        isPersonalized: false,
        bmrValue:       0,
        tdeeValue:      0,
        dailyCalTarget: 0,
        mealCalBudget:  0,
      );
    }

    // ── Step 1 — BMR ─────────────────────────────────────────────────────────
    final bmrVal  = bmr(heightCm, weightKg);

    // ── Step 2 — TDEE ────────────────────────────────────────────────────────
    final tdeeVal = tdee(heightCm, weightKg, activityLevel);

    // ── Step 3 — Diabetes-adjusted daily calorie target ───────────────────────
    final dailyCal = dailyCalorieTarget(heightCm, weightKg, activityLevel, diabetesType);

    // ── Step 4 — Per-meal calorie budget ─────────────────────────────────────
    final mealBudget = dailyCal / _mealsPerDay;

    // ── Step 5 — Portion grams ────────────────────────────────────────────────
    final grams = recommendedGrams(
      heightCm:      heightCm,
      weightKg:      weightKg,
      activityLevel: activityLevel,
      diabetesType:  diabetesType,
      calories100g:  calories100g,
      carbs100g:     carbs100g,
    );

    // ── Step 6 — Scale nutrients ──────────────────────────────────────────────
    final n = scaleNutrients(
      grams:        grams,
      calories100g: calories100g,
      carbs100g:    carbs100g,
      protein100g:  protein100g,
      fat100g:      fat100g,
    );

    // ── Portion label ─────────────────────────────────────────────────────────
    final label = '${grams.toInt()}g (for you)';

    return PersonalizedNutrition(
      grams:          grams,
      portionLabel:   label,
      calories:       n['calories']!,
      carbs:          n['carbs']!,
      protein:        n['protein']!,
      fat:            n['fat']!,
      isPersonalized: true,
      bmrValue:       bmrVal,
      tdeeValue:      tdeeVal,
      dailyCalTarget: dailyCal,
      mealCalBudget:  mealBudget,
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
  final bool   isPersonalized;

  // Exposed calculation context (shown in scanner info panel)
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

// ── Daily macro goal model ─────────────────────────────────────────────────────
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