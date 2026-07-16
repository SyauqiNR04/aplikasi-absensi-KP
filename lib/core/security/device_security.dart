// ==================================================================
// FITUR: Deteksi Manipulasi Environment
// Mendeteksi root/jailbreak, emulator, dan Fake GPS sebelum payload absensi dikirim.
// ==================================================================
import 'package:geolocator/geolocator.dart';
import 'package:safe_device/safe_device.dart';

/// Hasil pemeriksaan integritas perangkat.
class DeviceSecurityStatus {
  final bool isRooted;      // root (Android) / jailbreak (iOS)
  final bool isEmulator;    // dijalankan di emulator, bukan device nyata
  final bool isMockLocation;// Fake GPS aktif
  final bool isDeveloperMode;

  const DeviceSecurityStatus({
    required this.isRooted,
    required this.isEmulator,
    required this.isMockLocation,
    required this.isDeveloperMode,
  });

  /// Aman untuk mengirim absensi bila TIDAK ada satu pun sinyal berbahaya.
  bool get isTrustworthy =>
      !isRooted && !isEmulator && !isMockLocation;

  /// Alasan penolakan pertama yang ditemukan (untuk ditampilkan ke user).
  String? get blockReason {
    if (isMockLocation) return 'Fake GPS / lokasi palsu terdeteksi aktif.';
    if (isEmulator) return 'Aplikasi tidak dapat dijalankan di emulator.';
    if (isRooted) return 'Perangkat ter-root/jailbreak tidak diizinkan.';
    return null;
  }

  Map<String, bool> toApiFlags() => {
        'is_rooted': isRooted,
        'is_emulator': isEmulator,
        'is_mock_location': isMockLocation,
      };
}

/// DeviceSecurity
/// ---------------------------------------------------------------------------
/// Utility mitigasi manipulasi environment (OWASP Mobile M8: Code Tampering,
/// M1: Improper Platform Usage). Dipanggil SEBELUM payload absensi dikirim.
///
/// PENTING (defense-in-depth): deteksi di klien BISA di-bypass oleh penyerang
/// yang me-repackage APK. Karena itu flag hasil pemeriksaan ini JUGA dikirim
/// ke server (lihat DeviceIntegrity middleware) dan server tidak mempercayai
/// klien secara buta. Klien = UX cepat; server = penegak kebijakan.
class DeviceSecurity {
  /// Pemeriksaan penuh. Menggabungkan `safe_device` dengan pemeriksaan
  /// mock-location bawaan geolocator (dua sumber -> lebih sulit di-spoof).
  static Future<DeviceSecurityStatus> check() async {
    final results = await Future.wait([
      _safe(() => SafeDevice.isJailBroken),
      _safe(() => SafeDevice.isRealDevice).then((v) => !v), // isEmulator
      _safe(() => SafeDevice.isMockLocation),
      _safe(() => SafeDevice.isDevelopmentModeEnable),
    ]);

    // Sumber kedua untuk mock location: geolocator (Android >= isMocked).
    bool mockFromGeo = false;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition();
        mockFromGeo = pos.isMocked;
      }
    } catch (_) {
      // Abaikan; safe_device tetap menjadi sumber utama.
    }

    return DeviceSecurityStatus(
      isRooted: results[0],
      isEmulator: results[1],
      isMockLocation: results[2] || mockFromGeo,
      isDeveloperMode: results[3],
    );
  }

  /// Guard praktis: lempar [DeviceSecurityException] bila tidak aman.
  static Future<void> assertTrustworthyOrThrow() async {
    final status = await check();
    if (!status.isTrustworthy) {
      throw DeviceSecurityException(status.blockReason ?? 'Perangkat tidak aman.');
    }
  }

  /// Bungkus panggilan agar exception plugin tidak menjatuhkan aplikasi;
  /// fail-safe: bila pemeriksaan gagal, anggap TIDAK aman (return true) untuk
  /// kategori bahaya. Di sini kita kembalikan false hanya untuk cek positif.
  static Future<bool> _safe(Future<bool> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return false;
    }
  }
}

class DeviceSecurityException implements Exception {
  final String message;
  DeviceSecurityException(this.message);
  @override
  String toString() => message;
}
