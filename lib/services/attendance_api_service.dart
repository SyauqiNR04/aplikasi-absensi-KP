// ==================================================================
// FITUR: Layanan API Absensi
// Merangkai kontrol keamanan klien: integritas perangkat, pinning, token aman, attestation, dan auto-refresh.
// ==================================================================
import 'dart:io';
import 'package:http/http.dart' as http;

import '../core/security/certificate_pinning.dart';
import '../core/security/device_security.dart';
import 'secure_token_storage.dart';

/// AttendanceApiService
/// ---------------------------------------------------------------------------
/// Merangkai seluruh kontrol keamanan klien saat submit absensi:
///   1. Cek integritas perangkat (root/emulator/Fake GPS) -> blokir dini.
///   2. Kanal terproteksi certificate pinning (anti-MITM).
///   3. Token dari secure storage (bukan shared_preferences).
///   4. Play Integrity token dikirim via header X-Integrity-Token (Phase 3).
///   5. Auto-refresh token bila server menjawab 401.
///   6. Kirim flag integritas ke server (zero-trust).
class AttendanceApiService {
  static const String _baseUrl = 'https://api.example.com/api';

  Future<Map<String, dynamic>> submitAttendance({
    required double latitude,
    required double longitude,
    required File foto,
    String? integrityToken, // dari AttestationService (opsional saat rollout)
  }) async {
    // (1) Gerbang integritas perangkat.
    final status = await DeviceSecurity.check();
    if (!status.isTrustworthy) {
      throw DeviceSecurityException(status.blockReason ?? 'Perangkat tidak aman.');
    }

    // (2) Client dengan certificate pinning.
    final client = await PinnedHttpClient.create();

    // (3) Token dari penyimpanan terenkripsi.
    final token = await SecureTokenStorage.instance.readToken();
    if (token == null) {
      throw Exception('Sesi berakhir. Silakan login kembali.');
    }

    Future<http.Response> send(String bearer) async {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/attendances'));
      request.headers['Authorization'] = 'Bearer $bearer';
      request.headers['Accept'] = 'application/json';
      if (integrityToken != null) {
        request.headers['X-Integrity-Token'] = integrityToken; // (4)
      }
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
      status.toApiFlags().forEach((k, v) => request.fields[k] = v.toString());
      request.files.add(await http.MultipartFile.fromPath('foto', foto.path));
      final streamed = await client.send(request);
      return http.Response.fromStream(streamed);
    }

    var response = await send(token);

    // (5) Token kedaluwarsa -> refresh sekali lalu ulangi.
    if (response.statusCode == 401) {
      final refreshed = await _refreshToken(client, token);
      if (refreshed != null) {
        await SecureTokenStorage.instance.saveToken(refreshed);
        response = await send(refreshed);
      } else {
        await SecureTokenStorage.instance.deleteToken();
        throw Exception('Sesi berakhir. Silakan login kembali.');
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return {'success': true, 'body': response.body};
    }
    return {'success': false, 'status': response.statusCode, 'body': response.body};
  }

  /// Merotasi token via POST /refresh. Mengembalikan token baru atau null.
  Future<String?> _refreshToken(http.Client client, String currentToken) async {
    try {
      final res = await client.post(
        Uri.parse('$_baseUrl/refresh'),
        headers: {
          'Authorization': 'Bearer $currentToken',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        final match = RegExp('"token"\\s*:\\s*"([^"]+)"').firstMatch(res.body);
        return match?.group(1);
      }
    } catch (_) {}
    return null;
  }
}
