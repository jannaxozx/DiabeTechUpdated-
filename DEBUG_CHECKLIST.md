# Debug Checklist - Food Not Showing

## Step 1: Restart the App
```bash
# Stop the app completely (not hot reload)
# Then restart:
flutter run
```

## Step 2: Check User Profile
1. Open the app and go to Dashboard
2. Look at the debug console for:
```
=== USER PROFILE ===
User ID: ...
Raw diabetesType: Severe
Parsed diabetesType: "Severe"
Parsed height: 160.0
Parsed weight: 60.0
===================
```

**❌ If you see:**
- `diabetesType: null` or `diabetesType: Not set`
- Go to Edit Profile and set your diabetes type to "Severe"

**❌ If height/weight are null:**
- Go to Edit Profile and enter your height and weight

## Step 3: Add a Test Food in Admin Panel
Add a simple food with LOW carbs (should be "Do" for Severe):

**Food Name:** Test Apple
**Nutrition per 100g:**
- Calories: 52
- Carbs: 14 (this is LOW, should be "Do" for Severe)
- Protein: 0.3
- Fat: 0.2
**Image:** Upload any image

Click "Save Food"

## Step 4: Check Admin Save Logs
Look for this in debug console:
```
=== SAVING FOOD ===
Name: Test Apple
Carbs: 14.0g per 100g
Suitable for: [Mild, Severe]
Categories: {Mild: Do, Severe: Do}
Portion sizes: {Mild: 1 medium apple, Severe: 1 small apple}
==================
```

**✅ Expected:** 
- Suitable for: [Mild, Severe] (because 14g ≤ 20g)
- Categories: Both "Do" (because 14g ≤ 20g for Severe, ≤ 35g for Mild)

**❌ If you don't see this log:**
- The save function is not being called
- Check if there are any errors in the console

## Step 5: Go Back to User Dashboard
Pull down to refresh the dashboard.

Look for this in debug console:
```
=== DO/DON'T DEBUG ===
Total foods in database: 1
User diabetes type: "Severe"
User height: 160.0
User weight: 60.0

--- Food: Test Apple ---
  Document ID: test apple
  nameLower: test apple
  carbs: 14.0g per 100g
  suitableFor (NEW): [Mild, Severe]
  categories (NEW): {Mild: Do, Severe: Do}
  portionSizes: {Mild: 1 medium apple, Severe: 1 small apple}
  imageUrl: https://...

Filtered foods count: 1
DO foods count: 1
DON'T foods count: 0
=== END DEBUG ===
```

## Step 6: Verify Display
You should now see:
- **✅ DO: 1 foods** (green card)
- **🚫 DON'T: 0 foods** (red card)

Click on "✅ DO" and you should see:
- Image of the apple
- Name: "Test Apple"
- Portion: "1 small apple" (for Severe user)

## Step 7: Test Meal Log
1. Go to Meal Log (bottom navigation)
2. Search for "apple"
3. You should see "Test Apple" in the results

## Common Issues and Solutions

### Issue 1: "Total foods in database: 0"
**Problem:** Food was not saved to Firestore
**Solution:**
1. Check Firebase Console → Firestore Database
2. Look for `food_rules` collection
3. If empty, check Firestore security rules
4. Make sure admin has write permission

### Issue 2: "User diabetes type: Loading..."
**Problem:** User profile not loaded yet
**Solution:**
1. Wait a few seconds and pull down to refresh
2. If still loading, check Firebase Console → users collection
3. Verify your user document has `diabetesType` field

### Issue 3: "Filtered foods count: 0" but "Total foods: 1"
**Problem:** Food's `suitableFor` doesn't include your diabetes type
**Solution:**
1. Check the food's carbs value
2. For Severe: carbs must be ≤ 20g to be suitable
3. For Mild: carbs must be ≤ 35g to be suitable
4. If carbs > 35g, food will show in "DON'T" for both types

### Issue 4: Food shows but no image
**Problem:** Image upload failed or imageUrl is empty
**Solution:**
1. Check Firebase Console → Storage
2. Verify image was uploaded to `food_images/` folder
3. Check Firestore document has `imageUrl` field with valid URL

### Issue 5: "DO foods count: 0" but "Filtered foods count: 1"
**Problem:** Category calculation is wrong
**Solution:**
1. Check the debug log for `categories` field
2. Should be: `{Mild: Do, Severe: Do}` for low-carb foods
3. If wrong, delete the food and re-add it

## Expected Behavior by Carb Content

### Low Carb (0-20g per 100g)
Examples: Chicken, Fish, Eggs, Leafy Vegetables
- **Suitable for:** Mild ✅, Severe ✅
- **Category:** Do (both types)
- **Shows in:** "DO" section for both types

### Medium Carb (21-35g per 100g)
Examples: Banana, Sweet Potato, Oats
- **Suitable for:** Mild ✅, Severe ❌
- **Category:** 
  - Mild: Do ✅
  - Severe: Don't ❌
- **Shows in:** 
  - Mild users: "DO" section
  - Severe users: "DON'T" section

### High Carb (36g+ per 100g)
Examples: White Rice, Bread, Pasta, Sweets
- **Suitable for:** Mild ❌, Severe ❌
- **Category:** Don't (both types)
- **Shows in:** "DON'T" section for both types

## Firestore Structure Check

Go to Firebase Console and verify your food document looks like this:

```
food_rules/test apple
{
  name: "Test Apple"
  nameLower: "test apple"          ← MUST HAVE THIS
  calories: 52
  carbs: 14
  protein: 0.3
  fat: 0.2
  imageUrl: "https://..."
  suitableFor: ["Mild", "Severe"]  ← MUST BE ARRAY
  categories: {                     ← MUST BE MAP
    Mild: "Do"
    Severe: "Do"
  }
  portionSizes: {                   ← MUST BE MAP
    Mild: "1 medium apple"
    Severe: "1 small apple"
  }
  createdAt: Timestamp
  updatedAt: Timestamp
}
```

## Still Not Working?

If you've tried everything above and it still doesn't work, send me:

1. Screenshot of Firebase Console → Firestore → food_rules collection
2. Screenshot of Firebase Console → Firestore → users → [your user id]
3. Copy of the debug console logs (all the === sections)
4. Screenshot of your dashboard showing "0 foods"

This will help me identify the exact issue!
