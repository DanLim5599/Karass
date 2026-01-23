import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karass/widgets/karass_logo.dart';

void main() {
  testWidgets('KarassLogo widget displays correctly', (WidgetTester tester) async {
    // Test the logo widget independently without Firebase
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                KarassLogo(size: 80),
                SizedBox(height: 16),
                KarassLogoText(fontSize: 24),
              ],
            ),
          ),
        ),
      ),
    );

    // Verify the logo text displays
    expect(find.text('KARASS'), findsOneWidget);
  });

  testWidgets('KarassLogo can be animated', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: KarassLogo(size: 100, animated: true),
          ),
        ),
      ),
    );

    // Widget should render without error
    expect(find.byType(KarassLogo), findsOneWidget);
  });
}
