/**
 * Beacon Cloud Functions
 *
 * Handles beacon operations using a single document pattern to avoid
 * expensive batch updates across all users.
 *
 * Beacon data is stored in: app_config/beacon
 * This contains the current beacon user ID and timestamp.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { db, messaging, getUserDoc } from "./utils";

// Beacon document path
const BEACON_DOC = "app_config/beacon";

/**
 * Verify the caller is an admin
 */
async function verifyAdmin(request: { auth?: { uid: string } }): Promise<void> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in");
  }

  const userDoc = await getUserDoc(request.auth.uid);

  if (!userDoc || !userDoc.isAdmin) {
    throw new HttpsError("permission-denied", "Admin access required");
  }
}

/**
 * Get current beacon status
 * Returns the current beacon user if set
 */
export const getBeaconStatus = onCall(
  { enforceAppCheck: false },
  async (request) => {
    // Require authentication
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be logged in");
    }

    try {
      const beaconDoc = await db.doc(BEACON_DOC).get();

      if (!beaconDoc.exists) {
        return {
          success: true,
          hasBeacon: false,
          beacon: null,
        };
      }

      const beaconData = beaconDoc.data()!;

      // If no current beacon user
      if (!beaconData.userId) {
        return {
          success: true,
          hasBeacon: false,
          beacon: null,
        };
      }

      // Get beacon user details
      const userDoc = await db.doc(`users/${beaconData.userId}`).get();

      if (!userDoc.exists) {
        // Beacon user was deleted, clear beacon
        await db.doc(BEACON_DOC).set({
          userId: null,
          setAt: null,
          setBy: null,
        });

        return {
          success: true,
          hasBeacon: false,
          beacon: null,
        };
      }

      const userData = userDoc.data()!;

      return {
        success: true,
        hasBeacon: true,
        beacon: {
          userId: beaconData.userId,
          username: userData.username,
          twitterHandle: userData.twitterHandle,
          githubHandle: userData.githubHandle,
          setAt: beaconData.setAt?.toDate?.()?.toISOString() || null,
        },
      };
    } catch (error) {
      console.error("Get beacon status error:", error);
      throw new HttpsError("internal", "Failed to get beacon status");
    }
  }
);

/**
 * Set a user as the current beacon (admin only)
 */
export const setBeacon = onCall(
  { enforceAppCheck: false },
  async (request) => {
    await verifyAdmin(request);

    const { userId } = request.data;

    if (!userId) {
      throw new HttpsError("invalid-argument", "User ID is required");
    }

    try {
      // Verify target user exists
      const targetUserDoc = await db.doc(`users/${userId}`).get();

      if (!targetUserDoc.exists) {
        throw new HttpsError("not-found", "User not found");
      }

      const targetUser = targetUserDoc.data()!;

      // Set beacon document
      await db.doc(BEACON_DOC).set({
        userId: userId,
        setAt: admin.firestore.FieldValue.serverTimestamp(),
        setBy: request.auth!.uid,
      });

      // Send push notification to all users (except the beacon)
      await sendBeaconNotification(userId, targetUser.username);

      return {
        success: true,
        message: `${targetUser.username} is now the beacon`,
        beacon: {
          userId: userId,
          username: targetUser.username,
          twitterHandle: targetUser.twitterHandle,
          githubHandle: targetUser.githubHandle,
        },
      };
    } catch (error) {
      console.error("Set beacon error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Failed to set beacon");
    }
  }
);

/**
 * Clear the current beacon (admin only)
 */
export const clearBeacon = onCall(
  { enforceAppCheck: false },
  async (request) => {
    await verifyAdmin(request);

    try {
      // Clear beacon document
      await db.doc(BEACON_DOC).set({
        userId: null,
        setAt: null,
        setBy: request.auth!.uid,
        clearedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        message: "Beacon cleared",
      };
    } catch (error) {
      console.error("Clear beacon error:", error);
      throw new HttpsError("internal", "Failed to clear beacon");
    }
  }
);

/**
 * Check if the current user is the beacon
 */
export const amITheBeacon = onCall(
  { enforceAppCheck: false },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be logged in");
    }

    try {
      const beaconDoc = await db.doc(BEACON_DOC).get();

      if (!beaconDoc.exists) {
        return {
          success: true,
          isBeacon: false,
        };
      }

      const beaconData = beaconDoc.data()!;

      return {
        success: true,
        isBeacon: beaconData.userId === request.auth.uid,
      };
    } catch (error) {
      console.error("Am I beacon error:", error);
      throw new HttpsError("internal", "Failed to check beacon status");
    }
  }
);

/**
 * Send push notification about new beacon to all users
 */
async function sendBeaconNotification(
  beaconUserId: string,
  beaconUsername: string
): Promise<void> {
  try {
    // Get all users with FCM tokens (except the beacon user)
    const usersSnapshot = await db
      .collection("users")
      .where("fcmToken", "!=", null)
      .get();

    const tokens: string[] = [];

    usersSnapshot.docs.forEach((doc) => {
      if (doc.id !== beaconUserId && doc.data().fcmToken) {
        tokens.push(doc.data().fcmToken);
      }
    });

    if (tokens.length === 0) {
      console.log("No FCM tokens to send beacon notification");
      return;
    }

    // Send multicast message
    const message = {
      notification: {
        title: "Beacon Alert",
        body: `${beaconUsername} is the beacon! Find them!`,
      },
      data: {
        type: "beacon",
        beaconUserId: beaconUserId,
        beaconUsername: beaconUsername,
      },
      tokens: tokens,
    };

    const response = await messaging.sendEachForMulticast(message);

    console.log(
      `Beacon notification sent: ${response.successCount} success, ${response.failureCount} failures`
    );

    // Clean up invalid tokens
    if (response.failureCount > 0) {
      const invalidTokens: string[] = [];

      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const errorCode = resp.error?.code;
          if (
            errorCode === "messaging/invalid-registration-token" ||
            errorCode === "messaging/registration-token-not-registered"
          ) {
            invalidTokens.push(tokens[idx]);
          }
        }
      });

      // Remove invalid tokens from users
      if (invalidTokens.length > 0) {
        const batch = db.batch();

        for (const token of invalidTokens) {
          const userQuery = await db
            .collection("users")
            .where("fcmToken", "==", token)
            .limit(1)
            .get();

          if (!userQuery.empty) {
            batch.update(userQuery.docs[0].ref, { fcmToken: null });
          }
        }

        await batch.commit();
        console.log(`Cleaned up ${invalidTokens.length} invalid FCM tokens`);
      }
    }
  } catch (error) {
    console.error("Send beacon notification error:", error);
    // Don't throw - notification failure shouldn't fail the beacon operation
  }
}
