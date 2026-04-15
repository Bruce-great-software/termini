const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

function toInt(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const parsed = parseInt(String(value ?? "0"), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function asNonEmptyString(value) {
  const text = String(value ?? "").trim();
  return text.length > 0 ? text : "";
}

function isPendingEventInvite(eventData, userId) {
  if (!eventData || !userId) return false;

  const createdBy = asNonEmptyString(eventData.createdBy);
  const invitedUserIds = Array.isArray(eventData.invitedUserIds)
    ? eventData.invitedUserIds
    : [];
  const acceptedUserIds = Array.isArray(eventData.acceptedUserIds)
    ? eventData.acceptedUserIds
    : [];
  const maybeUserIds = Array.isArray(eventData.maybeUserIds)
    ? eventData.maybeUserIds
    : [];
  const declinedUserIds = Array.isArray(eventData.declinedUserIds)
    ? eventData.declinedUserIds
    : [];

  if (createdBy === userId) return false;
  if (!invitedUserIds.includes(userId)) return false;
  if (acceptedUserIds.includes(userId)) return false;
  if (maybeUserIds.includes(userId)) return false;
  if (declinedUserIds.includes(userId)) return false;
  return true;
}

async function getUserTokens(userId) {
  const tokens = new Set();

  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();
  const userData = userSnap.data() || {};

  const legacyToken = asNonEmptyString(userData.fcmToken);
  if (legacyToken) tokens.add(legacyToken);

  const deviceSnaps = await userRef.collection("devices").get();
  for (const deviceDoc of deviceSnaps.docs) {
    const data = deviceDoc.data() || {};
    if (data.enabled === false) continue;
    const token = asNonEmptyString(data.token || deviceDoc.id);
    if (token) tokens.add(token);
  }

  return Array.from(tokens);
}

async function cleanupInvalidTokens(userId, sentTokens, responses) {
  const userRef = db.collection("users").doc(userId);
  const invalidCodes = new Set([
    "messaging/registration-token-not-registered",
    "messaging/invalid-registration-token",
  ]);

  const deleteOps = [];

  responses.forEach((response, index) => {
    if (response.success) return;

    const code = response.error?.code || "";
    if (!invalidCodes.has(code)) return;

    const token = sentTokens[index];
    if (!token) return;

    deleteOps.push(userRef.collection("devices").doc(token).delete().catch(() => null));
    deleteOps.push(
      userRef
        .set(
          {
            fcmToken:
              admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        )
        .catch(() => null)
    );
  });

  if (deleteOps.length > 0) {
    await Promise.all(deleteOps);
  }
}

async function recomputeAndPersistBadgeCount(userId) {
  let unreadAppointments = 0;

  const threadSnap = await db
    .collection("contact_threads")
    .where(`participantMap.${userId}`, "==", true)
    .get();

  for (const doc of threadSnap.docs) {
    const data = doc.data() || {};
    if (data[`hiddenFor_${userId}`] === true) continue;
    unreadAppointments += toInt(data[`unreadCountFor_${userId}`]);
  }

  let pendingInvites = 0;

  const eventSnap = await db
    .collection("events")
    .where("invitedUserIds", "array-contains", userId)
    .get();

  for (const doc of eventSnap.docs) {
    if (isPendingEventInvite(doc.data() || {}, userId)) {
      pendingInvites += 1;
    }
  }

  const badgeCount = unreadAppointments + pendingInvites;

  await db.collection("users").doc(userId).set(
    {
      badgeCount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return badgeCount;
}

function sanitizeDataPayload(payload) {
  const result = {};

  for (const [key, value] of Object.entries(payload || {})) {
    if (!key) continue;
    result[key] = String(value ?? "");
  }

  return result;
}

async function sendPushToUser({
  userId,
  title,
  body,
  type,
  route,
  badgeCount,
  data,
}) {
  const tokens = await getUserTokens(userId);
  if (tokens.length === 0) return;

  const payloadData = sanitizeDataPayload({
    type,
    route,
    title,
    body,
    badgeCount,
    ...data,
  });

  const message = {
    tokens,
    notification: {
      title,
      body,
    },
    data: payloadData,
    android: {
      priority: "high",
      notification: {
        channelId: "checkmytime_general",
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          sound: "default",
          badge: Math.max(0, toInt(badgeCount)),
        },
      },
    },
  };

  const response = await admin.messaging().sendEachForMulticast(message);
  await cleanupInvalidTokens(userId, tokens, response.responses || []);
}

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

exports.onContactThreadWritten = onDocumentWritten(
  "contact_threads/{threadId}",
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) return;

    const afterData = afterSnap.data() || {};
    const beforeData = event.data?.before?.exists ? event.data.before.data() || {} : {};

    const participants = Array.isArray(afterData.participants)
      ? afterData.participants.map((value) => asNonEmptyString(value)).filter(Boolean)
      : [];

    const participantMap = afterData.participantMap || {};
    for (const userId of Object.keys(participantMap)) {
      const normalized = asNonEmptyString(userId);
      if (normalized && !participants.includes(normalized)) {
        participants.push(normalized);
      }
    }

    for (const userId of participants) {
      if (afterData[`hiddenFor_${userId}`] === true) continue;

      const oldUnreadCount = toInt(beforeData[`unreadCountFor_${userId}`]);
      const newUnreadCount = toInt(afterData[`unreadCountFor_${userId}`]);

      if (newUnreadCount <= oldUnreadCount) continue;

      // Only send push for appointment interactions. Chat messages are handled
    // by the notification_requests queue via NotificationDispatchService.
    const interactionType = asNonEmptyString(afterData.lastInteractionType);
    if (interactionType !== "appointment") continue;

      const senderId = participants.find((candidate) => candidate !== userId) || "";
      const contactNames = afterData.contactNames || {};
      const senderName = asNonEmptyString(contactNames[senderId]) || "Jemand";
      const appointmentTitle = asNonEmptyString(afterData.lastAppointmentTitle) || "Termin";

      const badgeCount = await recomputeAndPersistBadgeCount(userId);

      await sendPushToUser({
        userId,
        title: "Neuer Terminvorschlag",
        body: `${senderName}: ${appointmentTitle}`,
        type: "appointment",
        route: "appointments",
        badgeCount,
        data: {
          threadId: event.params.threadId,
          contactId: senderId,
          contactName: senderName,
        },
      });
    }
  }
);

exports.onEventWritten = onDocumentWritten("events/{eventId}", async (event) => {
  const afterSnap = event.data?.after;
  if (!afterSnap?.exists) return;

  const afterData = afterSnap.data() || {};
  const beforeData = event.data?.before?.exists ? event.data.before.data() || {} : {};

  const beforeInvited = Array.isArray(beforeData.invitedUserIds)
    ? beforeData.invitedUserIds
    : [];
  const afterInvited = Array.isArray(afterData.invitedUserIds)
    ? afterData.invitedUserIds
    : [];

  const affectedUsers = new Set([...beforeInvited, ...afterInvited]);

  for (const rawUserId of affectedUsers) {
    const userId = asNonEmptyString(rawUserId);
    if (!userId) continue;

    const wasPending = isPendingEventInvite(beforeData, userId);
    const isPendingNow = isPendingEventInvite(afterData, userId);

    if (wasPending || !isPendingNow) continue;

    const creatorName = asNonEmptyString(afterData.createdByName) || "Jemand";
    const eventTitle = asNonEmptyString(afterData.title) || "Event";

    const badgeCount = await recomputeAndPersistBadgeCount(userId);

    await sendPushToUser({
      userId,
      title: "Neue Event-Einladung",
      body: `${creatorName}: ${eventTitle}`,
      type: "event_invite",
      route: "event_detail",
      badgeCount,
      data: {
        eventId: event.params.eventId,
      },
    });
  }
});

// Processes all notification_requests queued by NotificationDispatchService.
// Covers: event join requests, responses, removals, updates, deletions,
// direct joins, invite decisions, and chat messages.
exports.onNotificationRequestCreated = onDocumentCreated(
  "notification_requests/{docId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const requestData = snap.data() || {};
    if (requestData.status !== "pending") return;

    const recipientUserId = asNonEmptyString(requestData.recipientUserId);
    const title = asNonEmptyString(requestData.title);
    const body = asNonEmptyString(requestData.body);
    const channelId = asNonEmptyString(requestData.channelId) || "checkmytime_general";
    const notifData = requestData.data || {};

    if (!recipientUserId || !title || !body) {
      await snap.ref.update({
        status: "failed",
        error: "missing required fields",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const tokens = await getUserTokens(recipientUserId);
    if (tokens.length === 0) {
      await snap.ref.update({
        status: "no_tokens",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const badgeCount = await recomputeAndPersistBadgeCount(recipientUserId);

    const payloadData = sanitizeDataPayload({
      ...notifData,
      title,
      body,
      badgeCount: String(badgeCount),
    });

    const message = {
      tokens,
      notification: { title, body },
      data: payloadData,
      android: {
        priority: "high",
        notification: {
          channelId,
          sound: "default",
        },
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: {
          aps: {
            sound: "default",
            badge: Math.max(0, toInt(badgeCount)),
          },
        },
      },
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      await cleanupInvalidTokens(recipientUserId, tokens, response.responses || []);
      await snap.ref.update({
        status: "sent",
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      console.error("onNotificationRequestCreated failed:", err);
      await snap.ref.update({
        status: "failed",
        error: String(err?.message || err),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);
