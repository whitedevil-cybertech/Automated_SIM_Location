import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ifso_mobile_app/main.dart';
import 'package:ifso_mobile_app/screens/biometric_unlock_screen.dart';
import 'package:ifso_mobile_app/screens/login_screen.dart';
import 'package:ifso_mobile_app/screens/signup_screen.dart';
import 'package:ifso_mobile_app/screens/welcome_screen.dart';
import 'package:ifso_mobile_app/services/api_service.dart';
import 'package:ifso_mobile_app/services/biometric_service.dart';
import 'package:ifso_mobile_app/services/session_manager.dart';

class MockSecureStorageAdapter implements SecureStorageAdapter {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({required String key}) async => _data[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _data[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }
}

class FakeBiometricService extends BiometricService {
  FakeBiometricService({
    this.isAvailable = true,
    this.authSuccess = true,
  });

  final bool isAvailable;
  final bool authSuccess;

  @override
  Future<bool> isBiometricAvailable() async => isAvailable;

  @override
  Future<bool> authenticate({
    String localizedReason = 'Verify your identity',
  }) async => authSuccess;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionManager Unit Tests', () {
    late SessionManager sessionManager;
    late MockSecureStorageAdapter storage;

    setUp(() {
      storage = MockSecureStorageAdapter();
      sessionManager = SessionManager(storage: storage);
    });

    test('saves, reads, and clears authentication session', () async {
      expect(await sessionManager.getSession(), isNull);

      const session = AuthSession(
        token: 'test-token-123',
        principalId: 'OFFICER-001',
        role: 'OFFICER',
        isBiometricEnabled: true,
      );

      await sessionManager.saveSession(session);
      final retrieved = await sessionManager.getSession();

      expect(retrieved, isNotNull);
      expect(retrieved!.token, 'test-token-123');
      expect(retrieved.principalId, 'OFFICER-001');
      expect(retrieved.role, 'OFFICER');
      expect(retrieved.isBiometricEnabled, isTrue);

      await sessionManager.clearSession();
      expect(await sessionManager.getSession(), isNull);
    });

    test('tracks hasSeenWelcome state', () async {
      expect(await sessionManager.hasSeenWelcome(), isFalse);
      await sessionManager.setHasSeenWelcome(true);
      expect(await sessionManager.hasSeenWelcome(), isTrue);
    });

