/**
 * OAuth Cloud Functions
 *
 * Handles Twitter and GitHub OAuth 2.0 with PKCE flow.
 * Stores temporary state in Firestore and exchanges tokens server-side.
 */

import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {
  db,
  auth,
  reserveUsername,
  generateUniqueUsername,
  setCustomClaims,
  isAutoAdmin,
} from "./utils";

// Define secrets (set via Firebase CLI: firebase functions:secrets:set)
const TWITTER_CLIENT_ID = defineSecret("TWITTER_CLIENT_ID");
const TWITTER_CLIENT_SECRET = defineSecret("TWITTER_CLIENT_SECRET");
const GITHUB_CLIENT_ID = defineSecret("GITHUB_CLIENT_ID");
const GITHUB_CLIENT_SECRET = defineSecret("GITHUB_CLIENT_SECRET");

// OAuth state TTL (5 minutes)
const STATE_TTL_MS = 5 * 60 * 1000;

/**
 * Generate PKCE code verifier
 */
function generateCodeVerifier(): string {
  return crypto.randomBytes(32).toString("base64url");
}

/**
 * Generate PKCE code challenge from verifier
 */
function generateCodeChallenge(verifier: string): string {
  return crypto.createHash("sha256").update(verifier).digest("base64url");
}

/**
 * Generate random state for CSRF protection
 */
function generateState(): string {
  return crypto.randomBytes(16).toString("hex");
}

// ============================================
// TWITTER OAUTH
// ============================================

/**
 * Initialize Twitter OAuth flow
 * Returns auth URL and stores PKCE state in Firestore
 */
export const twitterOAuthInit = onCall(
  {
    enforceAppCheck: false,
    secrets: [TWITTER_CLIENT_ID],
  },
  async () => {
    const clientId = TWITTER_CLIENT_ID.value();

    if (!clientId) {
      throw new HttpsError("failed-precondition", "Twitter OAuth not configured");
    }

    const state = generateState();
    const codeVerifier = generateCodeVerifier();
    const codeChallenge = generateCodeChallenge(codeVerifier);

    // Store state in Firestore with TTL
    await db.doc(`oauth_state/${state}`).set({
      provider: "twitter",
      codeVerifier,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + STATE_TTL_MS),
    });

    // Build Twitter OAuth URL
    const params = new URLSearchParams({
      response_type: "code",
      client_id: clientId,
      redirect_uri: "karass://callback",
      scope: "tweet.read users.read offline.access",
      state: state,
      code_challenge: codeChallenge,
      code_challenge_method: "S256",
    });

    const authUrl = `https://twitter.com/i/oauth2/authorize?${params.toString()}`;

    return {
      success: true,
      authUrl,
      state,
      codeVerifier, // Client needs this for callback
    };
  }
);

/**
 * Complete Twitter OAuth callback
 * Exchanges code for token and creates/finds user
 */
