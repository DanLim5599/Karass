/**
 * Karass Firebase Cloud Functions
 *
 * This is the main entry point that exports all Cloud Functions.
 */

import * as admin from "firebase-admin";

// Initialize Firebase Admin SDK
admin.initializeApp();

// Export all functions
export * from "./auth";
export * from "./oauth";
export * from "./admin";
export * from "./beacon";
export * from "./announcements";
