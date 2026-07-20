// session_manager.dart
//
// Penjaga sesi login. Token Sanctum punya masa berlaku (lihat
// config/sanctum.php -> expiration), sehingga token yang tersimpan di HP
// bisa MATI walau string-nya masih ada di penyimpanan lokal.
//
// Tanpa pemeriksaan ini, app terlihat "masih login" (langsung masuk
// dashboard) padahal setiap request dijawab 401 oleh server, dan kegagalan
// itu muncul sebagai pesan error yang menyesatkan di layar lain
// (mis. "foto referensi bermasalah" saat verifikasi wajah).

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const String baseUrl =
      "http://192.168.100.234/backend-absensi/public";

  static Future<String?> token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  /// Menyimpan token hasil rotasi (POST /api/refresh) ke tempat yang sama
  /// dengan yang dibaca [token], supaya seluruh layar ikut memakai token baru.
  static Future<void> saveToken(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', value);
  }

  /// Verifikasi token ke server. True kalau masih valid.
  /// Kalau server tidak terjangkau, dianggap valid (jangan paksa logout
  /// hanya gara-gara jaringan lagi putus).
  static Future<bool> isTokenValid(String token) async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/api/user'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));
      return res.statusCode != 401;
    } catch (_) {
      return true;
    }
  }

  /// Hapus sesi lokal lalu lempar user ke layar login dengan alasan jelas.
  /// Dipanggil saat ada response 401 dari endpoint mana pun.
  static Future<void> forceLogout(
    BuildContext context, {
    String message = 'Sesi Anda telah berakhir. Silakan login kembali.',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');

    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
