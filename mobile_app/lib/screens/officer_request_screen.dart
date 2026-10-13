import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/color_schemes.dart';
import '../core/theme/radius.dart';
import '../core/theme/spacing.dart';
import '../models/location_request.dart';
import '../services/api_service.dart';

class OfficerRequestScreen extends StatefulWidget {
  const OfficerRequestScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<OfficerRequestScreen> createState() => _OfficerRequestScreenState();
}

class _OfficerRequestScreenState extends State<OfficerRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _caseIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _remarksController = TextEditingController();

  static const _operators = <String>['JIO', 'AIRTEL', 'VI', 'BSNL'];
  String _operatorCode = 'JIO';
  bool _isSubmitting = false;
  bool _isMintingLink = false;
  String? _errorMessage;
  LocationRequest? _createdRequest;
  String? _shareableLink;

  @override
  void dispose() {
    _caseIdController.dispose();
    _phoneController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _createRequest() async {
    if (_isSubmitting) return;
    
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final normalizedPhoneNumber = _phoneController.text
    .replaceAll(RegExp(r'[\s-]'), '');
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final request = await widget.apiService.createLocationRequest(
        caseId: _caseIdController.text.trim(),
        targetPhoneNumber: normalizedPhoneNumber,
        operatorCode: _operatorCode,
        remarks: _remarksController.text,
      );
      if (!mounted) return;

      setState(() {
        _createdRequest = request;
        _shareableLink = null;
        _errorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location request created.')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _errorMessage = 'Unable to create the request. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _generateShareLink() async {
    final request = _createdRequest;
    if (request == null || _isMintingLink) return;

    setState(() {
      _isMintingLink = true;
      _errorMessage = null;
    });

    try {
      final updated = await widget.apiService.mintShareLink(
        requestId: request.requestId,
      );
      final link = updated.shareableLink;
      if (link == null || link.isEmpty) {
        throw const ApiException(
          statusCode: 500,
          code: 'INVALID_RESPONSE',
          message: 'The server did not return a share link.',
        );
      }
      if (!mounted) return;
      setState(() => _shareableLink = link);
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _errorMessage = 'Unable to generate the share link. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isMintingLink = false);
    }
  }

  Future<void> _copyShareLink() async {
    final link = _shareableLink;

    if (link == null || link.isEmpty) return;

    try {
      await Clipboard.setData(ClipboardData(text: link));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'One-time link copied. Share it only with the authorized IO.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
          'Unable to copy the share link. Select and copy it manually.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Officer Module')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space4),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create Location Request',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      'Enter the approved case reference and target details. The backend validates the request and records the officer identity from authentication.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _caseIdController,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 64,
                            decoration: const InputDecoration(
                              labelText: 'Case ID / FIR reference',
                              hintText: 'FIR-2026-IFSO-084',
                              prefixIcon: Icon(Icons.folder_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Enter a case reference.'
                                    : null,
                          ),
                          const SizedBox(height: AppSpacing.space2),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Target mobile number',
                              hintText: '10-digit number or +91 number',
                              prefixIcon: Icon(Icons.phone_android_outlined),
                              helperText:
                                  'The number is masked in the application response.',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final cleaned = (value ?? '')
                                  .replaceAll(RegExp(r'[\s-]'), '');
                              if (!RegExp(r'^(\+?91)?[6-9]\d{9}$')
                                  .hasMatch(cleaned)) {
                                return 'Enter a valid Indian mobile number.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.space3),
                          DropdownButtonFormField<String>(
                            initialValue: _operatorCode,
                            decoration: const InputDecoration(
                              labelText: 'Telecom operator',
                              prefixIcon: Icon(Icons.sim_card_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: _operators
                                .map((operator) => DropdownMenuItem(
                                      value: operator,
                                      child: Text(operator),
                                    ))
                                .toList(),
                            onChanged: _isSubmitting
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                      _operatorCode = value;
                                      });
                                    }
                                  },
                          ),
                          const SizedBox(height: AppSpacing.space3),
                          TextFormField(
                            controller: _remarksController,
                            maxLength: 500,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Remarks / justification (optional)',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.space3),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isSubmitting ? null : _createRequest,
                              icon: _isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.add_task),
                              label: Text(_isSubmitting
                                  ? 'Submitting…'
                                  : 'Create Request'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.space3),
              _errorCard(_errorMessage!),
            ],
            if (_createdRequest != null) ...[
              const SizedBox(height: AppSpacing.space3),
              _buildCreatedRequestCard(theme, _createdRequest!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCreatedRequestCard(ThemeData theme, LocationRequest request) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: AppColors.success),
                const SizedBox(width: AppSpacing.space2),
                Expanded(
                    child: Text('Request Created',
                        style: theme.textTheme.titleMedium)),
              ],
            ),
            const Divider(),
            _detail('Request ID', request.requestId),
            _detail('Case ID', request.caseId),
            _detail('Target', request.targetPhoneMasked),
            _detail('Operator', request.operatorCode),
            _detail('Status', request.status.label),
            const SizedBox(height: AppSpacing.space3),
            if (_shareableLink == null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isMintingLink ? null : _generateShareLink,
                  icon: _isMintingLink
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(_isMintingLink
                      ? 'Generating link…'
                      : 'Generate One-Time Share Link'),
                ),
              )
            else ...[
              Text('One-Time Share Link', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.space2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.space3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  border: Border.all(color: AppColors.border),
                  borderRadius: AppRadius.borderSmall,
                ),
                child: SelectableText(_shareableLink!),
              ),
              const SizedBox(height: AppSpacing.space2),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _copyShareLink,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy Link to Share with IO'),
                ),
              ),
              const SizedBox(height: AppSpacing.space2),
              Text(
                'Treat this bearer link as sensitive. It is single-use and expires according to server configuration. The receiving IO must still authenticate.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          const SizedBox(width: AppSpacing.space2),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Card(
      color: AppColors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: AppSpacing.space2),
            Expanded(
                child: Text(message,
                    style: const TextStyle(color: AppColors.error))),
          ],
        ),
      ),
    );
  }
}
