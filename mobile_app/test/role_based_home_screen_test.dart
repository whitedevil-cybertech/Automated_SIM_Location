import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ifso_mobile_app/screens/home_screen.dart';
import 'package:ifso_mobile_app/services/api_service.dart';

Widget buildHome(String role) => MaterialApp(
      home: HomeScreen(
        apiService: ApiService(baseUrl: 'http://localhost/api/v1', authToken: 'test'),
        officerApiService: ApiService(baseUrl: 'http://localhost/api/v1', authToken: 'test'),
        role: role,
        ioDeviceId: 'TEST-DEVICE',
      ),
    );

void main() {
  testWidgets('Officer sees only Officer workflow', (tester) async {
    await tester.pumpWidget(buildHome('OFFICER'));
    expect(find.text('Officer Module'), findsOneWidget);
    expect(find.text('IO Execution'), findsNothing);
  });

  testWidgets('IO sees only IO workflow', (tester) async {
    await tester.pumpWidget(buildHome('IO'));
    expect(find.text('IO Execution'), findsOneWidget);
    expect(find.text('Officer Module'), findsNothing);
  });

  testWidgets('Admin sees no request execution controls in MVP', (tester) async {
    await tester.pumpWidget(buildHome('ADMIN'));
    expect(find.text('Administrator'), findsOneWidget);
    expect(find.text('Officer Module'), findsNothing);
    expect(find.text('IO Execution'), findsNothing);
  });
}
