import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/biometric_unlock_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/api_service.dart';
import 'services/biometric_service.dart';
import 'services/session_manager.dart';
import 'services/telephony_bridge.dart';

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.137.1:8000/api/v1',
);
// Optional development/testing compile-time token fallback. Never bake production credentials into an APK.
const _apiAuthToken = String.fromEnvironment('API_AUTH_TOKEN', defaultValue: '');
const _ioDeviceId = String.fromEnvironment('IO_DEVICE_ID', defaultValue: 'IO-DEVICE-DEV-001');
const _simSlotIndex = int.fromEnvironment('SIM_SLOT_INDEX', defaultValue: 0);
final _defaultTelephonyBridge = TelephonyBridge();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IfsoApp());
}

class IfsoApp extends StatelessWidget {
  const IfsoApp({
    super.key,
    this.apiService,
    this.sessionManager,
    this.biometricService,
    this.telephonyBridge,
    this.ioDeviceId = _ioDeviceId,
    this.simSlotIndex = _simSlotIndex,
  });

  final ApiService? apiService;
  final SessionManager? sessionManager;
  final BiometricService? biometricService;
  final TelephonyBridge? telephonyBridge;
  final String ioDeviceId;
  final int simSlotIndex;

  @override
  Widget build(BuildContext context) {
    final baseApi = apiService ?? ApiService(baseUrl: _apiBaseUrl, authToken: _apiAuthToken);
    final sessionMgr = sessionManager ?? SessionManager();
    final bioService = biometricService ?? BiometricService();
    final telBridge = telephonyBridge ?? _defaultTelephonyBridge;

    return MaterialApp(
      title: 'IFSO Location Request Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _AppAuthGate(
        baseApiService: baseApi,
        sessionManager: sessionMgr,
        biometricService: bioService,
        telephonyBridge: telBridge,
        ioDeviceId: ioDeviceId,
        simSlotIndex: simSlotIndex,
      ),
    );
  }
}

enum _AuthFlowState {
  loading,
  welcome,
  signup,
  login,
  biometricUnlock,
  authenticated,
}

class _AppAuthGate extends StatefulWidget {
  const _AppAuthGate({
    required this.baseApiService,
    required this.sessionManager,
    required this.biometricService,
    required this.telephonyBridge,
    required this.ioDeviceId,
    required this.simSlotIndex,
  });

  final ApiService baseApiService;
  final SessionManager sessionManager;
  final BiometricService biometricService;
  final TelephonyBridge telephonyBridge;
  final String ioDeviceId;
  final int simSlotIndex;

  @override
  State<_AppAuthGate> createState() => _AppAuthGateState();
}

class _AppAuthGateState extends State<_AppAuthGate> {
  _AuthFlowState _state = _AuthFlowState.loading;
  AuthSession? _activeSession;
  String? _loginErrorMessage;

  @override
  void initState() {
    super.initState();
    _resolveInitialSession();
  }

  Future<void> _resolveInitialSession() async {
    setState(() => _state = _AuthFlowState.loading);

    // If compile-time token is provided (e.g. testing / automated scripts), test it
    if (widget.baseApiService.authToken != null && widget.baseApiService.authToken!.isNotEmpty) {
      try {
        final identity = await widget.baseApiService.getCurrentPrincipal();
        final principalId = identity['principal_id'] as String;
        final role = (identity['role'] as String).toUpperCase();
        if ({'OFFICER', 'IO', 'ADMIN'}.contains(role)) {
          final session = AuthSession(
            token: widget.baseApiService.authToken!,
            principalId: principalId,
            role: role,
          );
          if (mounted) {
            setState(() {
              _activeSession = session;
              _state = _AuthFlowState.authenticated;
            });
            return;
          }
        }
      } catch (_) {
        // Fall back to standard session lifecycle
      }
    }

    // Check securely stored session
    final savedSession = await widget.sessionManager.getSession();
    if (savedSession != null) {
      if (savedSession.isBiometricEnabled) {
        final isBioAvailable = await widget.biometricService.isBiometricAvailable();
        if (isBioAvailable && mounted) {
          setState(() {
            _activeSession = savedSession;
            _state = _AuthFlowState.biometricUnlock;
          });
          return;
        }
      }

      // Re-verify stored session token against server
      try {
        final verifyApi = widget.baseApiService.copyWith(authToken: savedSession.token);
        final identity = await verifyApi.getCurrentPrincipal();
        final principalId = identity['principal_id'] as String;
        final role = (identity['role'] as String).toUpperCase();

        if ({'OFFICER', 'IO', 'ADMIN'}.contains(role)) {
          final updatedSession = savedSession.copyWith(
            principalId: principalId,
            role: role,
          );
          await widget.sessionManager.saveSession(updatedSession);
          if (mounted) {
            setState(() {
              _activeSession = updatedSession;
              _state = _AuthFlowState.authenticated;
            });
            return;
          }
        }
      } catch (_) {
        // Session invalid, expired, or network unreachable
        await widget.sessionManager.clearSession();
        if (mounted) {
          setState(() {
            _activeSession = null;
            _loginErrorMessage = 'Session expired or invalidated. Please log in again.';
            _state = _AuthFlowState.login;
          });
          return;
        }
      }
    }

    // No session: determine if first launch or returning user
    final hasSeenWelcome = await widget.sessionManager.hasSeenWelcome();
    if (mounted) {
      setState(() {
        _activeSession = null;
        _state = hasSeenWelcome ? _AuthFlowState.login : _AuthFlowState.welcome;
      });
    }
  }

