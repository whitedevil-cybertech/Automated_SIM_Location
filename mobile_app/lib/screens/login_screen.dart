import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';
import '../core/theme/radius.dart';
import '../core/theme/spacing.dart';
import '../core/theme/typography.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import '../services/session_manager.dart';

/// Production-ready login screen enforcing real backend authentication and role resolution.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.apiService,
    required this.sessionManager,
    this.biometricService,
    required this.onLoginSuccess,
    required this.onNavigateToSignUp,
    this.initialErrorMessage,
  });

  final ApiService apiService;
  final SessionManager sessionManager;
  final BiometricService? biometricService;
  final ValueChanged<AuthSession> onLoginSuccess;
  final VoidCallback onNavigateToSignUp;
  final String? initialErrorMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();

  bool _isLoading = false;
  bool _enableBiometrics = false;
  bool _biometricsAvailable = false;
  bool _obscureToken = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialErrorMessage;
    _checkBiometrics();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    final bio = widget.biometricService ?? BiometricService();
    final available = await bio.isBiometricAvailable();
    if (mounted) {
      setState(() {
        _biometricsAvailable = available;
        _enableBiometrics = available;
      });
    }
  }

  Future<void> _performLogin([String? presetToken]) async {
    final tokenToTest = (presetToken ?? _tokenController.text).trim();
    if (presetToken != null) {
      _tokenController.text = presetToken;
    } else {
      if (!_formKey.currentState!.validate()) return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Create a temporary client with the provided token to test server authentication
      final tempApi = widget.apiService.copyWith(authToken: tokenToTest);
      final identity = await tempApi.getCurrentPrincipal();

      final principalId = identity['principal_id'] as String;
      final role = (identity['role'] as String).toUpperCase();

      if (!{'OFFICER', 'IO', 'ADMIN'}.contains(role)) {
        throw const ApiException(
          statusCode: 403,
          code: 'UNSUPPORTED_ROLE',
          message: 'The server assigned an unrecognized or unauthorized role.',
        );
      }

      final session = AuthSession(
        token: tokenToTest,
        principalId: principalId,
        role: role,
        isBiometricEnabled: _enableBiometrics && _biometricsAvailable,
      );

      // Securely persist session
      await widget.sessionManager.saveSession(session);
      await widget.sessionManager.setHasSeenWelcome(true);

      if (!mounted) return;
      widget.onLoginSuccess(session);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 401) {
          _errorMessage = 'Invalid or expired authentication credentials. Please check your token or contact the administrator.';
        } else if (e.statusCode == 403) {
          _errorMessage = 'Access denied. Your account is not authorized for mobile operations.';
        } else if (e.isNetworkError) {
          _errorMessage = 'Unable to connect to the authentication service. Check server network connection.';
        } else {
          _errorMessage = e.message.isNotEmpty ? e.message : 'Authentication failed.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An unexpected error occurred during login. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('IFSO Session Login'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space6,
              vertical: AppSpacing.space6,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_person_outlined,
                        size: 38,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space4),

                  Text(
                    'Authenticate Session',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.space1),
                  Text(
                    'Enter your provisioned bearer token or service credentials to access the system.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.space6),

                  // Error Message Banner
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.space3),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                          const SizedBox(width: AppSpacing.space2),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space4),
                  ],

                  // Token Input Field
                  TextFormField(
                    controller: _tokenController,
                    obscureText: _obscureToken,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      labelText: 'Access Token / Bearer Credential',
                      hintText: 'Enter issued bearer token',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureToken ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureToken = !_obscureToken),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Authentication token is required.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.space4),

                  // Biometric Option
                  if (_biometricsAvailable) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Fingerprint / Biometric Unlock'),
                      subtitle: const Text('Unlock returning sessions quickly without re-entering credentials'),
                      value: _enableBiometrics,
                      onChanged: _isLoading
                          ? null
                          : (val) => setState(() => _enableBiometrics = val),
                    ),
                    const SizedBox(height: AppSpacing.space4),
                  ],

                  // Login Action
                  FilledButton(
                    onPressed: _isLoading ? null : () => _performLogin(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Text('Authenticate & Open Session'),
                  ),
                  const SizedBox(height: AppSpacing.space4),

                  // Development Quick Tokens Card
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      side: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.code, size: 16, color: AppColors.textSecondary),
                              const SizedBox(width: AppSpacing.space1),
                              Text(
                                'Development / Test Profiles',
                                style: AppTypography.technicalBold.copyWith(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.space2),
                          Wrap(
                            spacing: AppSpacing.space2,
                            runSpacing: AppSpacing.space2,
                            children: [
                              ActionChip(
                                label: const Text('Officer Dev'),
                                avatar: const Icon(Icons.badge, size: 16),
                                onPressed: _isLoading ? null : () => _performLogin('dev-officer-token'),
                              ),
                              ActionChip(
                                label: const Text('IO Dev'),
                                avatar: const Icon(Icons.phone_android, size: 16),
                                onPressed: _isLoading ? null : () => _performLogin('dev-io-token'),
                              ),
                              ActionChip(
                                label: const Text('Admin Dev'),
                                avatar: const Icon(Icons.admin_panel_settings, size: 16),
                                onPressed: _isLoading ? null : () => _performLogin('dev-admin-token'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space6),

                  // Navigate to Signup
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : widget.onNavigateToSignUp,
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('New Officer? Request Account Enrollment'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
