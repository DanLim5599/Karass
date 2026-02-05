/**
 * Shared utilities for Cloud Functions
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

// Firestore instance
export const db = admin.firestore();

// Auth instance
export const auth = admin.auth();

// Messaging instance
export const messaging = admin.messaging();

/**
 * Validate email format
 */
export function isValidEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Validate username format (alphanumeric + underscore, 3-30 chars)
 */
export function isValidUsername(username: string): boolean {
  const usernameRegex = /^[a-zA-Z0-9_]{3,30}$/;
  return usernameRegex.test(username);
}

/**
 * Validate password (min 6 characters)
 */
export function isValidPassword(password: string): boolean {
  return password.length >= 6;
}

/**
 * Sanitize input string
 */
export function sanitize(input: string): string {
  return input.trim().replace(/[<>]/g, "");
}

/**
 * Check if a username is already taken
 */
export async function isUsernameTaken(username: string): Promise<boolean> {
  const doc = await db.doc(`usernames/${username.toLowerCase()}`).get();
  return doc.exists;
}

/**
 * Reserve a username atomically
 */
export async function reserveUsername(
  username: string,
  userId: string
): Promise<boolean> {
  const usernameRef = db.doc(`usernames/${username.toLowerCase()}`);

  try {
    await db.runTransaction(async (transaction) => {
      const doc = await transaction.get(usernameRef);
      if (doc.exists) {
        throw new HttpsError("already-exists", "Username is already taken");
      }
      transaction.set(usernameRef, { userId, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    });
    return true;
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "Failed to reserve username");
  }
}

/**
 * Generate a unique username from a base name
 */
export async function generateUniqueUsername(baseName: string): Promise<string> {
  // Clean the base name
  let username = baseName.replace(/[^a-zA-Z0-9_]/g, "").substring(0, 20);

  if (username.length < 3) {
    username = "user";
  }

  // Check if base name is available
  if (!(await isUsernameTaken(username))) {
    return username;
  }

  // Try adding numbers
  for (let i = 1; i < 1000; i++) {
    const candidate = `${username}${i}`;
    if (!(await isUsernameTaken(candidate))) {
      return candidate;
    }
  }

  // Fallback: random suffix
  const random = Math.random().toString(36).substring(2, 8);
  return `${username}_${random}`;
}

/**
 * Set custom claims on a user
 */
export async function setCustomClaims(
  uid: string,
  claims: { isAdmin?: boolean; isApproved?: boolean }
): Promise<void> {
  await auth.setCustomUserClaims(uid, claims);
}

/**
 * Get user document from Firestore
 */
export async function getUserDoc(userId: string) {
  const doc = await db.doc(`users/${userId}`).get();
  return doc.exists ? doc.data() : null;
}

/**
 * Admin emails that get auto-admin status
 */
export function getAdminEmails(): string[] {
  const adminEmailsEnv = process.env.ADMIN_EMAILS || "";
  return adminEmailsEnv.split(",").map((e) => e.trim().toLowerCase()).filter(Boolean);
}

/**
 * Check if email should be auto-admin
 */
export function isAutoAdmin(email: string): boolean {
  const adminEmails = getAdminEmails();
  return adminEmails.includes(email.toLowerCase());
}
