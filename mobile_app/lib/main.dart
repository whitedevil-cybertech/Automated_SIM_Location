import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'core/theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/telephony_bridge.dart';

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.137.1:8000/api/v1',
);
// Development/testing only. Never bake a production access token into an APK.
const _apiAuthToken = String.fromEnvironment('API_AUTH_TOKEN', defaultValue: '');
const _ioDeviceId = String.fromEnvironment('IO_DEVICE_ID', defaultValue: 'IO-DEVICE-DEV-001');
const _simSlotIndex = int.fromEnvironment('SIM_SLOT_INDEX', defaultValue: 0);
final _telephonyBridge = TelephonyBridge();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IfsoApp());
}

class IfsoApp extends StatelessWidget {
  const IfsoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService(baseUrl: _apiBaseUrl, authToken: _apiAuthToken);
    return MaterialApp(
      title: 'IFSO Location Request Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _AuthenticatedHomeGate(
        apiService: apiService,
        ioDeviceId: _ioDeviceId,
        simSlotIndex: _simSlotIndex,
        telephonyBridge: _telephonyBridge,
      ),
    );
  }
}

class _AuthenticatedHomeGate extends StatefulWidget {
  const _AuthenticatedHomeGate({
    required this.apiService,
    required this.ioDeviceId,
    required this.simSlotIndex,
    required this.telephonyBridge,
  });

  final ApiService apiService;
  final String ioDeviceId;
  final int simSlotIndex;
  final TelephonyBridge telephonyBridge;

  @override
  State<_AuthenticatedHomeGate> createState() => _AuthenticatedHomeGateState();
}

class _AuthenticatedHomeGateState extends State<_AuthenticatedHomeGate> {
  late Future<Map<String, dynamic>> _identity;

  @override
  void initState() {
    super.initState();
    _identity = widget.apiService.getCurrentPrincipal();
  }

  void _retry() => setState(() => _identity = widget.apiService.getCurrentPrincipal());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _identity,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('IFSO Location Management')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    const SizedBox(height: 12),
                    const Text('Authentication failed. No operational screens are available.'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _retry, child: const Text('Retry authentication')),
                  ],
                ),
              ),
            ),
          );
        }
        final identity = snapshot.data!;
        final role = (identity['role'] as String).toUpperCase();
        if (!{'OFFICER', 'IO', 'ADMIN'}.contains(role)) {
          return const Scaffold(body: Center(child: Text('Unknown role. Access denied.')));
        }
        return HomeScreen(
          apiService: widget.apiService,
          officerApiService: widget.apiService,
          role: role,
          ioDeviceId: widget.ioDeviceId,
          simSlotIndex: widget.simSlotIndex,
          telephonyBridge: widget.telephonyBridge,
        );
      },
    );
  }
}
