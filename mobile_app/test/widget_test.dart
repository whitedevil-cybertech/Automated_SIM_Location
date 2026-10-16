import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifso_mobile_app/screens/welcome_screen.dart';

void main() {
  testWidgets('Welcome screen renders successfully', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(
          onLogin: () {},
          onSignUp: () {},
        ),
      ),
    );

    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}