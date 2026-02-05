const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

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
