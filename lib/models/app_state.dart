enum AppStage {
  splash,            // Stage 1: Initial splash screen with logo
  signUp,            // Stage 2: Create account / login
  waitingForBeacon,  // Stage 3: After signup, waiting for beacon detection
  unlocked,          // Stage 4: Full app access (beacon detected)
}

class UserData {
  final String? email;
  final String? username;
  final String? twitterHandle;
  final bool isAdmin;

  const UserData({
    this.email,
    this.username,
    this.twitterHandle,
    this.isAdmin = false,
  });

  UserData copyWith({
    String? email,
    String? username,
    String? twitterHandle,
    bool? isAdmin,
  }) {
    return UserData(
      email: email ?? this.email,
      username: username ?? this.username,
      twitterHandle: twitterHandle ?? this.twitterHandle,
      isAdmin: isAdmin ?? this.isAdmin,
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
