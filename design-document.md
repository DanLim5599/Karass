# Karass App MVP - Design Document

## Overview

Karass is a proximity-based social app that uses Bluetooth beaconing to connect users who are physically near each other. The app has a mysterious, vibes-based aesthetic with floating ephemeral animations and haptic feedback.

## Core Concept

- Users must physically encounter another Karass user to unlock the app
- Once unlocked (via Bluetooth proximity detection), access is permanent
- The app emphasizes mystery, exclusivity, and real-world connection

## App States

### Stage 1: Splash Screen (Entry)
**Always shown when app opens - the "gimmick"**

- **Visual**: Logo centered on screen with floating, ephemeral animated background
- **Animation**: Procedurally generated particles/shapes that float and fade (NOT gifs)
- **Haptic**: Subtle haptic feedback on app launch
- **Feel**: Beautiful, mysterious, exclusive
- **Duration**: 2-3 seconds before transitioning to appropriate stage
- **Reference aesthetic**: Floating, dreamy, ethereal particles

### Stage 2: Locked State
**Shown when Bluetooth is off OR user has never been in proximity**

- **Visual**: Same layout but muted/darkened colors
- **Content**:
  - If Bluetooth off: "Enable Bluetooth to continue" with clear CTA
  - If not in range/never unlocked: "Find another Karass user to unlock"
- **Goal**: Show gated access clearly without confusion
- **UX**: Clear directions on what user needs to do next

### Stage 3: Proximity Detected (First Unlock)
**Triggered when Bluetooth beacon from another Karass user is detected**

- **Trigger**: App receives any Karass Bluetooth beacon signal
- **Effect**: Permanent unlock stored locally
- **Notification**: Alert user they've been unlocked
- **Sign-up Flow**:
  1. Twitter Login (OAuth)
  2. Email input
  3. Username selection
- **Post sign-up**: Show "Your application is pending approval" notification

### Stage 4: Unlocked (Main App)
**Normal app experience after unlock + sign-up**

- **Layout**:
  - TOP: Karass logo
  - MIDDLE: Notifications area
  - BOTTOM: Beacon status indicator
- **Beaconing**:
  - Tap and hold screen to manually beacon
  - OR: Always beacon when app is open (configurable)
- **Status**: Visual indicator showing if currently beaconing

## Technical Requirements

### Bluetooth
- Use BLE (Bluetooth Low Energy) for beaconing
- Custom service UUID to identify Karass users
- Scan for nearby Karass beacons
- Advertise own presence when beaconing

### Data Persistence
- Store unlock status locally (SharedPreferences)
- Store user credentials securely
- Store pending approval status

### Graphics
- All graphics must be easily replaceable (assets folder)
- All effects must be procedurally generated (CustomPainter/shaders)
- No GIF files for animations

### Haptic Feedback
- Subtle haptic on app launch
- Haptic on beacon detection
- Haptic on tap-and-hold beacon activation

## Data Model

```dart
enum AppState {
  splash,           // Stage 1
  lockedNoBluetooth,// Stage 2a
  lockedNoProximity,// Stage 2b
  proximityDetected,// Stage 3
  signUp,           // Stage 3 continued
  pendingApproval,  // Stage 3 final
  unlocked,         // Stage 4
}

class UserState {
  bool isUnlocked;          // Permanently true once proximity detected
  bool hasCompletedSignUp;
  bool isPendingApproval;
  String? email;
  String? username;
  String? twitterHandle;
}

class BeaconState {
  bool isBeaconing;
  bool isScanning;
  List<DetectedUser> nearbyUsers;
}
```

## File Structure

```
lib/
├── main.dart
├── app.dart
├── config/
│   └── constants.dart        # Colors, UUIDs, timing
├── models/
│   ├── app_state.dart
│   └── user.dart
├── services/
│   ├── bluetooth_service.dart
│   ├── storage_service.dart
│   └── haptic_service.dart
├── providers/
│   └── app_provider.dart     # State management
├── screens/
│   ├── splash_screen.dart    # Stage 1
│   ├── locked_screen.dart    # Stage 2
│   ├── signup_screen.dart    # Stage 3
│   └── home_screen.dart      # Stage 4
├── widgets/
│   ├── animated_background.dart
│   ├── karass_logo.dart
│   ├── beacon_indicator.dart
│   └── notification_card.dart
└── painters/
    └── particle_painter.dart # Procedural animations
```

## Dependencies

```yaml
dependencies:
  flutter_blue_plus: ^2.1.0   # Bluetooth
  shared_preferences: ^2.2.0  # Local storage
  provider: ^6.0.0            # State management
  vibration: ^2.0.0           # Haptic feedback (cross-platform)
```

## Color Scheme

### Active/Unlocked
- Primary: Deep purple (#6B4EE6)
- Secondary: Soft pink (#FF6B9D)
- Background: Dark navy (#0A0A1A)
- Particles: White/pink with glow

### Muted/Locked
- Same colors at 40% opacity
- Darkened overlay

## Animation Specs

### Floating Particles
- 50-100 particles on screen
- Random sizes (2-8px)
- Slow drift (0.5-2px per frame)
- Fade in/out over 3-5 seconds
- Soft glow effect
- Colors: white, pink, purple with varying opacity

## MVP Scope

### In Scope
- All 4 stages functional
- Bluetooth scanning and detection
- Basic beaconing (advertising)
- Local state persistence
- Email/username sign-up (Twitter OAuth can be stubbed)
- Procedural particle animation
- Haptic feedback

### Out of Scope (Post-MVP)
- Backend server integration
- Real Twitter OAuth
- Actual approval system
- Push notifications
- User profiles
- Chat/messaging
