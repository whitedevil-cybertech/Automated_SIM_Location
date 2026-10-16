import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  BiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({
    String localizedReason = 'Verify your identity to unlock your IFSO session',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
