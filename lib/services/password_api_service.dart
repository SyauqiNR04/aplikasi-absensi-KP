// ==================================================================
// FITUR: Layanan API Ganti Password
// Mengirim permintaan ganti password lewat kanal ter-pin + token aman.
// ==================================================================
import 'dart:convert';

import '../core/security/certificate_pinning.dart';
import 'secure_token_storage.dart';

class PasswordApiService {
  static const String _baseUrl = 'https://api.example.com/api';

  /// Mengembalikan (sukses, pesan). Menangani validasi 422 dari server.
  Future<(bool, String)> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final client = await PinnedHttpClient.create();
    final token = await SecureTokenStorage.instance.readToken();
    if (token == null) {
      return (false, 'Sesi berakhir. Silakan login kembali.');
    }

    try {
      final res = await client.post(
        Uri.parse('$_baseUrl/password'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'current_password': currentPassword,
          'password': newPassword,
          'password_confirmation': confirmPassword,
        }),
      );

      final body = _tryDecode(res.body);
      if (res.statusCode == 200) {
        return (true, (body['message'] as String?) ?? 'Password diperbarui.');
      }

      // 422: ambil pesan validasi pertama bila ada.
      final errors = body['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return (false, first.first.toString());
      }
      return (false, (body['message'] as String?) ?? 'Gagal memperbarui password.');
    } catch (e) {
      return (false, 'Terjadi kesalahan jaringan.');
    }
  }

  Map<String, dynamic> _tryDecode(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }
}
