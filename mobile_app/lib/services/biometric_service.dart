import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Device-local unlock only. Server authorization is still checked after success.
class BiometricService {
  BiometricService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  Future<bool> isBiometricAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final canCheck = await _auth.canCheckBiometrics;
      final enrolled = await _auth.getAvailableBiometrics();
      return canCheck && enrolled.isNotEmpty;
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
      if (!await isBiometricAvailable()) return false;
      return await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
