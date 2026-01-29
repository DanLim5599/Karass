enum AppStage {
  splash,            // Stage 1: Initial splash screen with logo
  landing,           // Stage 2: Landing page with "Request an Invitation" / "Login"
  onboarding1,       // Stage 3a: First onboarding page
  onboarding2,       // Stage 3b: Second onboarding page
  createAccount,     // Stage 3c: Create account form
  login,             // Stage 3d: Login form
  signUp,            // Legacy - kept for compatibility, redirects to landing
  waitingForBeacon,  // Stage 4: After signup, waiting for beacon detection
  unlocked,          // Stage 5: Full app access (beacon detected)
}

class UserData {
  final String? email;
  final String? username;
  final String? twitterHandle;
  final bool isAdmin;
  final bool isCurrentBeacon;

  const UserData({
    this.email,
    this.username,
    this.twitterHandle,
    this.isAdmin = false,
    this.isCurrentBeacon = false,
  });

  UserData copyWith({
    String? email,
    String? username,
    String? twitterHandle,
    bool? isAdmin,
    bool? isCurrentBeacon,
  }) {
    return UserData(
      email: email ?? this.email,
      username: username ?? this.username,
      twitterHandle: twitterHandle ?? this.twitterHandle,
      isAdmin: isAdmin ?? this.isAdmin,
      isCurrentBeacon: isCurrentBeacon ?? this.isCurrentBeacon,
    );
  }

  bool get isComplete => email != null && username != null;
}

class BeaconData {
  final bool isBeaconing;
  final bool isScanning;
  final int nearbyUsersCount;

  const BeaconData({
    this.isBeaconing = false,
    this.isScanning = false,
    this.nearbyUsersCount = 0,
  });

  BeaconData copyWith({
    bool? isBeaconing,
    bool? isScanning,
    int? nearbyUsersCount,
  }) {
    return BeaconData(
      isBeaconing: isBeaconing ?? this.isBeaconing,
      isScanning: isScanning ?? this.isScanning,
      nearbyUsersCount: nearbyUsersCount ?? this.nearbyUsersCount,
    );
  }
}
