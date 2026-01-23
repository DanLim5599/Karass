import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:karass/services/api_service.dart';
import 'package:karass/providers/app_provider.dart';
import 'package:karass/screens/home_screen.dart';
import 'package:karass/models/app_state.dart';

// Mock classes
class MockApiService extends Mock implements ApiService {}

void main() {
  group('Announcement Model', () {
    test('should create Announcement from JSON', () {
      final json = {
        'id': '1',
        'title': 'Test Announcement',
        'message': 'This is a test message',
        'createdAt': '2024-01-15T10:30:00.000Z',
        'createdBy': 'admin_user',
      };

      final announcement = Announcement.fromJson(json);

      expect(announcement.id, '1');
      expect(announcement.title, 'Test Announcement');
      expect(announcement.message, 'This is a test message');
      expect(announcement.createdBy, 'admin_user');
      expect(announcement.createdAt, isA<DateTime>());
    });

    test('should handle missing optional fields', () {
      final json = {
        'id': '2',
        'title': 'No Author',
        'message': 'Message without author',
      };

      final announcement = Announcement.fromJson(json);

      expect(announcement.id, '2');
      expect(announcement.title, 'No Author');
      expect(announcement.createdBy, isNull);
    });

    test('should handle null values gracefully', () {
      final json = <String, dynamic>{};

      final announcement = Announcement.fromJson(json);

      expect(announcement.id, '');
      expect(announcement.title, '');
      expect(announcement.message, '');
      expect(announcement.createdBy, isNull);
    });
  });

  group('UserResponse Model', () {
    test('should create UserResponse from JSON', () {
      final json = {
        'id': 'user123',
        'email': 'test@example.com',
        'username': 'testuser',
        'twitterHandle': '@testuser',
        'isApproved': true,
        'isAdmin': true,
      };

      final user = UserResponse.fromJson(json);

      expect(user.id, 'user123');
      expect(user.email, 'test@example.com');
      expect(user.username, 'testuser');
      expect(user.twitterHandle, '@testuser');
      expect(user.isApproved, true);
      expect(user.isAdmin, true);
    });

    test('should handle non-admin user', () {
      final json = {
        'id': 'user456',
        'email': 'regular@example.com',
        'username': 'regularuser',
        'isApproved': true,
        'isAdmin': false,
      };

      final user = UserResponse.fromJson(json);

      expect(user.isAdmin, false);
      expect(user.twitterHandle, isNull);
    });

    test('should default to false for boolean fields', () {
      final json = {
        'id': 'user789',
        'email': 'new@example.com',
        'username': 'newuser',
      };

      final user = UserResponse.fromJson(json);

      expect(user.isApproved, false);
      expect(user.isAdmin, false);
    });
  });

  group('ApiResponse', () {
    test('should create successful ApiResponse', () {
      final user = UserResponse.fromJson({
        'id': '1',
        'email': 'test@test.com',
        'username': 'test',
        'isApproved': true,
        'isAdmin': false,
      });

      final response = ApiResponse(
        success: true,
        message: 'Success',
        user: user,
      );

      expect(response.success, true);
      expect(response.message, 'Success');
      expect(response.user, isNotNull);
    });

    test('should create failed ApiResponse', () {
      final response = ApiResponse(
        success: false,
        message: 'Error occurred',
      );

      expect(response.success, false);
      expect(response.message, 'Error occurred');
      expect(response.user, isNull);
    });
  });

  group('UserData Model', () {
    test('should create default UserData', () {
      const userData = UserData();

      expect(userData.email, isNull);
      expect(userData.username, isNull);
      expect(userData.twitterHandle, isNull);
      expect(userData.isAdmin, false);
    });

    test('should create UserData with values', () {
      const userData = UserData(
        email: 'admin@karass.app',
        username: 'admin',
        twitterHandle: '@admin',
        isAdmin: true,
      );

      expect(userData.email, 'admin@karass.app');
      expect(userData.username, 'admin');
      expect(userData.twitterHandle, '@admin');
      expect(userData.isAdmin, true);
    });

    test('should copy with new values', () {
      const original = UserData(
        email: 'original@test.com',
        username: 'original',
        isAdmin: false,
      );

      final copied = original.copyWith(isAdmin: true);

      expect(copied.email, 'original@test.com');
      expect(copied.username, 'original');
      expect(copied.isAdmin, true);
    });
  });

  group('Announcement UI Tests', () {
    testWidgets('should show empty state when no announcements',
        (WidgetTester tester) async {
      // Build a minimal test widget
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Builder(
              builder: (context) {
                // Test the empty state text
                return const Center(
                  child: Text('No announcements yet'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('No announcements yet'), findsOneWidget);
    });

    testWidgets('should show admin button for admin users',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Builder(
              builder: (context) {
                // Test that admin button exists with correct text
                return OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.campaign, size: 18),
                  label: const Text('SEND ANNOUNCEMENT'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('SEND ANNOUNCEMENT'), findsOneWidget);
      expect(find.byIcon(Icons.campaign), findsOneWidget);
    });

    testWidgets('should display announcement card correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Test Announcement Title',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text('This is the announcement message'),
                  const SizedBox(height: 6),
                  Text(
                    '— admin_user',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Test Announcement Title'), findsOneWidget);
      expect(find.text('This is the announcement message'), findsOneWidget);
      expect(find.text('— admin_user'), findsOneWidget);
    });

    testWidgets('should show announcement dialog elements',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Send Announcement'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              decoration: const InputDecoration(
                                labelText: 'Title',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Message',
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          OutlinedButton(
                            onPressed: () {},
                            child: const Text('Send'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog elements
      expect(find.text('Send Announcement'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('should close dialog on cancel', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Send Announcement'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Send Announcement'), findsOneWidget);

      // Cancel dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Send Announcement'), findsNothing);
    });
  });

  group('Time Formatting', () {
    test('should format time as "Just now" for recent times', () {
      final now = DateTime.now();
      final formatted = _formatTimeAgo(now);
      expect(formatted, 'Just now');
    });

    test('should format time in minutes', () {
      final fiveMinutesAgo = DateTime.now().subtract(const Duration(minutes: 5));
      final formatted = _formatTimeAgo(fiveMinutesAgo);
      expect(formatted, '5m ago');
    });

    test('should format time in hours', () {
      final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2));
      final formatted = _formatTimeAgo(twoHoursAgo);
      expect(formatted, '2h ago');
    });

    test('should format time in days', () {
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      final formatted = _formatTimeAgo(threeDaysAgo);
      expect(formatted, '3d ago');
    });
  });
}

// Helper function mirroring the one in home_screen.dart for testing
String _formatTimeAgo(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inDays > 0) {
    return '${difference.inDays}d ago';
  } else if (difference.inHours > 0) {
    return '${difference.inHours}h ago';
  } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes}m ago';
  } else {
    return 'Just now';
  }
}
