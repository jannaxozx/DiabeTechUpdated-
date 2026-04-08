# URGENT DEBUG STEPS - Follow Exactly

## Step 1: Restart App
```bash
# Stop the app completely
# Then run:
flutter run
```

## Step 2: Open Debug Console
Make sure you can see the debug console output (terminal where you ran `flutter run`)

## Step 3: Go to Admin Panel
1. Open the app
2. Navigate to Admin Panel
3. Go to "Add Food" screen

## Step 4: Add Test Food
Fill in EXACTLY these values:

**Food Name:** TestApple
**Calories:** 52
**Carbs:** 14
**Protein:** 0.3
**Fat:** 0.2
**Image:** Upload any image (or skip for now)

Click "Save Food"

## Step 5: Check Console - Save Logs
You MUST see these logs in order:

```
=== SAVING FOOD ===
Name: TestApple
Carbs: 14.0g per 100g
Suitable for: [Mild, Severe]
Categories: {Mild: Do, Severe: Do}
Portion sizes: {Mild: 1 medium apple, Severe: 1 small apple}
==================
📝 Calling Firestore.set()...
✅ Firestore save SUCCESS!
```

### ❌ If you see "Firestore save FAILED":
- Copy the FULL error message
- This means Firestore permissions are wrong
- Go to Firebase Console → Firestore → Rules
- Check if you have write permission

### ❌ If you DON'T see any logs:
- The save function is not being called
- Check if you're logged in as admin
- Check if there are any errors before this

## Step 6: Go to User Dashboard
1. Navigate back to user dashboard
2. Pull down to refresh
3. Click the orange "Debug" button next to "Do & Don't Eat"

## Step 7: Check Console - Dashboard Logs
You MUST see:

```
🔍 MANUAL FIRESTORE CHECK
Total docs: 1
Doc ID: testapple
Data: {name: TestApple, nameLower: testapple, calories: 52, carbs: 14, ...}
User diabetesType: "Severe"  (or "Mild")
User height: 154.0  (your actual height)
User weight: 76.0   (your actual weight)
```

### ❌ If "Total docs: 0":
- Food was NOT saved to Firestore
- Go back to Step 5 and check for errors
- Check Firebase Console manually

### ❌ If "User diabetesType: Loading..." or "Not set":
- Your profile is not set up
- Go to Edit Profile
- Set Diabetes Type, Height, Weight
- Come back and refresh

## Step 8: Check Automatic Logs
After clicking Debug, you should also see:

```
=== DO/DON'T DEBUG ===
Total foods in database: 1
User diabetes type: "Severe"

--- Food: TestApple ---
  Document ID: testapple
  nameLower: testapple
  carbs: 14.0g per 100g
  suitableFor (NEW): [Mild, Severe]
  categories (NEW): {Mild: Do, Severe: Do}

TestApple: NEW structure, suitableFor=[Mild, Severe], matches=true
Filtered foods count: 1
TestApple: NEW categories, value=Do, isDo=true
DO foods count: 1
DON'T foods count: 0
=== END DEBUG ===
```

### ❌ If "matches=false":
- Your diabetes type doesn't match
- Check if diabetesType is exactly "Severe" or "Mild" (case-sensitive!)
- Check for extra spaces

### ❌ If "Filtered foods count: 0":
- The suitableFor array doesn't contain your diabetes type
- This means the food was saved wrong
- Delete it and re-add

### ❌ If "DO foods count: 0" but "Filtered foods count: 1":
- The categories map is wrong
- Check the "categories (NEW)" line
- Should be: {Mild: Do, Severe: Do}

## Step 9: Verify Display
You should now see:
- **✅ DO: 1 foods** (green card)
- **🚫 DON'T: 0 foods** (red card)

### ❌ If still showing "0 foods":
- The StreamBuilder is not updating
- Try hot restart (press 'R' in terminal)
- Or fully restart the app

## Step 10: Click on "✅ DO"
You should see a screen with:
- Title: "✅ DO — Recommended Foods"
- One food card with:
  - Image (if you uploaded one)
  - Name: "TestApple"
  - Portion: "1 small apple" (for Severe) or "1 medium apple" (for Mild)

### ❌ If it says "No foods in this category yet!":
- The doFoods list is empty
- Go back to Step 8 and check the logs
- The filtering is failing

## Step 11: Test Meal Log
1. Go to Meal Log (bottom navigation)
2. Type "apple" in search
3. You should see "TestApple"

### ❌ If "Food Not Found":
- The nameLower field is missing or wrong
- Check Step 7 logs - look for "nameLower: testapple"
- If missing, delete food and re-add

## What to Send Me If Still Not Working

Copy and paste ALL of these from your console:

1. **Save logs** (from Step 5)
2. **Manual Firestore check** (from Step 7)
3. **Automatic debug logs** (from Step 8)
4. **Any error messages** (red text in console)

Also send:
5. Screenshot of your dashboard showing "0 foods"
6. Screenshot of Firebase Console → Firestore → food_rules collection
7. Screenshot of Firebase Console → Firestore → users → [your user id]

## Quick Fixes for Common Issues

### Issue: "permission-denied" error
**Fix:** Go to Firebase Console → Firestore → Rules
Add this rule:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /food_rules/{document=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### Issue: diabetesType is "Loading..." forever
**Fix:** 
1. Check internet connection
2. Check Firebase Console → users collection exists
3. Check your user document has diabetesType field
4. Try logging out and back in

### Issue: Food saves but doesn't show
**Fix:**
1. Check if diabetesType matches exactly (case-sensitive)
2. Check if suitableFor array contains your type
3. Try deleting the food and re-adding
4. Try hot restart (press 'R' in terminal)

### Issue: StreamBuilder not updating
**Fix:**
1. Hot restart (press 'R' in terminal)
2. Or fully stop and restart app
3. Check if you have internet connection
4. Check Firebase Console to verify data is there
