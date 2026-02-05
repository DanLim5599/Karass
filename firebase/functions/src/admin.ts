/**
 * Admin Cloud Functions
 *
 * Handles administrative operations like user approval and admin assignment.
 * All functions require admin privileges.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, auth, setCustomClaims, getUserDoc } from "./utils";

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
 * Approve a user (admin only)
 */
export const approveUser = onCall(
  { enforceAppCheck: false },
  async (request) => {
    await verifyAdmin(request);

    const { userId } = request.data;

    if (!userId) {
      throw new HttpsError("invalid-argument", "User ID is required");
    }

    try {
      // Update Firestore document
      await db.doc(`users/${userId}`).update({
        isApproved: true,
      });

      // Update custom claims
      const currentUser = await auth.getUser(userId);
      const currentClaims = currentUser.customClaims || {};

      await setCustomClaims(userId, {
        ...currentClaims,
        isApproved: true,
      });

      // Get updated user data
      const userDoc = await db.doc(`users/${userId}`).get();
      const userData = userDoc.data()!;

      return {
        success: true,
        message: "User approved",
        user: {
          id: userId,
          email: userData.email,
          username: userData.username,
          isApproved: true,
          isAdmin: userData.isAdmin,
        },
      };
    } catch (error) {
      console.error("Approve user error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Failed to approve user");
    }
  }
);

/**
 * Set a user as admin (admin only)
 */
export const setUserAsAdmin = onCall(
  { enforceAppCheck: false },
  async (request) => {
    await verifyAdmin(request);

    const { userId, isAdmin } = request.data;

    if (!userId) {
      throw new HttpsError("invalid-argument", "User ID is required");
    }

    const makeAdmin = isAdmin !== false; // Default to true

    try {
      // Update Firestore document
      await db.doc(`users/${userId}`).update({
        isAdmin: makeAdmin,
      });

      // Update custom claims
      const currentUser = await auth.getUser(userId);
      const currentClaims = currentUser.customClaims || {};

      await setCustomClaims(userId, {
        ...currentClaims,
        isAdmin: makeAdmin,
      });

      // Get updated user data
      const userDoc = await db.doc(`users/${userId}`).get();
      const userData = userDoc.data()!;

      return {
        success: true,
        message: makeAdmin ? "User is now admin" : "Admin status removed",
        user: {
          id: userId,
          email: userData.email,
          username: userData.username,
          isApproved: userData.isApproved,
          isAdmin: makeAdmin,
        },
      };
    } catch (error) {
      console.error("Set admin error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Failed to update admin status");
    }
  }
);

/**
 * Get all users (admin only)
 */
export const getAllUsers = onCall(
  { enforceAppCheck: false },
  async (request) => {
    await verifyAdmin(request);

    try {
      const usersSnapshot = await db
        .collection("users")
        .orderBy("createdAt", "desc")
        .get();

      const users = usersSnapshot.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          email: data.email,
          username: data.username,
          twitterHandle: data.twitterHandle,
          githubHandle: data.githubHandle,
          isApproved: data.isApproved,
          isAdmin: data.isAdmin,
          createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
        };
      });

      return {
        success: true,
        users,
      };
    } catch (error) {
      console.error("Get all users error:", error);
      throw new HttpsError("internal", "Failed to get users");
    }
  }
);

/**
 * Get pending users awaiting approval (admin only)
 */
export const getPendingUsers = onCall(
  { enforceAppCheck: false },
  async (request) => {
    await verifyAdmin(request);

    try {
      const usersSnapshot = await db
        .collection("users")
        .where("isApproved", "==", false)
        .orderBy("createdAt", "desc")
        .get();

      const users = usersSnapshot.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          email: data.email,
          username: data.username,
          twitterHandle: data.twitterHandle,
          githubHandle: data.githubHandle,
          isApproved: data.isApproved,
          isAdmin: data.isAdmin,
          createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
        };
      });

      return {
        success: true,
        users,
      };
    } catch (error) {
      console.error("Get pending users error:", error);
      throw new HttpsError("internal", "Failed to get pending users");
    }
  }
);
