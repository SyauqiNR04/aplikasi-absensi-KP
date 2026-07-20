// ==================================================================
// FITUR: Layanan API Ganti Password
// Mengirim permintaan ganti password memakai sesi yang sama dengan
// layar lain (SessionManager), dengan pengaman TLS untuk build rilis.
// ==================================================================
import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;

import 'session_manager.dart';

class PasswordApiService {
  // Satu sumber alamat server dengan layar lain, supaya saat IP backend
  // berubah tidak ada endpoint yang tertinggal memakai host lama.
  static String get _baseUrl => '${SessionManager.baseUrl}/api';

  /// Mengembalikan (sukses, pesan). Menangani validasi 422 dari server.
  Future<(bool, String)> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    // PENGAMAN RILIS. Certificate pinning dilepas agar bisa menembak backend
    // HTTP di LAN saat pengembangan (asset assets/certs/server_ca.pem belum
    // ada). Request ini membawa password lama DAN baru, jadi di atas HTTP
    // polos isinya terbaca siapa pun yang menyadap jaringan.
    //
    // Pemeriksaan di bawah memastikan kompromi itu tidak pernah ikut terbawa
    // ke tangan pengguna: build rilis menolak jalan kalau server bukan HTTPS.
    // Saat backend produksi sudah ber-TLS, pasang kembali PinnedHttpClient
    // (lihat core/security/certificate_pinning.dart) beserta asset PEM-nya.
    if (kReleaseMode && !Uri.parse(_baseUrl).isScheme('https')) {
      return (
        false,
        'Konfigurasi tidak aman: ganti password membutuhkan koneksi HTTPS.',
      );
    }

    // Seluruh proses dibungkus try: sebelumnya penyiapan client & token
    // berada di luar try, sehingga kegagalannya lolos sebagai unhandled
    // exception dan membuat tombol simpan macet dengan spinner tanpa pesan.
    try {
      final token = await SessionManager.token();
      if (token == null || token.isEmpty) {
        return (false, 'Sesi berakhir. Silakan login kembali.');
      }

      final res = await http
          .post(
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
          )
          .timeout(const Duration(seconds: 8));

      final body = _tryDecode(res.body);
      if (res.statusCode == 200) {
        return (true, (body['message'] as String?) ?? 'Password diperbarui.');
      }

      if (res.statusCode == 401) {
        return (false, 'Sesi berakhir. Silakan login kembali.');
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