  void _onWelcomeLogin() async {
    await widget.sessionManager.setHasSeenWelcome(true);
    setState(() {
      _loginErrorMessage = null;
      _state = _AuthFlowState.login;
    });
  }

  void _onWelcomeSignUp() async {
    await widget.sessionManager.setHasSeenWelcome(true);
    setState(() {
      _state = _AuthFlowState.signup;
    });
  }

  void _onLoginSuccess(AuthSession session) {
    setState(() {
      _activeSession = session;
      _loginErrorMessage = null;
      _state = _AuthFlowState.authenticated;
    });
  }

  void _onNavigateToSignUp() {
    setState(() {
      _state = _AuthFlowState.signup;
    });
  }

  void _onNavigateToLogin() {
    setState(() {
      _loginErrorMessage = null;
      _state = _AuthFlowState.login;
    });
  }

  void _onBiometricUnlockSuccess(AuthSession session) {
    setState(() {
      _activeSession = session;
      _loginErrorMessage = null;
      _state = _AuthFlowState.authenticated;
    });
  }

  void _onBiometricSwitchAccount() async {
    await widget.sessionManager.clearSession();
    setState(() {
      _activeSession = null;
      _loginErrorMessage = null;
      _state = _AuthFlowState.login;
    });
  }

  void _onSessionExpired() {
    setState(() {
      _activeSession = null;
      _loginErrorMessage = 'Your session has expired. Please log in again.';
      _state = _AuthFlowState.login;
    });
  }

  void _onLogout() async {
    await widget.sessionManager.clearSession();
    setState(() {
      _activeSession = null;
      _loginErrorMessage = null;
      _state = _AuthFlowState.login;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _AuthFlowState.loading:
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );

      case _AuthFlowState.welcome:
        return WelcomeScreen(
          onLogin: _onWelcomeLogin,
          onSignUp: _onWelcomeSignUp,
        );

      case _AuthFlowState.signup:
        return SignupScreen(
          onNavigateToLogin: _onNavigateToLogin,
        );

      case _AuthFlowState.login:
        return LoginScreen(
          apiService: widget.baseApiService,
          sessionManager: widget.sessionManager,
          biometricService: widget.biometricService,
          initialErrorMessage: _loginErrorMessage,
          onLoginSuccess: _onLoginSuccess,
          onNavigateToSignUp: _onNavigateToSignUp,
        );

      case _AuthFlowState.biometricUnlock:
        return BiometricUnlockScreen(
          session: _activeSession!,
          apiService: widget.baseApiService,
          sessionManager: widget.sessionManager,
          biometricService: widget.biometricService,
          onUnlockSuccess: _onBiometricUnlockSuccess,
          onSwitchAccount: _onBiometricSwitchAccount,
          onSessionExpired: _onSessionExpired,
        );

      case _AuthFlowState.authenticated:
        final session = _activeSession!;
        final authenticatedApiService = widget.baseApiService.copyWith(
          authToken: session.token,
        );

        return HomeScreen(
          apiService: authenticatedApiService,
          officerApiService: authenticatedApiService,
          role: session.role,
          ioDeviceId: widget.ioDeviceId,
          simSlotIndex: widget.simSlotIndex,
          telephonyBridge: widget.telephonyBridge,
          onLogout: _onLogout,
        );
    }
  }
}
