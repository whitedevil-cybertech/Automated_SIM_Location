import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'core/theme/app_theme.dart';
import 'screens/home_screen.dart';

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.137.1:8000/api/v1',
);
// Development only: supply the backend's authorized development token at run time.
const _apiAuthToken = String.fromEnvironment(
  'API_AUTH_TOKEN',
  defaultValue: '',
);
const _officerAuthToken = String.fromEnvironment(
  'OFFICER_AUTH_TOKEN',
  defaultValue: '',
);
const _ioDeviceId = String.fromEnvironment(
  'IO_DEVICE_ID',
  defaultValue: 'IO-DEVICE-DEV-001',
);
const _simSlotIndex = int.fromEnvironment('SIM_SLOT_INDEX', defaultValue: 0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IfsoApp());
}

/// Root Application Widget for IFSO Location Request Management System.
class IfsoApp extends StatelessWidget {
  const IfsoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService(
      baseUrl: _apiBaseUrl,
      authToken: _apiAuthToken,
    );
    final officerApiService = ApiService(
      baseUrl: _apiBaseUrl,
      authToken: _officerAuthToken,
    );

    return MaterialApp(
      title: 'IFSO Location Request Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: HomeScreen(
        apiService: apiService,
        officerApiService: officerApiService,
        ioDeviceId: _ioDeviceId,
        simSlotIndex: _simSlotIndex,
      ),
    );
  }
}
