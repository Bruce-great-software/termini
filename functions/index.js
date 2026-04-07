const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();

exports.exchangePnvToken = onCall(async (request) => {
  const phoneNumber = (request.data?.phoneNumber || "").trim();

  if (!phoneNumber) {
    throw new HttpsError("invalid-argument", "phoneNumber fehlt.");
  }

  try {
    let userRecord;

    try {
      userRecord = await admin.auth().getUserByPhoneNumber(phoneNumber);
    } catch (error) {
      if (error.code === "auth/user-not-found") {
        userRecord = await admin.auth().createUser({
          phoneNumber: phoneNumber,
        });
      } else {
        throw error;
      }
    }

    const userDocRef = admin.firestore().collection("users").doc(userRecord.uid);
    const userDoc = await userDocRef.get();

    if (!userDoc.exists) {
      await userDocRef.set({
        displayName: "",
        phoneNumber: phoneNumber,
        authProvider: "pnv",
        rolle: "kunde",
        isActive: true,
        profileCompleted: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      await userDocRef.set(
        {
          phoneNumber: phoneNumber,
          authProvider: "pnv",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    const customToken = await admin.auth().createCustomToken(userRecord.uid);

    return {
      customToken,
      uid: userRecord.uid,
    };
  } catch (error) {
    console.error("exchangePnvToken failed:", error);
    throw new HttpsError("internal", "Fehler");
  }
});