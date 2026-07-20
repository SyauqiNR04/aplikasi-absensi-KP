// ==================================================================
// FITUR: Profil Pengguna
// Mengambil identitas karyawan (nama, NIP, foto) dari GET /api/user
// untuk dipakai bersama oleh Dashboard dan Settings.
// ==================================================================
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'session_manager.dart';

/// Identitas karyawan yang sedang login.
class UserProfile {
  final String nama;
  final String nip;
  final String jabatan;

  const UserProfile({
    required this.nama,
    required this.nip,
    required this.jabatan,
  });
}

enum ProfileStatus {
  /// Data berhasil diambil.
  ok,

  /// Token hilang/kedaluwarsa — pemanggil harus memaksa logout.
  unauthorized,

  /// Jaringan bermasalah atau server membalas error.
  failed,
}

class ProfileResult {
  final ProfileStatus status;
  final UserProfile? profile;
  final String? message;

  const ProfileResult(this.status, {this.profile, this.message});
}

/// Sumber tunggal data profil. Sebelumnya tiap layar menulis sendiri nama
/// dan foto pengguna secara hardcode, sehingga Dashboard dan Settings bisa
/// menampilkan orang yang berbeda.
class UserProfileService {
  /// Mengambil nama & NIP. Tidak pernah melempar exception.
  static Future<ProfileResult> fetch() async {
    try {
      final token = await SessionManager.token();
      if (token == null || token.isEmpty) {
        return const ProfileResult(ProfileStatus.unauthorized);
      }

      final res = await http
          .get(
            Uri.parse('${SessionManager.baseUrl}/api/user'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 401) {
        return const ProfileResult(ProfileStatus.unauthorized);
      }
      if (res.statusCode != 200) {
        return ProfileResult(
          ProfileStatus.failed,
          message: 'Gagal memuat profil (${res.statusCode}).',
        );
      }

      final data = jsonDecode(res.body)['data'];
      return ProfileResult(
        ProfileStatus.ok,
        profile: UserProfile(
          nama: (data?['nama_lengkap'] as String?) ?? '-',
          nip: (data?['nip'] as String?) ?? '-',
          jabatan: (data?['jabatan'] as String?) ?? '-',
        ),
      );
    } on FormatException {
      return const ProfileResult(
        ProfileStatus.failed,
        message: 'Respons server tidak valid.',
      );
    } catch (_) {
      return const ProfileResult(
        ProfileStatus.failed,
        message: 'Gagal terhubung ke server.',
      );
    }
  }

  /// Foto profil sebagai bytes. Kolom `foto_referensi` di server berisi path
  /// pada disk privat, bukan URL publik, jadi gambar hanya bisa diambil lewat
  /// endpoint ber-otentikasi ini — `NetworkImage` tidak akan bisa memuatnya.
  ///
  /// Mengembalikan null bila foto belum diunggah admin (404) atau gagal
  /// diunduh; itu kondisi normal, bukan error yang perlu ditampilkan.
  static Future<Uint8List?> fetchPhoto() async {
    try {
      final token = await SessionManager.token();
      if (token == null || token.isEmpty) return null;

      final res = await http
          .get(
            Uri.parse('${SessionManager.baseUrl}/api/reference-photo'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
