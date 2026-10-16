import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';
import '../core/theme/radius.dart';
import '../core/theme/spacing.dart';

/// Screen guiding officers through the authorized IFSO account provisioning workflow.
///
/// In compliance with departmental security requirements, public users cannot self-assign
/// IO or ADMIN privileges. Real account provisioning is managed via administrative enrollment
/// or external enterprise Identity Provider (IdP).
class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    required this.onNavigateToLogin,
  });

  final VoidCallback onNavigateToLogin;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _officerNameController = TextEditingController();
  final _badgeNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _unitController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isSubmitted = false;

  @override
  void dispose() {
    _officerNameController.dispose();
    _badgeNumberController.dispose();
    _emailController.dispose();
    _unitController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submitEnrollment() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isSubmitted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Officer Enrollment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onNavigateToLogin,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space4,
          ),
          child: _isSubmitted
              ? _buildEnrollmentConfirmation(theme)
              : _buildEnrollmentForm(theme),
        ),
      ),
    );
  }

  Widget _buildEnrollmentForm(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Security Policy Notice Card
          Card(
            color: AppColors.infoContainer.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              side: BorderSide(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.security, size: 20, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.space2),
                      Text(
                        'Account Provisioning Policy',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    'Access is strictly restricted to verified Delhi Police / IFSO personnel. '
                    'To prevent unauthorized access, users cannot self-assign IO (Investigating Officer) '
                    'or ADMIN roles. Accounts are provisioned and vetted through the IFSO System Administrator '
                    'or Enterprise MDM profile.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space4),

          Text(
            'Submit Enrollment Request',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            'Provide your official credentials to request account activation or receive your bearer access token.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.space4),

          // Officer Full Name
          TextFormField(
            controller: _officerNameController,
            decoration: const InputDecoration(
              labelText: 'Officer Full Name',
              hintText: 'e.g. Insp. Rajesh Kumar',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your full name.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.space3),

          // Badge / Service ID
          TextFormField(
            controller: _badgeNumberController,
            decoration: const InputDecoration(
              labelText: 'Badge / Service PIS Number',
              hintText: 'e.g. 28910042',
              prefixIcon: Icon(Icons.numbers),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your official badge/PIS number.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.space3),

          // Department Email
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Official Government Email',
              hintText: 'name@delhipolice.gov.in',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your official email address.';
              }
              if (!value.contains('@') || !value.contains('.')) {
                return 'Please enter a valid official email address.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.space3),

          // Unit / Station
          TextFormField(
            controller: _unitController,
            decoration: const InputDecoration(
              labelText: 'Assigned Unit / Police Station',
              hintText: 'e.g. IFSO Cyber Cell, Dwarka',
              prefixIcon: Icon(Icons.location_city_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please specify your assigned unit.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.space3),

          // Phone Number
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Official Contact Phone',
              hintText: '10-digit mobile number',
              prefixIcon: Icon(Icons.phone_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your contact number.';
              }
              if (value.trim().replaceAll(RegExp(r'\D'), '').length < 10) {
                return 'Please enter a valid 10-digit phone number.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.space6),

          // Submit Button
          FilledButton.icon(
            onPressed: _submitEnrollment,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Submit Enrollment Request'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space3),

          // Already have token/credentials link
          TextButton(
            onPressed: widget.onNavigateToLogin,
            child: const Text('Already have an issued token or credential? Log In'),
          ),
        ],
      ),
    );
  }

  Widget _buildEnrollmentConfirmation(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 64,
            color: AppColors.success,
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            'Enrollment Request Logged',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Your enrollment request for Officer ID "${_badgeNumberController.text.trim()}" has been recorded for administrative verification.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.space6),

          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              side: BorderSide(color: AppColors.border.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next Steps for Account Activation',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  const Text('1. The IFSO Administrator will verify your badge against the departmental roster.'),
                  const SizedBox(height: AppSpacing.space1),
                  const Text('2. For IO roles, hardware SIM registration on the MDM platform is mandatory.'),
                  const SizedBox(height: AppSpacing.space1),
                  const Text('3. You will receive an official bearer token or IdP single sign-on access to log in.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space6),

          FilledButton.icon(
            onPressed: widget.onNavigateToLogin,
            icon: const Icon(Icons.login),
            label: const Text('Proceed to Log In'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
