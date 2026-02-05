/**
 * Announcements Cloud Functions
 *
 * Handles announcement CRUD operations with FCM push notifications.
 * Announcements can have scheduled start/expiry times.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { db, messaging, getUserDoc } from "./utils";

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
 * Create a new announcement (admin only)
 */
export const createAnnouncement = onCall(
  { enforceAppCheck: false },
  async (request) => {
    await verifyAdmin(request);

    const { title, message, imageUrl, startsAt, expiresAt } = request.data;

    if (!message || message.trim() === "") {
      throw new HttpsError("invalid-argument", "Message is required");
    }

    try {
      const announcementData: Record<string, unknown> = {
        title: title || null,
        message: message.trim(),
        imageUrl: imageUrl || null,
        createdBy: request.auth!.uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        startsAt: startsAt ? new Date(startsAt) : null,
        expiresAt: expiresAt ? new Date(expiresAt) : null,
      };

      const docRef = await db.collection("announcements").add(announcementData);

      // Send push notification if announcement is active now
      const now = new Date();
      const startTime = startsAt ? new Date(startsAt) : null;

      if (!startTime || startTime <= now) {
        await sendAnnouncementNotification(title, message);
      }

      return {
        success: true,
        message: "Announcement created",
        announcement: {
          id: docRef.id,
          ...announcementData,
          createdAt: new Date().toISOString(),
          startsAt: startsAt || null,
          expiresAt: expiresAt || null,
        },
      };
    } catch (error) {
      console.error("Create announcement error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Failed to create announcement");
    }
  }
);

/**
 * Get all active announcements
 * Returns announcements that have started and haven't expired
 */
export const getAnnouncements = onCall(
  { enforceAppCheck: false },
  async (request) => {
    // Require authentication
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be logged in");
    }

    try {
      const now = new Date();

      // Query announcements
      // Note: Firestore doesn't support OR queries well, so we'll filter in memory
      const snapshot = await db
        .collection("announcements")
        .orderBy("createdAt", "desc")
        .limit(50)
        .get();

      const announcements = snapshot.docs
        .map((doc) => {
          const data = doc.data();
          return {
            id: doc.id,
            title: data.title,
            message: data.message,
            imageUrl: data.imageUrl,
            createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
            startsAt: data.startsAt?.toDate?.()?.toISOString() || null,
            expiresAt: data.expiresAt?.toDate?.()?.toISOString() || null,
          };
        })
        .filter((announcement) => {
          // Filter: must have started (or no start time)
          if (announcement.startsAt) {
            const startTime = new Date(announcement.startsAt);
            if (startTime > now) return false;
          }

          // Filter: must not have expired (or no expiry)
          if (announcement.expiresAt) {
            const expiryTime = new Date(announcement.expiresAt);
            if (expiryTime < now) return false;
          }

          return true;
        });

      return {
        success: true,
        announcements,
      };
    } catch (error) {
      console.error("Get announcements error:", error);
      throw new HttpsError("internal", "Failed to get announcements");
    }
  }
);

/**
 * Get all announcements including inactive (admin only)
 */
export const getAllAnnouncements = onCall(
  { enforceAppCheck: false },
  async (request) => {
    await verifyAdmin(request);

    try {
      const snapshot = await db
        .collection("announcements")
        .orderBy("createdAt", "desc")
        .limit(100)
        .get();

      const announcements = snapshot.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          title: data.title,
          message: data.message,
          imageUrl: data.imageUrl,
          createdBy: data.createdBy,
          createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
          startsAt: data.startsAt?.toDate?.()?.toISOString() || null,
          expiresAt: data.expiresAt?.toDate?.()?.toISOString() || null,
        };
      });

      return {
        success: true,
        announcements,
      };
    } catch (error) {
      console.error("Get all announcements error:", error);
      throw new HttpsError("internal", "Failed to get announcements");
    }
  }
);

/**
 * Delete an announcement (admin only)
 */
export const deleteAnnouncement = onCall(
  { enforceAppCheck: false },
  async (request) => {
    await verifyAdmin(request);

    const { announcementId } = request.data;

    if (!announcementId) {
      throw new HttpsError("invalid-argument", "Announcement ID is required");
    }

    try {
      const docRef = db.doc(`announcements/${announcementId}`);
      const doc = await docRef.get();

      if (!doc.exists) {
        throw new HttpsError("not-found", "Announcement not found");
      }

      await docRef.delete();

      return {
        success: true,
        message: "Announcement deleted",
      };
    } catch (error) {
      console.error("Delete announcement error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Failed to delete announcement");
    }
  }
);

/**
 * Update an announcement (admin only)
 */
export const updateAnnouncement = onCall(
  { enforceAppCheck: false },
  async (request) => {
    await verifyAdmin(request);

    const { announcementId, title, message, imageUrl, startsAt, expiresAt } =
      request.data;

    if (!announcementId) {
      throw new HttpsError("invalid-argument", "Announcement ID is required");
    }

    try {
      const docRef = db.doc(`announcements/${announcementId}`);
      const doc = await docRef.get();

      if (!doc.exists) {
        throw new HttpsError("not-found", "Announcement not found");
      }

      const updateData: Record<string, unknown> = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (title !== undefined) updateData.title = title;
      if (message !== undefined) updateData.message = message;
      if (imageUrl !== undefined) updateData.imageUrl = imageUrl;
      if (startsAt !== undefined)
        updateData.startsAt = startsAt ? new Date(startsAt) : null;
      if (expiresAt !== undefined)
        updateData.expiresAt = expiresAt ? new Date(expiresAt) : null;

      await docRef.update(updateData);

      // Get updated document
      const updatedDoc = await docRef.get();
      const data = updatedDoc.data()!;

      return {
        success: true,
        message: "Announcement updated",
        announcement: {
          id: announcementId,
          title: data.title,
          message: data.message,
          imageUrl: data.imageUrl,
          createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
          startsAt: data.startsAt?.toDate?.()?.toISOString() || null,
          expiresAt: data.expiresAt?.toDate?.()?.toISOString() || null,
        },
      };
    } catch (error) {
      console.error("Update announcement error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Failed to update announcement");
    }
  }
);

/**
 * Send push notification for new announcement
 */
async function sendAnnouncementNotification(
  title: string | null,
  message: string
): Promise<void> {
  try {
    // Get all users with FCM tokens
    const usersSnapshot = await db
      .collection("users")
      .where("fcmToken", "!=", null)
      .get();

    const tokens: string[] = [];

    usersSnapshot.docs.forEach((doc) => {
      if (doc.data().fcmToken) {
        tokens.push(doc.data().fcmToken);
      }
    });

    if (tokens.length === 0) {
      console.log("No FCM tokens to send announcement notification");
      return;
    }

    // Truncate message for notification
    const truncatedMessage =
      message.length > 100 ? message.substring(0, 97) + "..." : message;

    // Send multicast message
    const notification = {
      notification: {
        title: title || "Karass Announcement",
        body: truncatedMessage,
      },
      data: {
        type: "announcement",
        fullMessage: message,
      },
      tokens: tokens,
    };

    const response = await messaging.sendEachForMulticast(notification);

    console.log(
      `Announcement notification sent: ${response.successCount} success, ${response.failureCount} failures`
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
    console.error("Send announcement notification error:", error);
    // Don't throw - notification failure shouldn't fail the announcement creation
  }
}
