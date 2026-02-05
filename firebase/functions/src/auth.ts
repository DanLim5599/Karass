/**
 * Authentication Cloud Functions
 *
 * Handles user registration and login with email/password.
 * Uses Firebase Auth for user management and Firestore for profile data.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
  db,
  auth,
  isValidEmail,
  isValidUsername,
  isValidPassword,
  sanitize,
  reserveUsername,
  setCustomClaims,
  isAutoAdmin,
} from "./utils";

/**
 * Register a new user with email and password
 */
export const register = onCall(
  { enforceAppCheck: false }, // Enable in production
  async (request) => {
    const { email, username, password, twitterHandle } = request.data;

    // Validate inputs
    if (!email || !isValidEmail(email)) {
      throw new HttpsError("invalid-argument", "Invalid email address");
    }

    if (!username || !isValidUsername(username)) {
      throw new HttpsError(
        "invalid-argument",
        "Username must be 3-30 characters, alphanumeric and underscores only"
      );
    }

    if (!password || !isValidPassword(password)) {
      throw new HttpsError(
        "invalid-argument",
        "Password must be at least 6 characters"
      );
    }

    const sanitizedEmail = sanitize(email).toLowerCase();
    const sanitizedUsername = sanitize(username);
    const sanitizedTwitter = twitterHandle ? sanitize(twitterHandle) : null;

    try {
      // Check if email already exists in Firebase Auth
      try {
        await auth.getUserByEmail(sanitizedEmail);
        throw new HttpsError("already-exists", "Email is already registered");
      } catch (error: unknown) {
        // User not found is expected - continue
        if ((error as { code?: string }).code !== "auth/user-not-found") {
          if (error instanceof HttpsError) throw error;
        }
      }

      // Reserve username atomically
      // First create Firebase Auth user to get UID
      const userRecord = await auth.createUser({
        email: sanitizedEmail,
        password: password,
        displayName: sanitizedUsername,
      });

      const userId = userRecord.uid;

      try {
        // Reserve username
        await reserveUsername(sanitizedUsername, userId);
      } catch (error) {
        // Rollback: delete the auth user if username reservation fails
        await auth.deleteUser(userId);
        throw error;
      }

      // Determine if auto-admin
      const shouldBeAdmin = isAutoAdmin(sanitizedEmail);

      // Set custom claims
      await setCustomClaims(userId, {
        isAdmin: shouldBeAdmin,
        isApproved: true, // Auto-approve for now
      });

      // Create user document in Firestore
      const userData = {
        email: sanitizedEmail,
        username: sanitizedUsername,
        twitterHandle: sanitizedTwitter,
        authProvider: "email",
        isApproved: true,
        isAdmin: shouldBeAdmin,
        fcmToken: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db.doc(`users/${userId}`).set(userData);

      // Generate custom token for immediate sign-in
      const customToken = await auth.createCustomToken(userId);

      return {
        success: true,
        message: "Account created successfully",
        token: customToken,
        user: {
          id: userId,
          email: sanitizedEmail,
          username: sanitizedUsername,
          twitterHandle: sanitizedTwitter,
          isApproved: true,
          isAdmin: shouldBeAdmin,
        },
      };
    } catch (error) {
      console.error("Registration error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Failed to create account");
    }
  }
);

/**
 * Login with email/username and password
 *
 * Verifies credentials using Firebase Auth REST API and returns a custom token.
 */
export const login = onCall(
  { enforceAppCheck: false }, // Enable in production
  async (request) => {
    const { emailOrUsername, password } = request.data;

    if (!emailOrUsername || !password) {
      throw new HttpsError("invalid-argument", "Email/username and password are required");
    }

    const sanitizedInput = sanitize(emailOrUsername).toLowerCase();

    try {
      let userEmail: string;
      let userId: string;

      // Try to find user by email first
      if (isValidEmail(sanitizedInput)) {
        try {
          const userRecord = await auth.getUserByEmail(sanitizedInput);
          userId = userRecord.uid;
          userEmail = sanitizedInput;
        } catch {
          throw new HttpsError("not-found", "Invalid email or password");
        }
      } else {
        // Find by username
        const usernameDoc = await db.doc(`usernames/${sanitizedInput}`).get();
        if (!usernameDoc.exists) {
          throw new HttpsError("not-found", "Invalid username or password");
        }
        userId = usernameDoc.data()?.userId;
        const userRecord = await auth.getUser(userId);
        if (!userRecord.email) {
          throw new HttpsError("not-found", "User has no email for authentication");
        }
        userEmail = userRecord.email;
      }

      // Verify password using Firebase Auth REST API
      const apiKey = process.env.FIREBASE_API_KEY;
      if (!apiKey) {
        console.error("FIREBASE_API_KEY not configured");
        throw new HttpsError("internal", "Server configuration error");
      }

      const verifyResponse = await fetch(
        `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            email: userEmail,
            password: password,
            returnSecureToken: false,
          }),
        }
      );

      if (!verifyResponse.ok) {
        const errorData = await verifyResponse.json();
        console.error("Password verification failed:", errorData.error?.message);
        throw new HttpsError("not-found", "Invalid email or password");
      }

      // Get user document for additional data
      const userDoc = await db.doc(`users/${userId}`).get();
      const userData = userDoc.data();

      if (!userData) {
        throw new HttpsError("not-found", "User profile not found");
      }

      // Generate custom token
      const customToken = await auth.createCustomToken(userId);

      return {
        success: true,
        message: "Login successful",
        token: customToken,
        user: {
          id: userId,
          email: userData.email,
          username: userData.username,
          twitterHandle: userData.twitterHandle,
          isApproved: userData.isApproved,
          isAdmin: userData.isAdmin,
        },
      };
    } catch (error) {
      console.error("Login error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Login failed");
    }
  }
);

/**
 * Get user status (approval and admin status)
 * Users can only query their own status, admins can query anyone
 */
export const getUserStatus = onCall(
  { enforceAppCheck: false },
  async (request) => {
    // Require authentication
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be logged in");
    }

    const { userId } = request.data;
    const requestingUserId = request.auth.uid;

    if (!userId) {
      throw new HttpsError("invalid-argument", "User ID is required");
    }

    try {
      // Users can only check their own status unless they're admin
      if (userId !== requestingUserId) {
        // Check if requesting user is admin
        const requestingUserDoc = await db.doc(`users/${requestingUserId}`).get();
        const requestingUserData = requestingUserDoc.data();

        if (!requestingUserData?.isAdmin) {
          throw new HttpsError("permission-denied", "Cannot access other user's status");
        }
      }

      const userDoc = await db.doc(`users/${userId}`).get();

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User not found");
      }

      const userData = userDoc.data()!;

      return {
        success: true,
        isApproved: userData.isApproved || false,
        isAdmin: userData.isAdmin || false,
      };
    } catch (error) {
      console.error("Get user status error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Failed to get user status");
    }
  }
);

/**
 * Update FCM token for push notifications
 */
export const updateFcmToken = onCall(
  { enforceAppCheck: false },
  async (request) => {
    // Require authentication
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be logged in");
    }

    const { fcmToken } = request.data;
    const userId = request.auth.uid;

    if (!fcmToken) {
      throw new HttpsError("invalid-argument", "FCM token is required");
    }

    try {
      await db.doc(`users/${userId}`).update({
        fcmToken: fcmToken,
      });

      return { success: true };
    } catch (error) {
      console.error("Update FCM token error:", error);
      throw new HttpsError("internal", "Failed to update FCM token");
    }
  }
);
