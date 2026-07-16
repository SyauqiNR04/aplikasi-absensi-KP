// ==================================================================
// FITUR: Play Integrity Client
// Meminta token attestation dari Google Play untuk diverifikasi server.
// ==================================================================
import 'package:app_device_integrity/app_device_integrity.dart';

/// AttestationService
/// ---------------------------------------------------------------------------
/// Meminta token Play Integrity dari Google Play (Android) untuk dikirim ke
/// server dan diverifikasi (lihat PlayIntegrityService di backend). Berbeda
/// dari DeviceSecurity yang berjalan lokal dan bisa di-bypass, verdict Play
/// Integrity ditandatangani Google -> sulit dipalsukan.
///
/// PRASYARAT (pubspec.yaml):
///   app_device_integrity: ^1.1.0
/// dan konfigurasi Cloud Project number di Google Play Console. Di iOS paket
/// ini memakai App Attest dan mengabaikan cloudProjectNumber.
///
/// `nonce` HARUS unik per-request dan idealnya berasal dari server
/// (challenge-response) agar tahan replay attack. Di sini kita contohkan
/// nonce berbasis waktu + payload; produksi sebaiknya ambil nonce dari server.
class AttestationService {
  final AppDeviceIntegrity _plugin = AppDeviceIntegrity();

  /// Cloud project number dari Google Play Console.
  final int cloudProjectNumber;

  AttestationService({required this.cloudProjectNumber});

  /// Mengembalikan integrity token, atau null bila gagal (mis. non-Android).
  Future<String?> requestToken({required String nonce}) async {
    try {
      return await _plugin.getAttestationServiceSupport(
        challengeString: nonce,
        gcp: cloudProjectNumber,
      );
    } catch (_) {
      // Fail-safe: kembalikan null; server akan menolak (fail-closed) bila
      // attestation diwajibkan.
      return null;
    }
  }
}
