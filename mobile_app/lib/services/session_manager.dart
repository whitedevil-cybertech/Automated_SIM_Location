import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthSession {
  const AuthSession({
    required this.token,
    required this.principalId,
    required this.role,
    this.isBiometricEnabled = false,
  });

  final String token;
  final String principalId;
  final String role;
  final bool isBiometricEnabled;

  Map<String, dynamic> toJson() => {
        'token': token,
        'principal_id': principalId,
        'role': role,
        'is_biometric_enabled': isBiometricEnabled,
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token'] as String,
      principalId: json['principal_id'] as String,
      role: json['role'] as String,
      isBiometricEnabled: json['is_biometric_enabled'] as bool? ?? false,
    );
  }

  AuthSession copyWith({
    String? token,
    String? principalId,
    String? role,
    bool? isBiometricEnabled,
  }) {
    return AuthSession(
      token: token ?? this.token,
      principalId: principalId ?? this.principalId,
      role: role ?? this.role,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
    );
  }
}

abstract class SecureStorageAdapter {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
  Future<void> deleteAll();
}

class DefaultSecureStorageAdapter implements SecureStorageAdapter {
  DefaultSecureStorageAdapter([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  final Map<String, String> _memoryFallback = {};

  @override
  Future<String?> read({required String key}) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      return _memoryFallback[key];
    } on MissingPluginException {
      return _memoryFallback[key];
    } catch (_) {
      return _memoryFallback[key];
    }
  }

  @override
  Future<void> write({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException {
      _memoryFallback[key] = value;
    } on MissingPluginException {
      _memoryFallback[key] = value;
    } catch (_) {
      _memoryFallback[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    _memoryFallback.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
    _memoryFallback.clear();
  }
}

class SessionManager {
  SessionManager({SecureStorageAdapter? storage})
      : _storage = storage ?? DefaultSecureStorageAdapter();

  final SecureStorageAdapter _storage;

  static const _keySession = 'ifso_auth_session';
  static const _keyHasSeenWelcome = 'ifso_has_seen_welcome';

  Future<AuthSession?> getSession() async {
    final raw = await _storage.read(key: _keySession);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        return AuthSession.fromJson(map);
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveSession(AuthSession session) async {
    final raw = jsonEncode(session.toJson());
    await _storage.write(key: _keySession, value: raw);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _keySession);
  }

  Future<bool> hasSeenWelcome() async {
    final val = await _storage.read(key: _keyHasSeenWelcome);
    return val == 'true';
  }

  Future<void> setHasSeenWelcome(bool seen) async {
    await _storage.write(key: _keyHasSeenWelcome, value: seen ? 'true' : 'false');
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final session = await getSession();
    if (session != null) {
      await saveSession(session.copyWith(isBiometricEnabled: enabled));
    }
  }
}
