const functions = require("firebase-functions");
const admin = require("firebase-admin");
const fetch = require("node-fetch");
admin.initializeApp();

// ──────────────────────────────────────────────────────────────────
// SECURE: Identify food with Gemini Vision API (API key in Cloud)
// ──────────────────────────────────────────────────────────────────
exports.identifyFoodWithGemini = functions.https.onCall(async (data, context) => {
  const { imageBase64 } = data;
  
  if (!imageBase64) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'imageBase64 is required'
    );
  }

  try {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      console.error("GEMINI_API_KEY not set in environment");
      throw new functions.https.HttpsError(
        'internal',
        'API key not configured'
      );
    }

    const geminiModel = 'gemini-2.5-flash';
    const prompt = `
Look at this image and identify the food item.

Reply with ONLY a JSON object, no extra text:
{"food": "food name here", "is_food": true}

If there is NO food in the image:
{"food": "", "is_food": false}

Rules:
- Use simple common names (e.g. "white rice", "fried chicken", "apple")
- Lowercase only
- If multiple foods, name the main/dominant one
`;

    const url = `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent?key=${apiKey}`;

    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                inline_data: {
                  mime_type: 'image/jpeg',
                  data: imageBase64,
                },
              },
              { text: prompt },
            ],
          }
        ],
        generationConfig: {
          maxOutputTokens: 100,
          temperature: 0.1,
        },
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      console.error(`Gemini API error ${response.status}:`, error);
      throw new functions.https.HttpsError(
        'internal',
        `Gemini API error: ${response.status}`
      );
    }

    const decoded = await response.json();
    const text = decoded?.candidates?.[0]?.content?.parts?.[0]?.text;
    
    if (!text) {
      throw new functions.https.HttpsError(
        'internal',
        'No response from Gemini'
      );
    }

    const raw = text
      .trim()
      .replace(/^```json\s*/gm, '')
      .replace(/^```\s*/gm, '')
      .replace(/```$/gm, '')
      .trim();

    const parsed = JSON.parse(raw);
    if (parsed.is_food === false) {
      return { success: true, food: null, isFood: false };
    }

    return {
      success: true,
      food: (parsed.food || '').trim(),
      isFood: true,
    };
  } catch (error) {
    console.error('Gemini identification error:', error);
    throw new functions.https.HttpsError(
      'internal',
      error.message || 'Failed to identify food'
    );
  }
});

// ──────────────────────────────────────────────────────────────────
// deleteAuthUser — your existing function (kept as-is)
// ──────────────────────────────────────────────────────────────────
exports.deleteAuthUser = functions.https.onCall(async (data, context) => {
  const uid = data.uid;

  try {
    await admin.auth().deleteUser(uid);
    console.log(`Deleted user: ${uid}`);

    await admin.firestore().collection('users').doc(uid).delete();
    console.log(`Deleted user document: ${uid}`);

    return { success: true, message: "User deleted successfully" };
  } catch (error) {
    console.error("Error deleting user:", error);
    return { success: false, message: error.message };
  }
});

// ──────────────────────────────────────────────────────────────────
// deleteUser — called by ADMIN to delete any user
// Verifies caller is admin, then deletes Auth + all Firestore data
// Flutter: FirebaseFunctions.instance.httpsCallable('deleteUser')
//            .call({'uid': targetUid})
// ──────────────────────────────────────────────────────────────────
exports.deleteUser = functions.https.onCall(async (data, context) => {
  // Must be logged in
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'You must be logged in to perform this action.'
    );
  }

  // Caller must be an admin
  const callerUid = context.auth.uid;
  const adminDoc  = await admin.firestore().collection('users').doc(callerUid).get();
  if (!adminDoc.exists || adminDoc.data().role !== 'admin') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only admins can delete user accounts.'
    );
  }

  const targetUid = data.uid;
  if (!targetUid) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Missing uid parameter.'
    );
  }

  try {
    // Delete sub-collections
    const db = admin.firestore();
    const subCollections = ['foodLogs', 'mealLogs', 'scannedFoods'];
    for (const sub of subCollections) {
      const snap = await db.collection('users').doc(targetUid).collection(sub).get();
      if (!snap.empty) {
        const batch = db.batch();
        snap.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();
      }
    }

    // Delete Firestore user document
    await db.collection('users').doc(targetUid).delete();

    // Delete from Firebase Authentication
    await admin.auth().deleteUser(targetUid);

    console.log(`✅ Admin ${callerUid} deleted user ${targetUid}`);
    return { success: true, message: 'User deleted successfully.' };

  } catch (err) {
    console.error('❌ deleteUser error:', err);
    throw new functions.https.HttpsError('internal', err.message);
  }
});

// ──────────────────────────────────────────────────────────────────
// deleteOwnAccount — called by the USER themselves
// Deletes their own Auth account + all their Firestore data
// Flutter: FirebaseFunctions.instance
//            .httpsCallable('deleteOwnAccount').call()
// ──────────────────────────────────────────────────────────────────
exports.deleteOwnAccount = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'You must be logged in to delete your account.'
    );
  }

  const uid = context.auth.uid;

  try {
    const db = admin.firestore();

    // Delete sub-collections
    const subCollections = ['foodLogs', 'mealLogs', 'scannedFoods'];
    for (const sub of subCollections) {
      const snap = await db.collection('users').doc(uid).collection(sub).get();
      if (!snap.empty) {
        const batch = db.batch();
        snap.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();
      }
    }

    // Delete Firestore document
    await db.collection('users').doc(uid).delete();

    // Delete from Firebase Auth
    await admin.auth().deleteUser(uid);

    console.log(`✅ User ${uid} deleted their own account.`);
    return { success: true };

  } catch (err) {
    console.error('❌ deleteOwnAccount error:', err);
    throw new functions.https.HttpsError('internal', err.message);
  }
});