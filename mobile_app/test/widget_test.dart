import 'package:flutter_test/flutter_test.dart';
import 'package:ifso_mobile_app/main.dart';
import 'package:ifso_mobile_app/screens/home_screen.dart';

void main() {
  testWidgets('IFSO Application shell renders successfully', (
    WidgetTester tester,
  ) async {
    // Build application widget tree
    await tester.pumpWidget(const IfsoApp());

    // Verify HomeScreen is rendered
    expect(find.byType(HomeScreen), findsOneWidget);

    // Verify Title and Phase banner
    expect(find.text('IFSO Location Management'), findsOneWidget);
    expect(find.text('Phase 1 — Foundation & Architecture'), findsOneWidget);

    // Verify System Environment card
    expect(find.text('System Environment'), findsOneWidget);
    expect(find.text('Internal MDM Managed'), findsOneWidget);
  });
}
