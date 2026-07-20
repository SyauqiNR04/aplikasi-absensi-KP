// ==================================================================
// FITUR: Layanan API Absensi
// Merangkai kontrol keamanan klien: integritas perangkat, pinning, token, dan
// pengiriman bukti verifikasi wajah.
// ==================================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;

import '../core/security/certificate_pinning.dart';
import '../core/security/device_security.dart';
import 'device_install_id.dart';
import 'session_manager.dart';

/// Hasil pengiriman absensi dalam bentuk yang bisa langsung dipakai UI.
///
/// Sengaja BUKAN exception untuk kegagalan yang wajar (di luar geo-fence, wajah
/// tidak cocok, sudah absen dua kali): itu jawaban normal dari server yang
/// perlu ditampilkan apa adanya, bukan kondisi luar biasa. Exception hanya
/// untuk yang benar-benar tak terduga.
class AttendanceSubmitResult {
  final bool success;

  /// Pesan siap tampil. Untuk kegagalan, diambil dari server bila ada.
  final String message;

  /// Isi `data` dari respons sukses (type, jarak_meter, total_jam_kerja, ...).
  final Map<String, dynamic>? data;

  /// True bila server menjawab 401 -- pemanggil harus memaksa logout.
  final bool sessionExpired;

  const AttendanceSubmitResult({
    required this.success,
    required this.message,
    this.data,
    this.sessionExpired = false,
  });
}

/// Dilempar saat perangkat dinilai tidak layak (root/emulator/Fake GPS) atau
/// konfigurasi jaringannya tidak aman untuk build rilis.
class AttendanceBlockedException implements Exception {
  final String message;
  const AttendanceBlockedException(this.message);

  @override
  String toString() => message;
}

/// AttendanceApiService
/// ---------------------------------------------------------------------------
/// Satu-satunya jalur pengiriman absensi. Sebelumnya kelas ini ada tetapi tidak
/// dipakai siapa pun -- layar kamera merakit request-nya sendiri -- sehingga
/// gerbang integritas perangkat dan pinning di sini tidak pernah benar-benar
/// berjalan pada alur absensi. Semua pengiriman kini melewati kelas ini.
///
/// Urutan kontrol:
///   1. Gerbang integritas perangkat (root/emulator/Fake GPS) -> blokir dini.
///   2. Kanal: pinning saat HTTPS; build rilis menolak server non-HTTPS.
///   3. Token sesi dari SessionManager (sumber yang sama dengan layar lain).
///   4. Play Integrity token lewat header X-Integrity-Token (opsional).
///   5. Flag integritas & bukti verifikasi wajah ikut dikirim (zero-trust:
///      server yang menilai, bukan aplikasi).
class AttendanceApiService {
  /// Satu sumber alamat server dengan layar lain, supaya saat IP backend
  /// berubah tidak ada endpoint yang tertinggal memakai host lama.
  static String get _baseUrl => '${SessionManager.baseUrl}/api';

