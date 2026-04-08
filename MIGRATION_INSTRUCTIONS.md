# 🔧 Data Migration Instructions

## Problem
Your existing foods in the database have the OLD structure and are not showing up in the user dashboard.

## Solution
Run this migration to update all existing foods to the new structure.

## Steps:

### Option 1: Use the Migration Tool (Recommended)

1. **Add Migration Button to Admin Dashboard**
   
   Open `lib/Screens/admin_dashboard.dart` and find the section with admin buttons/cards.
   
   Add this button somewhere visible:
   
   ```dart
   ElevatedButton.icon(
     onPressed: () {
       Navigator.push(
         context,
         MaterialPageRoute(
           builder: (_) => const AdminDataMigrationScreen(),
         ),
       );
     },
     icon: const Icon(Icons.sync),
     label: const Text('Migrate Old Data'),
     style: ElevatedButton.styleFrom(
       backgroundColor: Colors.orange,
     ),
   ),
   ```

2. **Run the Migration**
   - Login as admin
   - Click the "Migrate Old Data" button
   - Click "Migrate Old Data to New Structure"
   - Wait for completion
   - Check the log to see what was updated

3. **Verify**
   - Go to user dashboard
   - Check if Do & Don't section now shows foods
   - Try searching for "apple" in meal log

### Option 2: Manual Firebase Console Fix

If you prefer to fix it manually in Firebase Console:

1. Go to Firebase Console → Firestore Database
2. Open `food_rules` collection
3. For EACH food document, add these fields:

   ```
   suitableFor: ["Mild", "Severe"]  // Array - adjust based on carbs
   
   categories: {                     // Map
     Mild: "Do",                     // or "Don't" based on carbs
     Severe: "Do"                    // or "Don't" based on carbs
   }
   
   portionSizes: {                   // Map
     Mild: "1 small apple",          // example
     Severe: "½ small apple"         // example
   }
   
   imageUrl: ""                      // Empty string if no image
   ```

### Option 3: Delete and Re-add Foods

The simplest but most tedious:

1. Delete all existing foods from Firebase Console
2. Re-add them using the updated admin panel
3. The new admin panel will automatically set all required fields

## What the Migration Does

For each food in your database:

1. **Calculates `suitableFor`** based on carb content:
   - If carbs ≤ 20g → suitable for both Mild and Severe
   - If carbs ≤ 35g → suitable for Mild only
   - If carbs > 35g → still added but marked as "Don't"

2. **Calculates `categories`** for each diabetes type:
   - Mild: carbs > 35g → "Don't", else "Do"
   - Severe: carbs > 20g → "Don't", else "Do"

3. **Calculates `portionSizes`** using the portion calculator:
   - Generates human-readable portions like "1 small apple"
   - Different portions for Mild vs Severe

4. **Adds `imageUrl`** field (empty if not set)

## After Migration

Your foods will have this structure:

```javascript
{
  // OLD fields (kept for compatibility)
  name: "Apple",
  diabetesType: "Mild",
  category: "Do",
  calories: 52,
  carbs: 14,
  protein: 0.3,
  fat: 0.2,
  
  // NEW fields (added by migration)
  suitableFor: ["Mild", "Severe"],
  categories: {
    "Mild": "Do",
    "Severe": "Do"
  },
  portionSizes: {
    "Mild": "1 small apple",
    "Severe": "½ small apple"
  },
  imageUrl: "",
  updatedAt: timestamp
}
```

## Troubleshooting

If foods still don't show after migration:

1. Check the debug logs in your console
2. Verify your user's diabetes type is set correctly
3. Make sure the food's `suitableFor` array contains your diabetes type
4. Check that `categories[YourDiabetesType]` is either "Do" or "Don't"

## Need Help?

Share the debug logs from the console and I can help diagnose the issue!
