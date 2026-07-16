// ==================================================================
// FITUR: Certificate Pinning
// Membatasi kepercayaan TLS hanya pada CA/leaf server sendiri untuk mencegah MITM.
// ==================================================================
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// PinnedHttpClient
/// ---------------------------------------------------------------------------
/// Certificate pinning untuk mencegah Man-in-the-Middle (OWASP Mobile M3:
/// Insecure Communication). Tanpa pinning, penyerang yang bisa memasang root
/// CA di perangkat (proxy korporat, Wi-Fi jahat, atau perangkat root) dapat
/// mendekripsi & memodifikasi lalu lintas HTTPS — mencuri token dan memalsukan
/// koordinat absensi.
///
/// STRATEGI YANG DIPAKAI DI FILE INI: **trust-anchor pinning**.
/// Kita membuat [SecurityContext] yang HANYA mempercayai sertifikat CA/leaf
/// milik server kita sendiri (di-bundle sebagai asset PEM). Sertifikat yang
/// tidak dirantai ke PEM tersebut — termasuk CA sistem apa pun yang dipasang
/// penyerang — akan ditolak saat handshake TLS. Ini benar-benar ditegakkan
/// oleh engine TLS, bukan sekadar callback.
///
/// `badCertificateCallback` dikembalikan `false` secara eksplisit agar tidak
/// ada jalan pintas untuk menerima sertifikat yang gagal divalidasi.
///
/// PENYIAPAN:
///   1. Ekspor sertifikat server (atau CA penerbitnya) ke PEM:
///        openssl s_client -connect api.example.com:443 -servername api.example.com \
///          < /dev/null 2>/dev/null | openssl x509 -outform PEM > server_ca.pem
///   2. Simpan sebagai asset: assets/certs/server_ca.pem
///   3. Daftarkan di pubspec.yaml:
///        flutter:
///          assets:
///            - assets/certs/server_ca.pem
///   4. Selalu bundle CA cadangan (backup) sebelum rotasi agar pengguna tidak
///      terkunci saat sertifikat di-renew. Rotasi pin lewat update aplikasi.
///
/// ALTERNATIF: untuk SPKI/public-key hash pinning yang tahan renew sertifikat,
/// gunakan paket teruji `http_certificate_pinning` atau `dio` +
/// interceptor pinning. Trust-anchor pinning di sini lebih sederhana dan
/// dependency-free.
class PinnedHttpClient {
  PinnedHttpClient._();

  static const String _certAssetPath = 'assets/certs/server_ca.pem';

  static http.Client? _cached;

  /// Membangun (dan meng-cache) http.Client yang hanya mempercayai CA server.
  static Future<http.Client> create() async {
    if (_cached != null) return _cached!;

    final certBytes = (await rootBundle.load(_certAssetPath)).buffer.asUint8List();

    // Konteks TLS yang tidak mewarisi trust store sistem: withTrustedRoots:false.
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(certBytes);

    final inner = HttpClient(context: context)
      // Bila sertifikat gagal divalidasi terhadap PEM kita -> TOLAK.
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => false;

    _cached = IOClient(inner);
    return _cached!;
  }

  /// Panggil saat logout / rotasi untuk melepas koneksi lama.
  static void dispose() {
    _cached?.close();
    _cached = null;
  }
}