export const twitterOAuthCallback = onCall(
  {
    enforceAppCheck: false,
    secrets: [TWITTER_CLIENT_ID, TWITTER_CLIENT_SECRET],
  },
  async (request) => {
    const { code, state, codeVerifier } = request.data;

    if (!code || !state || !codeVerifier) {
      throw new HttpsError("invalid-argument", "Missing required parameters");
    }

    const clientId = TWITTER_CLIENT_ID.value();
    const clientSecret = TWITTER_CLIENT_SECRET.value();

    if (!clientId || !clientSecret) {
      throw new HttpsError("failed-precondition", "Twitter OAuth not configured");
    }

    try {
      // Verify state exists and hasn't expired
      const stateDoc = await db.doc(`oauth_state/${state}`).get();

      if (!stateDoc.exists) {
        throw new HttpsError("invalid-argument", "Invalid or expired state");
      }

      const stateData = stateDoc.data()!;

      if (stateData.provider !== "twitter") {
        throw new HttpsError("invalid-argument", "State mismatch");
      }

      // Delete state document (one-time use)
      await db.doc(`oauth_state/${state}`).delete();

      // Exchange code for access token
      const tokenResponse = await fetch("https://api.twitter.com/2/oauth2/token", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`,
        },
        body: new URLSearchParams({
          code,
          grant_type: "authorization_code",
          redirect_uri: "karass://callback",
          code_verifier: codeVerifier,
        }),
      });

      if (!tokenResponse.ok) {
        const error = await tokenResponse.text();
        console.error("Twitter token error:", error);
        throw new HttpsError("internal", "Failed to exchange code for token");
      }

      const tokenData = await tokenResponse.json();
      const accessToken = tokenData.access_token;

      // Fetch Twitter user profile
      const userResponse = await fetch(
        "https://api.twitter.com/2/users/me?user.fields=id,name,username,profile_image_url",
        {
          headers: {
            Authorization: `Bearer ${accessToken}`,
          },
        }
      );

      if (!userResponse.ok) {
        throw new HttpsError("internal", "Failed to fetch Twitter profile");
      }

      const twitterUser = (await userResponse.json()).data;
      const twitterId = twitterUser.id;
      const twitterHandle = `@${twitterUser.username}`;

      // Check if user exists with this Twitter ID
      const existingUserQuery = await db
        .collection("users")
        .where("twitterId", "==", twitterId)
        .limit(1)
        .get();

      let userId: string;
      let isNewUser = false;
      let userData;

      if (!existingUserQuery.empty) {
        // Existing user - sign them in
        const existingDoc = existingUserQuery.docs[0];
        userId = existingDoc.id;
        userData = existingDoc.data();
      } else {
        // New user - create account
        isNewUser = true;

        // Generate unique username from Twitter handle
        const username = await generateUniqueUsername(twitterUser.username);

        // Create Firebase Auth user (no password for OAuth users)
        const userRecord = await auth.createUser({
          displayName: username,
        });

        userId = userRecord.uid;

        // Reserve username
        await reserveUsername(username, userId);

        // Set custom claims
        await setCustomClaims(userId, {
          isAdmin: false,
          isApproved: true,
        });

        // Create user document
        userData = {
          email: null,
          username,
          twitterHandle,
          twitterId,
          githubHandle: null,
          githubId: null,
          authProvider: "twitter",
          isApproved: true,
          isAdmin: false,
          fcmToken: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.doc(`users/${userId}`).set(userData);
      }

      // Generate custom token for sign-in
      const customToken = await auth.createCustomToken(userId);

      return {
        success: true,
        message: isNewUser ? "Account created" : "Login successful",
        token: customToken,
        isNewUser,
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
      console.error("Twitter OAuth callback error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Twitter authentication failed");
    }
  }
);

// ============================================
// GITHUB OAUTH
// ============================================

/**
 * Initialize GitHub OAuth flow
 */
export const githubOAuthInit = onCall(
  {
    enforceAppCheck: false,
    secrets: [GITHUB_CLIENT_ID],
  },
  async () => {
    const clientId = GITHUB_CLIENT_ID.value();

    if (!clientId) {
      throw new HttpsError("failed-precondition", "GitHub OAuth not configured");
    }

    const state = generateState();
    const codeVerifier = generateCodeVerifier();

    // Store state in Firestore
    await db.doc(`oauth_state/${state}`).set({
      provider: "github",
      codeVerifier,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + STATE_TTL_MS),
    });

    // Build GitHub OAuth URL
    const params = new URLSearchParams({
      client_id: clientId,
      redirect_uri: "karass://callback",
      scope: "read:user user:email",
      state: state,
    });

    const authUrl = `https://github.com/login/oauth/authorize?${params.toString()}`;

    return {
      success: true,
      authUrl,
      state,
      codeVerifier,
    };
  }
);

/**
 * GitHub web callback handler (for redirect flow)
 */
export const githubWebCallback = onRequest(
  {
    secrets: [GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET],
  },
  async (req, res) => {
    const { code, state } = req.query;

    if (!code || !state) {
      res.status(400).send("Missing code or state");
      return;
    }

    // Validate that code and state only contain safe characters (alphanumeric, hyphen, underscore)
    const safePattern = /^[a-zA-Z0-9_-]+$/;
    if (!safePattern.test(String(code)) || !safePattern.test(String(state))) {
      res.status(400).send("Invalid code or state format");
      return;
    }

    // URL-encode parameters for safety
    const encodedCode = encodeURIComponent(String(code));
    const encodedState = encodeURIComponent(String(state));

    // Redirect to mobile app with code and state
    const redirectUrl = `karass://callback?code=${encodedCode}&state=${encodedState}`;

    // Send HTML that redirects to the app (using safe encoded values)
    res.send(`<!DOCTYPE html>
<html>
<head>
<title>Redirecting...</title>
<meta http-equiv="refresh" content="0;url=${redirectUrl}">
</head>
<body>
<p>Redirecting to Karass app...</p>
<p><a href="${redirectUrl}">Click here if not redirected</a></p>
<script>window.location.href = ${JSON.stringify(redirectUrl)};</script>
</body>
</html>`);
  }
);

/**
 * Complete GitHub OAuth callback
 */
export const githubOAuthCallback = onCall(
  {
    enforceAppCheck: false,
    secrets: [GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET],
  },
  async (request) => {
    const { code, state } = request.data;

    if (!code || !state) {
      throw new HttpsError("invalid-argument", "Missing required parameters");
    }

    const clientId = GITHUB_CLIENT_ID.value();
    const clientSecret = GITHUB_CLIENT_SECRET.value();

    if (!clientId || !clientSecret) {
      throw new HttpsError("failed-precondition", "GitHub OAuth not configured");
    }

    try {
      // Verify state
      const stateDoc = await db.doc(`oauth_state/${state}`).get();

      if (!stateDoc.exists) {
        throw new HttpsError("invalid-argument", "Invalid or expired state");
      }

      const stateData = stateDoc.data()!;

      if (stateData.provider !== "github") {
        throw new HttpsError("invalid-argument", "State mismatch");
      }

      // Delete state document
      await db.doc(`oauth_state/${state}`).delete();

      // Exchange code for access token
      const tokenResponse = await fetch(
        "https://github.com/login/oauth/access_token",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Accept: "application/json",
          },
          body: JSON.stringify({
            client_id: clientId,
            client_secret: clientSecret,
            code,
            redirect_uri: "karass://callback",
          }),
        }
      );

      const tokenData = await tokenResponse.json();

      if (tokenData.error) {
        console.error("GitHub token error:", tokenData);
        throw new HttpsError("internal", "Failed to exchange code for token");
      }

      const accessToken = tokenData.access_token;

      // Fetch GitHub user profile
      const userResponse = await fetch("https://api.github.com/user", {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: "application/vnd.github.v3+json",
        },
      });

      if (!userResponse.ok) {
        throw new HttpsError("internal", "Failed to fetch GitHub profile");
      }

      const githubUser = await userResponse.json();
      const githubId = String(githubUser.id);
      const githubHandle = `@${githubUser.login}`;

      // Fetch email (may be private)
      let email = githubUser.email;

      if (!email) {
        const emailResponse = await fetch("https://api.github.com/user/emails", {
          headers: {
            Authorization: `Bearer ${accessToken}`,
            Accept: "application/vnd.github.v3+json",
          },
        });

        if (emailResponse.ok) {
          const emails = await emailResponse.json();
          const primaryEmail = emails.find(
            (e: { primary: boolean; verified: boolean; email: string }) =>
              e.primary && e.verified
          );
          email = primaryEmail?.email || null;
        }
      }

      // Check if user exists with this GitHub ID
      const existingUserQuery = await db
        .collection("users")
        .where("githubId", "==", githubId)
        .limit(1)
        .get();

      let userId: string;
      let isNewUser = false;
      let userData;

      if (!existingUserQuery.empty) {
        // Existing user
        const existingDoc = existingUserQuery.docs[0];
        userId = existingDoc.id;
        userData = existingDoc.data();
      } else {
        // New user
        isNewUser = true;

        // Generate unique username
        const username = await generateUniqueUsername(githubUser.login);

        // Determine if auto-admin
        const shouldBeAdmin = email ? isAutoAdmin(email) : false;

        // Create Firebase Auth user
        const createUserData: admin.auth.CreateRequest = {
          displayName: username,
        };

        if (email) {
          createUserData.email = email;
        }

        const userRecord = await auth.createUser(createUserData);
        userId = userRecord.uid;

        // Reserve username
        await reserveUsername(username, userId);

        // Set custom claims
        await setCustomClaims(userId, {
          isAdmin: shouldBeAdmin,
          isApproved: true,
        });

        // Create user document
        userData = {
          email: email || null,
          username,
          twitterHandle: null,
          twitterId: null,
          githubHandle,
          githubId,
          authProvider: "github",
          isApproved: true,
          isAdmin: shouldBeAdmin,
          fcmToken: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        await db.doc(`users/${userId}`).set(userData);
      }

      // Generate custom token
      const customToken = await auth.createCustomToken(userId);

      return {
        success: true,
        message: isNewUser ? "Account created" : "Login successful",
        token: customToken,
        isNewUser,
        user: {
          id: userId,
          email: userData.email,
          username: userData.username,
          githubHandle: userData.githubHandle,
          isApproved: userData.isApproved,
          isAdmin: userData.isAdmin,
        },
      };
    } catch (error) {
      console.error("GitHub OAuth callback error:", error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "GitHub authentication failed");
    }
  }
);
