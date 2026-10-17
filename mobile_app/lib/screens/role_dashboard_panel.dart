import 'package:flutter/material.dart';

import '../core/constants/request_states.dart';
import '../core/theme/color_schemes.dart';
import '../core/theme/spacing.dart';
import '../models/location_request.dart';
import '../services/api_service.dart';

/// A role-scoped dashboard panel. Every displayed operational value comes from
/// the authenticated backend; unavailable capabilities are explicitly labelled.
class RoleDashboardPanel extends StatefulWidget {
  const RoleDashboardPanel({
    super.key,
    required this.apiService,
    required this.role,
  });

  final ApiService apiService;
  final String role;

  @override
  State<RoleDashboardPanel> createState() => _RoleDashboardPanelState();
}

class _RoleDashboardPanelState extends State<RoleDashboardPanel> {
  bool _loading = true;
  String? _error;
  List<LocationRequest> _requests = const [];
  Map<String, dynamic> _admin = const {};
  List<Map<String, dynamic>> _pendingAccounts = const [];
  final Set<String> _accountActionsInProgress = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.role == 'ADMIN') {
        final overview = await widget.apiService.getAdminDashboard();
        final recent = overview['recent_requests'];
        final pendingAccounts = await widget.apiService.getAdminAccounts();
        setState(() {
          _admin = overview;
          _pendingAccounts = pendingAccounts;
          _requests = recent is List
              ? recent.whereType<Map>().map((item) =>
                  LocationRequest.fromJson(Map<String, dynamic>.from(item))).toList()
              : const [];
          _loading = false;
        });
      } else if (widget.role == 'OFFICER') {
        final items = await widget.apiService.getMyRequests();
        setState(() {
          _requests = items;
          _loading = false;
        });
      } else if (widget.role == 'IO') {
        final items = await widget.apiService.getIoVisibleRequests();
        setState(() {
          _requests = items;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Unknown role. Dashboard access is denied.';
          _loading = false;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Dashboard data could not be loaded.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = <RequestState, int>{
      for (final state in RequestState.values)
        state: _requests.where((request) => request.status == state).length,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.role == 'ADMIN'
                        ? 'System Overview'
                        : widget.role == 'IO'
                            ? 'IO Request Tracking'
                            : 'My Request Tracking',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh dashboard',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading && _requests.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _requests.isEmpty)
              _errorState(theme)
            else if (widget.role == 'ADMIN')
              _adminSummary(theme)
            else
              _requestSummary(theme, counts),
            if (!_loading && _error == null && _requests.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'No requests are available for this account.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            if (_requests.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                widget.role == 'ADMIN' ? 'Recent Requests' : 'Requests',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final request in _requests.take(10))
                _requestTile(context, request, theme),
            ],
            if (widget.role == 'ADMIN' && !_loading && _error == null) ...[
              _pendingApprovals(theme),
              _adminLimitations(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorState(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error ?? 'Unable to load dashboard.',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ],
      );

  Widget _requestSummary(ThemeData theme, Map<RequestState, int> counts) {
    final summary = widget.role == 'OFFICER'
        ? <RequestState>[
            RequestState.created,
            RequestState.pendingIoReview,
            RequestState.executing,
            RequestState.waitingResponse,
            RequestState.completed,
            RequestState.smsFailed,
            RequestState.timeout,
          ]
        : <RequestState>[
            RequestState.pendingIoReview,
            RequestState.executing,
            RequestState.waitingResponse,
            RequestState.completed,
            RequestState.smsFailed,
            RequestState.timeout,
            RequestState.responseInvalid,
          ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: summary.map((state) => _countChip(
        state.label,
        counts[state] ?? 0,
        state.color,
        state.containerColor,
      )).toList(),
    );
  }

  Widget _adminSummary(ThemeData theme) {
    final stateCounts = _admin['requests_by_state'];
    final operatorCounts = _admin['operator_configurations'];
    final states = stateCounts is Map ? Map<String, dynamic>.from(stateCounts) : <String, dynamic>{};
    final operators = operatorCounts is Map ? Map<String, dynamic>.from(operatorCounts) : <String, dynamic>{};
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _countChip('Total Requests', _admin['request_total'] ?? 0, AppColors.primary, AppColors.primaryContainer),
        for (final entry in states.entries)
          _countChip(entry.key, entry.value, AppColors.secondary, AppColors.surfaceContainer),
        _countChip('Operator Profiles', operators['total'] ?? 0, AppColors.primary, AppColors.primaryContainer),
        _countChip('Active Operators', operators['active'] ?? 0, AppColors.success, AppColors.successContainer),
        _countChip('Inactive Operators', operators['inactive'] ?? 0, AppColors.warning, AppColors.warningContainer),
        _countChip('Recent Audit Events', (_admin['recent_audit_events'] is List) ? (_admin['recent_audit_events'] as List).length : 0, AppColors.secondary, AppColors.surfaceContainer),
      ],
    );
  }

  Widget _countChip(String label, dynamic value, Color foreground, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: foreground.withAlpha(65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value', style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 18)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _requestTile(BuildContext context, LocationRequest request, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(request.requestId, style: theme.textTheme.titleSmall),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Case: ${request.caseId}'),
              Text('Target: ${request.targetPhoneMasked} · ${request.operatorCode}'),
              Text('Created: ${_formatDate(request.createdAt)}'),
              Text('Updated: ${_formatDate(request.updatedAt)}'),
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(request.status.icon, size: 16, color: request.status.color),
                  const SizedBox(width: 5),
                  Text(request.status.label,
                      style: TextStyle(color: request.status.color, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
        onTap: () => _showDetails(context, request),
      ),
    );
  }

  void _showDetails(BuildContext context, LocationRequest request) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request Details'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Request ID: ${request.requestId}\n'
            'Case/FIR: ${request.caseId}\n'
            'Target: ${request.targetPhoneMasked}\n'
            'Operator: ${request.operatorCode}\n'
            'Status: ${request.status.value}\n'
            'Created: ${request.createdAt.toLocal()}\n'
            'Updated: ${request.updatedAt.toLocal()}\n'
            'Requesting officer: ${request.submittingOfficerId ?? 'Not provided'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _pendingApprovals(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Pending Signup Approvals (${_pendingAccounts.length})', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_pendingAccounts.isEmpty)
          const Text('No signup requests are awaiting approval.')
        else
          for (final account in _pendingAccounts)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${account['full_name'] ?? account['user_id']}', style: theme.textTheme.titleSmall),
                  Text('ID: ${account['user_id']} · Role: ${account['requested_role']}'),
                  Text('${account['email']} · ${account['unit']}'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    FilledButton.tonalIcon(
                      onPressed: _accountActionsInProgress.contains('${account['user_id']}') ? null : () => _decideAccount('${account['user_id']}', approve: true),
                      icon: const Icon(Icons.check_circle_outline), label: const Text('Approve'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _accountActionsInProgress.contains('${account['user_id']}') ? null : () => _decideAccount('${account['user_id']}', approve: false),
                      icon: const Icon(Icons.cancel_outlined), label: const Text('Reject'),
                    ),
                  ]),
                ]),
              ),
            ),
      ],
    );
  }

  Future<void> _decideAccount(String userId, {required bool approve}) async {
    setState(() => _accountActionsInProgress.add(userId));
    try {
      await widget.apiService.decideAdminAccount(userId, approve: approve);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Enrollment approved.' : 'Enrollment rejected.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _accountActionsInProgress.remove(userId));
    }
  }

  Widget _adminLimitations(ThemeData theme) {
    final capabilities = _admin['capabilities'];
    final canAdmin = capabilities is Map ? capabilities : const {};
    final events = _admin['recent_audit_events'];
    final eventList = events is List ? events.whereType<Map>().toList() : const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Recent Audit Events', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (eventList.isEmpty)
          const Text('No audit events are recorded.')
        else
          for (final event in eventList)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${event['event_type'] ?? 'Event'}'),
              subtitle: Text('${event['timestamp'] ?? ''} · ${event['actor_role'] ?? ''}'),
              trailing: event['request_id'] == null ? null : Text('${event['request_id']}'),
            ),
        const SizedBox(height: 8),
        Text(
          canAdmin['operator_configuration_mutation'] == true
              ? 'Operator configuration controls are available.'
              : 'Operator configuration editing is not implemented yet. Signup approval is available above; approval records do not themselves issue identity-provider credentials.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} $hour:$minute';
  }
}
