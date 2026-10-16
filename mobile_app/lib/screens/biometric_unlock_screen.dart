import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';
import '../core/theme/radius.dart';
import '../core/theme/spacing.dart';
import '../core/theme/typography.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import '../services/session_manager.dart';

/// Screen allowing returning users with stored sessions to unlock via biometrics.
///
/// In compliance with security requirements, biometrics unlock the existing authenticated
/// session but do not bypass backend authorization.
class BiometricUnlockScreen extends StatefulWidget {
  const BiometricUnlockScreen({
    super.key,
    required this.session,
    required this.apiService,
    required this.sessionManager,
    this.biometricService,
    required this.onUnlockSuccess,
    required this.onSwitchAccount,
    required this.onSessionExpired,
  });

  final AuthSession session;
  final ApiService apiService;
  final SessionManager sessionManager;
  final BiometricService? biometricService;
  final ValueChanged<AuthSession> onUnlockSuccess;
  final VoidCallback onSwitchAccount;
  final VoidCallback onSessionExpired;

  @override
  State<BiometricUnlockScreen> createState() => _BiometricUnlockScreenState();
}

class _BiometricUnlockScreenState extends State<BiometricUnlockScreen> {
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Auto-prompt biometrics shortly after screen displays
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerBiometricAuth();
    });
  }

  Future<void> _triggerBiometricAuth() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final bio = widget.biometricService ?? BiometricService();
    final success = await bio.authenticate(
      localizedReason: 'Unlock IFSO Location Management session for ${widget.session.principalId}',
    );

    if (!mounted) return;

    if (!success) {
      setState(() {
        _isAuthenticating = false;
        _errorMessage = 'Biometric authentication was not completed or failed. Tap below to retry or log in with credentials.';
      });
      return;
    }

    // Biometric verified locally. Now re-validate session with backend.
    try {
      final verifyApi = widget.apiService.copyWith(authToken: widget.session.token);
      final principal = await verifyApi.getCurrentPrincipal();

      final principalId = principal['principal_id'] as String;
      final role = (principal['role'] as String).toUpperCase();

      final updatedSession = widget.session.copyWith(
        principalId: principalId,
        role: role,
      );
      await widget.sessionManager.saveSession(updatedSession);

      if (!mounted) return;
      widget.onUnlockSuccess(updatedSession);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        // Session has expired on the backend
        await widget.sessionManager.clearSession();
        widget.onSessionExpired();
      } else {
        setState(() {
          _isAuthenticating = false;
          _errorMessage = e.message.isNotEmpty
              ? e.message
              : 'Failed to re-validate session with the server.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to reach the authentication server. Verify network connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Locked'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log Out',
            onPressed: widget.onSwitchAccount,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space6,
              vertical: AppSpacing.space8,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Biometric Fingerprint Icon
                Center(
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.fingerprint,
                      size: 64,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space6),

                Text(
                  'Unlock Session',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.space2),

                // Account card showing Principal and Role
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    side: BorderSide(color: AppColors.border.withValues(alpha: 0.4)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.person, size: 18, color: AppColors.secondary),
                            const SizedBox(width: AppSpacing.space2),
                            Text(
                              widget.session.principalId,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.space1),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space2,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(AppRadius.small),
                          ),
                          child: Text(
                            'ROLE: ${widget.session.role}',
                            style: AppTypography.technicalBold.copyWith(
                              fontSize: 11,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space6),

                // Error Banner
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.space3),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.error, size: 20),
                        const SizedBox(width: AppSpacing.space2),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                ],

                // Unlock Button
                FilledButton.icon(
                  onPressed: _isAuthenticating ? null : _triggerBiometricAuth,
                  icon: _isAuthenticating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Icon(Icons.fingerprint),
                  label: Text(
                    _isAuthenticating ? 'Verifying Identity...' : 'Unlock with Fingerprint',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space4),

                // Switch Account / Login with credentials
                TextButton(
                  onPressed: _isAuthenticating ? null : widget.onSwitchAccount,
                  child: const Text('Log In with Different Credentials'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
