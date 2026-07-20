// ==================================================================
// FITUR: Identitas Instalasi Aplikasi
// Pengenal acak per-instal yang dilampirkan pada bukti absensi.
// ==================================================================
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// DeviceInstallId
/// ---------------------------------------------------------------------------
/// Pengenal acak yang dibuat sekali saat aplikasi pertama dipakai, lalu
/// disimpan di penyimpanan terenkripsi.
///
/// SENGAJA BUKAN identitas perangkat keras (IMEI/Android ID): nomor seperti itu
/// adalah data pribadi yang melekat permanen pada seseorang, dan kita tidak
/// membutuhkannya. Yang diperlukan server hanya kemampuan melihat bahwa satu
/// akun tiba-tiba absen dari instalasi yang berbeda -- pola yang layak ditinjau
/// admin. Karena acak, ia tidak bisa dipakai melacak orangnya lintas aplikasi,
/// dan hilang begitu aplikasi dihapus.
///
/// Nilai ini BUKAN kontrol keamanan: aplikasi yang dimodifikasi bisa
/// mengirimkan nilai apa pun. Ia sinyal untuk audit, bukan gerbang.
class DeviceInstallId {
  static const String _key = 'device_install_id';

  static String? _cached;

  /// Storage sendiri, bukan menumpang SecureTokenStorage: kelas itu sengaja
  /// hanya mengurus token sesi, dan id instalasi punya daur hidup berbeda --
  /// ia harus bertahan melewati logout.
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Mengembalikan id instalasi, membuatnya bila belum ada.
  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;

    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }

    final baru = _generate();
    await _storage.write(key: _key, value: baru);
    _cached = baru;
    return baru;
  }

  /// 128 bit dari Random.secure, dikodekan base64url tanpa padding.
  static String _generate() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
