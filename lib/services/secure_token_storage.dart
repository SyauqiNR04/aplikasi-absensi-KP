// ==================================================================
// FITUR: Penyimpanan Token Aman
// Menyimpan token Sanctum di Keystore/Keychain terenkripsi, menggantikan shared_preferences plain-text.
// ==================================================================
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SecureTokenStorage
/// ---------------------------------------------------------------------------
/// Pengganti `shared_preferences` untuk menyimpan token Sanctum.
///
/// MASALAH LAMA: pubspec memakai `shared_preferences`, yang menulis data ke
/// file XML plain-text (Android) / NSUserDefaults (iOS). Pada perangkat root,
/// token bisa dibaca langsung -> pembajakan sesi (OWASP Mobile M9: Insecure
/// Data Storage).
///
/// SOLUSI: `flutter_secure_storage` menyimpan token di:
///   - Android : EncryptedSharedPreferences (AES) yang kuncinya berada di
///               Android Keystore (didukung hardware bila tersedia).
///   - iOS     : Keychain dengan proteksi first-unlock.
///
/// Semua akses token di aplikasi HARUS lewat kelas ini (single source of truth).
class SecureTokenStorage {
  SecureTokenStorage._();
  static final SecureTokenStorage instance = SecureTokenStorage._();

  static const _tokenKey = 'sanctum_token';

  // Konfigurasi enkripsi eksplisit.
  // Sejak flutter_secure_storage v10, Android selalu memakai cipher sendiri
  // dan opsi encryptedSharedPreferences diabaikan, jadi tidak diset lagi.
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      // Token hanya bisa dibaca setelah perangkat pertama kali di-unlock,
      // dan tidak ikut ter-backup ke iCloud/perangkat lain.
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> readToken() async {
    return _storage.read(key: _tokenKey);
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  Future<bool> hasToken() async {
    final token = await _storage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }
}