    test('updates biometric enabled flag on active session', () async {
      const session = AuthSession(
        token: 'token-abc',
        principalId: 'IO-001',
        role: 'IO',
        isBiometricEnabled: false,
      );
      await sessionManager.saveSession(session);

      await sessionManager.setBiometricEnabled(true);
      final updated = await sessionManager.getSession();
      expect(updated!.isBiometricEnabled, isTrue);
    });
  });

  group('WelcomeScreen Tests', () {
    testWidgets('renders branding and triggers actions', (tester) async {
      bool loginCalled = false;
      bool signUpCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onLogin: () => loginCalled = true,
            onSignUp: () => signUpCalled = true,
          ),
        ),
      );

      expect(find.text('IFSO Location Management'), findsOneWidget);
      expect(find.textContaining('Authorized Access Only'), findsOneWidget);

      await tester.tap(find.text('Log In with Credentials'));
      expect(loginCalled, isTrue);

      await tester.tap(find.text('New Officer Enrollment'));
      expect(signUpCalled, isTrue);
    });
  });

  group('SignupScreen Tests', () {
    testWidgets('validates required fields and shows policy banner', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SignupScreen(onNavigateToLogin: () {}),
        ),
      );

      expect(find.text('Account Provisioning Policy'), findsOneWidget);
      expect(find.textContaining('cannot self-assign IO'), findsOneWidget);

      // Attempt to submit empty form
      final submitButton = find.byType(FilledButton);
      await tester.scrollUntilVisible(submitButton, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('Please enter your full name.'), findsOneWidget);
      expect(find.text('Please enter your official badge/PIS number.'), findsOneWidget);

      // Fill valid information
      await tester.enterText(find.byType(TextFormField).at(0), 'Insp. Anuj Sharma');
      await tester.enterText(find.byType(TextFormField).at(1), 'PIS-28910042');
      await tester.enterText(find.byType(TextFormField).at(2), 'anuj@delhipolice.gov.in');
      await tester.enterText(find.byType(TextFormField).at(3), 'IFSO Cyber Cell');
      await tester.enterText(find.byType(TextFormField).at(4), '9876543210');

      await tester.scrollUntilVisible(submitButton, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('Enrollment Request Logged'), findsOneWidget);
      expect(find.textContaining('Next Steps for Account Activation'), findsOneWidget);
    });
  });

  group('LoginScreen Tests', () {
    testWidgets('authenticates with valid server response and saves session', (tester) async {
      final storage = MockSecureStorageAdapter();
      final sessionManager = SessionManager(storage: storage);
      AuthSession? loggedInSession;

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/me')) {
          if (request.headers['authorization'] == 'Bearer valid-officer-token') {
            return http.Response(
              jsonEncode({
                'success': true,
                'message': 'Authenticated principal resolved.',
                'data': {'principal_id': 'OFFICER-DEV-001', 'role': 'OFFICER'},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'success': false,
              'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid credentials'},
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final apiService = ApiService(
        baseUrl: 'http://test.server/api/v1',
        client: mockClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            apiService: apiService,
            sessionManager: sessionManager,
            biometricService: FakeBiometricService(isAvailable: false),
            onLoginSuccess: (s) => loggedInSession = s,
            onNavigateToSignUp: () {},
          ),
        ),
      );

      expect(find.text('Authenticate Session'), findsOneWidget);

      // Test validation error when empty
      await tester.tap(find.text('Authenticate & Open Session'));
      await tester.pumpAndSettle();
      expect(find.text('Authentication token is required.'), findsOneWidget);

      // Enter invalid token
      await tester.enterText(find.byType(TextFormField), 'wrong-token');
      await tester.tap(find.text('Authenticate & Open Session'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid or expired authentication credentials'), findsOneWidget);

      // Enter valid token
      await tester.enterText(find.byType(TextFormField), 'valid-officer-token');
      await tester.tap(find.text('Authenticate & Open Session'));
      await tester.pumpAndSettle();

      expect(loggedInSession, isNotNull);
      expect(loggedInSession!.principalId, 'OFFICER-DEV-001');
      expect(loggedInSession!.role, 'OFFICER');

      final saved = await sessionManager.getSession();
      expect(saved, isNotNull);
      expect(saved!.token, 'valid-officer-token');
    });
  });

  group('BiometricUnlockScreen Tests', () {
    testWidgets('unlocks session upon successful biometric and server revalidation', (tester) async {
      final storage = MockSecureStorageAdapter();
      final sessionManager = SessionManager(storage: storage);
      const initialSession = AuthSession(
        token: 'stored-io-token',
        principalId: 'IO-DEV-001',
        role: 'IO',
        isBiometricEnabled: true,
      );
      await sessionManager.saveSession(initialSession);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'OK',
            'data': {'principal_id': 'IO-DEV-001', 'role': 'IO'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = ApiService(
        baseUrl: 'http://test.server/api/v1',
        client: mockClient,
      );

      AuthSession? unlockedSession;

      await tester.pumpWidget(
        MaterialApp(
          home: BiometricUnlockScreen(
            session: initialSession,
            apiService: apiService,
            sessionManager: sessionManager,
            biometricService: FakeBiometricService(isAvailable: true, authSuccess: true),
            onUnlockSuccess: (s) => unlockedSession = s,
            onSwitchAccount: () {},
            onSessionExpired: () {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(unlockedSession, isNotNull);
      expect(unlockedSession!.principalId, 'IO-DEV-001');
      expect(unlockedSession!.role, 'IO');
    });
  });

  group('IfsoApp Full Lifecycle Routing', () {
    testWidgets('shows WelcomeScreen on first launch', (tester) async {
      final storage = MockSecureStorageAdapter();
      final sessionManager = SessionManager(storage: storage);

      await tester.pumpWidget(
        IfsoApp(
          sessionManager: sessionManager,
          biometricService: FakeBiometricService(isAvailable: false),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('shows LoginScreen for returning logged-out user', (tester) async {
      final storage = MockSecureStorageAdapter();
      final sessionManager = SessionManager(storage: storage);
      await sessionManager.setHasSeenWelcome(true);

      await tester.pumpWidget(
        IfsoApp(
          sessionManager: sessionManager,
          biometricService: FakeBiometricService(isAvailable: false),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