  Future<AttendanceSubmitResult> submitAttendance({
    required double latitude,
    required double longitude,
    required File foto,
    required double? faceMatchScore,
    required double faceMatchThreshold,
    required bool livenessPassed,
    required List<String> livenessChallenges,
    String? integrityToken,
  }) async {
    // (1) Gerbang integritas perangkat.
    final status = await DeviceSecurity.check();
    if (!status.isTrustworthy) {
      throw AttendanceBlockedException(
        status.blockReason ?? 'Perangkat tidak aman.',
      );
    }

    // (2) PENGAMAN RILIS -- alasan lengkap sama dengan PasswordApiService:
    // pinning dilepas agar bisa menembak backend HTTP di LAN saat
    // pengembangan (asset assets/certs/server_ca.pem belum ada). Payload ini
    // membawa foto wajah dan koordinat, jadi di atas HTTP polos isinya
    // terbaca siapa pun yang menyadap jaringan. Build rilis menolak jalan
    // kalau server bukan HTTPS, supaya kompromi pengembangan itu tidak pernah
    // ikut terbawa ke tangan pengguna.
    final isHttps = Uri.parse(_baseUrl).isScheme('https');
    if (kReleaseMode && !isHttps) {
      throw const AttendanceBlockedException(
        'Konfigurasi tidak aman: absensi membutuhkan koneksi HTTPS.',
      );
    }

    // Pinning hanya bermakna di atas TLS. Karena rilis sudah dipagari HTTPS di
    // atas, jalur tanpa pinning hanya mungkin terjadi saat pengembangan.
    final client = isHttps ? await PinnedHttpClient.create() : http.Client();

    try {
      // (3) Token sesi.
      final token = await SessionManager.token();
      if (token == null || token.isEmpty) {
        return const AttendanceSubmitResult(
          success: false,
          message: 'Sesi berakhir. Silakan login kembali.',
          sessionExpired: true,
        );
      }

      final deviceId = await DeviceInstallId.get();
      final capturedAt = DateTime.now().toUtc().toIso8601String();

      // Dibangun ulang tiap percobaan: MultipartRequest sekali pakai --
      // stream berkasnya sudah habis terbaca setelah dikirim, sehingga
      // request yang sama tidak bisa diulang untuk percobaan kedua.
      Future<http.Response> kirim(String bearer) async {
        final request =
            http.MultipartRequest('POST', Uri.parse('$_baseUrl/attendances'))
              ..headers['Authorization'] = 'Bearer $bearer'
              ..headers['Accept'] = 'application/json';

        if (integrityToken != null) {
          request.headers['X-Integrity-Token'] = integrityToken; // (4)
        }

        request.fields['latitude'] = latitude.toString();
        request.fields['longitude'] = longitude.toString();
        status.toApiFlags().forEach((k, v) => request.fields[k] = v.toString());

        // (5) Bukti verifikasi wajah. Yang dikirim adalah skor MENTAH, bukan
        // kesimpulan lolos/tidak: ambang penentu dipegang server, karena
        // aplikasi bisa dimodifikasi.
        if (faceMatchScore != null) {
          request.fields['face_match_score'] = faceMatchScore.toString();
        }
        request.fields['face_match_threshold'] = faceMatchThreshold.toString();
        request.fields['liveness_passed'] = livenessPassed.toString();
        for (var i = 0; i < livenessChallenges.length; i++) {
          request.fields['liveness_challenges[$i]'] = livenessChallenges[i];
        }
        request.fields['device_id'] = deviceId;
        request.fields['client_captured_at'] = capturedAt;

        request.files.add(await http.MultipartFile.fromPath('foto', foto.path));

        final streamed = await client.send(request).timeout(
              const Duration(seconds: 30),
            );
        return http.Response.fromStream(streamed);
      }

      var response = await kirim(token);

      // Token kedaluwarsa -> rotasi sekali lalu ulangi, supaya karyawan tidak
      // terlempar ke layar login hanya karena masa berlaku token habis tepat
      // saat ia menekan tombol absen.
      if (response.statusCode == 401) {
        final baru = await _refreshToken(client, token);
        if (baru != null) {
          await SessionManager.saveToken(baru);
          response = await kirim(baru);
        }
      }

      final body = _tryDecode(response.body);

      if (response.statusCode == 401) {
        return const AttendanceSubmitResult(
          success: false,
          message: 'Sesi berakhir. Silakan login kembali.',
          sessionExpired: true,
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AttendanceSubmitResult(
          success: true,
          message: (body['message'] as String?) ?? 'Absensi berhasil direkam.',
          data: body['data'] is Map<String, dynamic> ? body['data'] : null,
        );
      }

      // Pesan server dipakai apa adanya: ia sudah menjelaskan sebabnya
      // (di luar area kantor, wajah tidak cocok, sudah absen dua kali).
      return AttendanceSubmitResult(
        success: false,
        message: (body['message'] as String?) ?? 'Absensi gagal direkam.',
      );
    } finally {
      // Client pinning di-cache dan dipakai ulang, jadi jangan ditutup di
      // sini; hanya client sementara jalur pengembangan yang perlu dilepas.
      if (!isHttps) client.close();
    }
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
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        // Server membungkus token di dalam 'data' (lihat AuthController::
        // issueToken), bukan di akar respons.
        final data = _tryDecode(res.body)['data'];
        final token = data is Map ? data['token'] : null;
        return token is String && token.isNotEmpty ? token : null;
      }
    } catch (_) {
      // Rotasi gagal -> pemanggil tetap melihat 401 dan meminta login ulang.
    }
    return null;
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
