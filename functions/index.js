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

    // Strip markdown fences if present
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

exports.deleteAuthUser = functions.https.onCall(async (data, context) => {
  const uid = data.uid;

  try {
    // Delete from Firebase Authentication
    await admin.auth().deleteUser(uid);
    console.log(`Deleted user: ${uid}`);

    // Delete user document from Firestore
    await admin.firestore().collection('users').doc(uid).delete();
    console.log(`Deleted user document: ${uid}`);

    return { success: true, message: "User deleted successfully" };
  } catch (error) {
    console.error("Error deleting user:", error);
    return { success: false, message: error.message };
  }
});
