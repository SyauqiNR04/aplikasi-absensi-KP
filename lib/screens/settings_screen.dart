import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_styles.dart';
import '../features/auth/change_password_screen.dart';
import '../services/office_settings_service.dart';
import '../services/session_manager.dart';
import '../services/user_profile_service.dart';
import '../widgets/custom_bottom_nav.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Kunci preferensi dari toggle Biometric dan Push Notifications yang sudah
  /// dihapus dari UI. Ketiganya tidak pernah dibaca fitur apa pun, jadi
  /// nilainya dibersihkan agar tidak menetap sebagai data yatim di perangkat
  /// yang sempat memakainya.
  static const _prefUsang = ['pref_biometric_enabled', 'pref_push_enabled'];

  bool _isLoggingOut = false;

  // Data profil dari GET /api/user.
  bool _isLoadingProfile = true;
  String _nama = '-';
  String _nip = '-';
  String _jabatan = '-';
  Uint8List? _fotoProfil;

  // Aturan absensi dari GET /api/settings. Null selama dimuat atau bila gagal.
  OfficeSettings? _office;

  @override
  void initState() {
    super.initState();
    _bersihkanPreferensiUsang();
    _fetchUserProfile();
    _fetchOfficeSettings();
  }

  Future<void> _fetchOfficeSettings() async {
    final office = await OfficeSettingsService.fetch();
    if (!mounted) return;
    setState(() => _office = office);
  }

  Future<void> _bersihkanPreferensiUsang() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _prefUsang) {
      await prefs.remove(key);
    }
  }

  // === PROFIL PENGGUNA ===

  Future<void> _fetchUserProfile() async {
    if (mounted) setState(() => _isLoadingProfile = true);

    final hasil = await UserProfileService.fetch();
    if (!mounted) return;

    switch (hasil.status) {
      case ProfileStatus.unauthorized:
        setState(() => _isLoadingProfile = false);
        await SessionManager.forceLogout(context);
        return;
      case ProfileStatus.failed:
        setState(() => _isLoadingProfile = false);
        _tampilkanPesan(hasil.message ?? 'Gagal memuat profil.');
        return;
      case ProfileStatus.ok:
        setState(() {
          _nama = hasil.profile!.nama;
          _nip = hasil.profile!.nip;
          _jabatan = hasil.profile!.jabatan;
          _isLoadingProfile = false;
        });
    }

    // Foto menyusul agar nama tidak ikut tertahan menunggu unduhan gambar.
    final foto = await UserProfileService.fetchPhoto();
    if (!mounted || foto == null) return;
    setState(() => _fotoProfil = foto);
  }

  // === LOGOUT ===

  Future<void> _logout() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Konfirmasi Logout'),
        content: const Text('Apakah Anda yakin ingin keluar dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Tidak'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ya, Logout'),
          ),
        ],
      ),
    );

    if (konfirmasi != true || !mounted) return;

    setState(() => _isLoggingOut = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token != null && token.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('${SessionManager.baseUrl}/api/logout'),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Tetap hapus sesi lokal walau server tidak terjangkau.
      }
    }

    await prefs.remove('token');
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  void _tampilkanPesan(String pesan) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  void _keChangePassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgScaffold,
      bottomNavigationBar: const CustomBottomNav(
        activeIndex: 3,
      ), // Index 3 untuk Settings
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // HEADER
              const Text(
                "Settings",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 24),

              // PROFILE CARD
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(
                    left: BorderSide(color: AppColors.darkGreen, width: 4),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppColors.borderLight,
                      backgroundImage: _fotoProfil != null
                          ? MemoryImage(_fotoProfil!)
                          : null,
                      child: _fotoProfil == null
                          ? const Icon(
                              Icons.person,
                              size: 32,
                              color: AppColors.darkGreen,
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _isLoadingProfile
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.darkGreen,
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _nama,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _nip,
                                  style: const TextStyle(
                                    color: AppColors.textGrey,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _jabatan,
                                  style: const TextStyle(
                                    color: AppColors.accentGreen,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    ElevatedButton(onPressed: () {}, child: const Text("Edit")),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // SECTIONS
              _buildSectionTitle("ACCOUNT SETTINGS"),
              _buildSettingItem(
                Icons.lock,
                "Change Password",
                Icons.chevron_right,
                _keChangePassword,
              ),

              // Aturan absensi ditampilkan hanya bila berhasil dimuat; ini
              // data pelengkap, jadi kegagalannya cukup disembunyikan.
              if (_office != null) ...[
                const SizedBox(height: 24),
                _buildSectionTitle("INFO KERJA"),
                _buildInfoItem(
                  Icons.business,
                  "Lokasi Kantor",
                  _office!.namaLokasi,
                ),
                _buildInfoItem(
                  Icons.schedule,
                  "Jam Kerja",
                  "${_office!.jamMasuk} - ${_office!.jamPulang}",
                ),
                _buildInfoItem(
                  Icons.my_location,
                  "Radius Absensi",
                  "${_office!.radiusMeter} meter",
                ),
                if (_office!.aturanTambahan != null &&
                    _office!.aturanTambahan!.isNotEmpty)
                  _buildInfoItem(
                    Icons.info_outline,
                    "Aturan Tambahan",
                    _office!.aturanTambahan!,
                  ),
              ],

              const SizedBox(height: 24),

              // LOGOUT BUTTON
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(double.infinity, 56),
                ),
                onPressed: _isLoggingOut ? null : _logout,
                icon: _isLoggingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout),
                label: Text(
                  _isLoggingOut ? "Logging out..." : "Logout",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: AppColors.textGrey,
        letterSpacing: 1.2,
      ),
    ),
  );

  /// Baris info baca-saja. Sengaja tanpa InkWell/chevron agar tidak terlihat
  /// bisa ditekan — aturan ini ditetapkan admin, karyawan tidak bisa mengubah.
  Widget _buildInfoItem(IconData icon, String label, String value) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.darkGreen),
        const SizedBox(width: 16),
        Text(label, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textGrey,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildSettingItem(
    IconData icon,
    String title,
    IconData trailing,
    VoidCallback onTap,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    // Material + InkWell agar efek ripple ikut terpotong radius kartu.
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: AppColors.darkGreen),
              const SizedBox(width: 16),
              Text(title, style: const TextStyle(fontSize: 16)),
              const Spacer(),
              Icon(trailing, color: AppColors.textGrey),
            ],
          ),
        ),
      ),
    ),
  );
}
