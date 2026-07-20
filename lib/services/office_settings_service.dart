// ==================================================================
// FITUR: Pengaturan Kantor
// Mengambil lokasi kantor, jam kerja, dan radius absensi dari
// GET /api/settings — endpoint yang sudah ada tapi belum dipakai klien.
// ==================================================================
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_manager.dart';

/// Aturan absensi yang ditetapkan admin. Nilai-nilai inilah yang dipakai
/// server untuk menilai telat/tidaknya seorang karyawan, jadi menampilkannya
/// membuat aturan itu terlihat oleh yang terkena dampaknya.
class OfficeSettings {
  final String namaLokasi;
  final String jamMasuk;
  final String jamPulang;
  final int radiusMeter;
  final String? aturanTambahan;

  /// Titik pusat geofence. Nullable: bila server mengirim nilai yang tidak bisa
  /// dibaca, lebih baik perhitungan jarak dilewati daripada memakai 0,0 yang
  /// menghasilkan jarak ribuan kilometer dan status "di luar radius" palsu.
  final double? latitude;
  final double? longitude;

  const OfficeSettings({
    required this.namaLokasi,
    required this.jamMasuk,
    required this.jamPulang,
    required this.radiusMeter,
    this.aturanTambahan,
    this.latitude,
    this.longitude,
  });

  bool get punyaKoordinat => latitude != null && longitude != null;
}

class OfficeSettingsService {
  /// Mengembalikan null bila gagal — pemanggil cukup menyembunyikan bagian
  /// ini alih-alih menampilkan error, karena datanya pelengkap, bukan inti.
  ///
  /// Endpoint ini publik (tanpa auth), jadi tidak perlu token.
  static Future<OfficeSettings?> fetch() async {
    try {
      final res = await http
          .get(
            Uri.parse('${SessionManager.baseUrl}/api/settings'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body)['data'];
      if (data == null) return null;

      return OfficeSettings(
        namaLokasi: (data['nama_lokasi'] as String?) ?? '-',
        jamMasuk: _jam(data['jam_masuk'] as String?),
        jamPulang: _jam(data['jam_pulang'] as String?),
        // radius_meter bisa datang sebagai int atau string tergantung driver DB.
        radiusMeter: int.tryParse('${data['radius_meter']}') ?? 0,
        aturanTambahan: data['aturan_tambahan'] as String?,
        latitude: _koordinat(data['latitude']),
        longitude: _koordinat(data['longitude']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Laravel bisa mengirim kolom decimal sebagai angka atau string.
  static double? _koordinat(dynamic raw) {
    if (raw == null) return null;
    return double.tryParse('$raw');
  }

  /// Server mengirim "08:00:00"; detiknya tidak berguna bagi pembaca.
  static String _jam(String? raw) {
    if (raw == null || raw.length < 5) return '--:--';
    return raw.substring(0, 5);
  }
}
