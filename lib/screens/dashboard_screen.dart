import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_styles.dart';
import '../widgets/custom_bottom_nav.dart';
import '../services/office_settings_service.dart';
import '../services/session_manager.dart';
import '../services/user_profile_service.dart';
import 'camera_screen.dart';

/// Posisi pengguna terhadap radius kantor.
enum StatusJangkauan { memuat, didalam, diluar, izinDitolak, tidakDiketahui }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Alamat server memakai SessionManager agar tidak ada salinan kedua yang
  // bisa tertinggal saat IP backend berubah.
  static String get _baseUrl => SessionManager.baseUrl;

  Map<String, dynamic>? _attendance;
  bool _isLoadingToday = true;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // Identitas pengguna dari GET /api/user.
  bool _isLoadingProfil = true;
  String _nama = '-';
  Uint8List? _fotoProfil;

  // Aturan kantor dari GET /api/settings. Null selama dimuat atau bila gagal.
  OfficeSettings? _office;

  // Posisi terhadap geofence kantor.
  StatusJangkauan _statusJangkauan = StatusJangkauan.memuat;
  double? _jarakKeKantor;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _muatStatusHariIni();
    _muatProfil();
    _muatPengaturanKantor();
  }

  Future<void> _muatPengaturanKantor() async {
    final office = await OfficeSettingsService.fetch();
    if (!mounted) return;
    setState(() => _office = office);
    // Jarak baru bisa dihitung setelah titik pusat geofence diketahui.
    await _hitungJangkauan();
  }

  /// Membandingkan posisi sekarang dengan titik kantor. Sebelumnya badge
  /// "In Range" ditulis mati di UI — selalu mengklaim pengguna berada di dalam
  /// radius tanpa pernah mengukurnya.
  ///
  /// Status "tidak diketahui" sengaja dibedakan dari "di luar radius": izin
  /// lokasi ditolak bukan berarti pengguna jauh dari kantor, dan menyamakan
  /// keduanya akan menyesatkan.
  Future<void> _hitungJangkauan() async {
    final office = _office;
    if (office == null || !office.punyaKoordinat) {
      if (mounted) {
        setState(() => _statusJangkauan = StatusJangkauan.tidakDiketahui);
      }
      return;
    }

    try {
      var izin = await Geolocator.checkPermission();
      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
      }
      if (izin == LocationPermission.denied ||
          izin == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _statusJangkauan = StatusJangkauan.izinDitolak);
        }
        return;
      }

      final posisi = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));

      final jarak = Geolocator.distanceBetween(
        posisi.latitude,
        posisi.longitude,
        office.latitude!,
        office.longitude!,
      );

      if (!mounted) return;
      setState(() {
        _jarakKeKantor = jarak;
        _statusJangkauan = jarak <= office.radiusMeter
            ? StatusJangkauan.didalam
            : StatusJangkauan.diluar;
      });
    } catch (_) {
      // GPS mati, timeout, atau plugin gagal — jangan mengklaim apa pun.
      if (mounted) {
        setState(() => _statusJangkauan = StatusJangkauan.tidakDiketahui);
      }
    }
  }

  Future<void> _muatProfil() async {
    if (mounted) setState(() => _isLoadingProfil = true);

    final hasil = await UserProfileService.fetch();
    if (!mounted) return;

    switch (hasil.status) {
      case ProfileStatus.unauthorized:
        setState(() => _isLoadingProfil = false);
        await SessionManager.forceLogout(context);
        return;
      case ProfileStatus.failed:
        // Sengaja tanpa Snackbar: _muatStatusHariIni() berjalan bersamaan dan
        // sudah menandai kegagalan jaringan lewat tombol absen yang nonaktif.
        setState(() => _isLoadingProfil = false);
        return;
      case ProfileStatus.ok:
        setState(() {
          _nama = hasil.profile!.nama;
          _isLoadingProfil = false;
        });
    }

    final foto = await UserProfileService.fetchPhoto();
    if (!mounted || foto == null) return;
    setState(() => _fotoProfil = foto);
  }

  /// Pull-to-refresh menyegarkan status absensi, profil, dan aturan kantor.
  Future<void> _muatSemua() async {
    await Future.wait([
      _muatStatusHariIni(),
      _muatProfil(),
      _muatPengaturanKantor(),
    ]);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _muatStatusHariIni() async {
    if (mounted) setState(() => _isLoadingToday = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        if (mounted) setState(() => _isLoadingToday = false);
        return;
      }

      final res = await http
          .get(
            Uri.parse('$_baseUrl/api/attendances/today'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      if (res.statusCode == 401) {
        setState(() => _isLoadingToday = false);
        await SessionManager.forceLogout(context);
        return;
      }
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        setState(() {
          _attendance = body['data']?['attendance'];
          _isLoadingToday = false;
        });
      } else {
        setState(() => _isLoadingToday = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingToday = false);
    }
  }

  Future<void> _prosesLogout(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');

    if (token != null && token.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('$_baseUrl/api/logout'),
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
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  Future<void> _keKamera(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(isCheckOut: _sudahAbsenMasuk),
      ),
    );
    // Refresh status setelah kembali dari layar kamera (bisa jadi sudah
    // absen masuk/pulang di sesi kamera tadi).
    _muatStatusHariIni();
  }

  // === HELPER DATA ABSENSI HARI INI ===
  DateTime? get _waktuAbsen {
    final raw = _attendance?['waktu_absen'];
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  DateTime? get _waktuPulang {
    final raw = _attendance?['waktu_pulang'];
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  bool get _sudahAbsenMasuk => _waktuAbsen != null;
  bool get _sudahAbsenPulang => _waktuPulang != null;

  String _formatJam(DateTime? dt) {
    if (dt == null) return '--:--';
    int hour = dt.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    hour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  String get _tanggalHariIni {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return '${months[_now.month - 1]} ${_now.day}, ${_now.year}';
  }

  String get _statusLabel {
    if (!_sudahAbsenMasuk) return '-';
    return (_attendance?['status'] == 'hadir') ? 'On Time' : 'Late';
  }

  Color get _statusColor {
    if (!_sudahAbsenMasuk) return AppColors.textGrey;
    return (_attendance?['status'] == 'hadir')
        ? AppColors.darkGreen
        : const Color(0xFFBA1A1A);
  }

  /// Durasi kerja: kalau sudah pulang, dari masuk s/d pulang (statis).
  /// Kalau belum pulang, dari masuk s/d SEKARANG (jalan terus/live).
  Duration get _totalDurasiKerja {
    if (_waktuAbsen == null) return Duration.zero;
    final akhir = _waktuPulang ?? _now;
    final diff = akhir.difference(_waktuAbsen!);
    return diff.isNegative ? Duration.zero : diff;
  }

  String get _totalJamKerjaLabel {
    // Bulatkan ke menit terdekat (bukan dipotong ke bawah) supaya durasi
    // singkat (mis. 39 detik) tetap kebaca "0h 01m", bukan hilang jadi 0.
    final totalMenit = (_totalDurasiKerja.inSeconds / 60).round();
    final jam = totalMenit ~/ 60;
    final menit = totalMenit % 60;
    return '${jam}h ${menit.toString().padLeft(2, '0')}m';
  }

  String get _shiftBadge {
    if (!_sudahAbsenMasuk) return 'BELUM ABSEN';
    if (!_sudahAbsenPulang) return 'SHIFT ACTIVE';
    return 'SHIFT SELESAI';
  }

  String get _tombolLabel {
    if (!_sudahAbsenMasuk) return 'CLOCK IN / ABSEN MASUK';
    if (!_sudahAbsenPulang) return 'CLOCK OUT / ABSEN PULANG';
    return 'ABSENSI HARI INI SELESAI';
  }

  bool get _tombolAktif => !_sudahAbsenPulang;

  // === TAMPILAN BADGE JANGKAUAN ===

  String get _labelJangkauan {
    switch (_statusJangkauan) {
      case StatusJangkauan.memuat:
        return 'Mengecek lokasi...';
      case StatusJangkauan.didalam:
        return 'In Range';
      case StatusJangkauan.diluar:
        return 'Di luar radius ($_jarakTerbaca)';
      case StatusJangkauan.izinDitolak:
        return 'Izin lokasi ditolak';
      case StatusJangkauan.tidakDiketahui:
        return 'Lokasi tidak diketahui';
    }
  }

  /// Di bawah 1 km angka meter masih bermakna; di atas itu terlalu panjang.
  String get _jarakTerbaca {
    final jarak = _jarakKeKantor;
    if (jarak == null) return '-';
    if (jarak < 1000) return '${jarak.round()} m';
    return '${(jarak / 1000).toStringAsFixed(1)} km';
  }

  IconData get _ikonJangkauan {
    switch (_statusJangkauan) {
      case StatusJangkauan.memuat:
        return Icons.location_searching;
      case StatusJangkauan.didalam:
        return Icons.check_circle;
      case StatusJangkauan.diluar:
        return Icons.cancel;
      case StatusJangkauan.izinDitolak:
      case StatusJangkauan.tidakDiketahui:
        return Icons.help_outline;
    }
  }

  Color get _warnaJangkauan {
    switch (_statusJangkauan) {
      case StatusJangkauan.didalam:
        return AppColors.darkGreen;
      case StatusJangkauan.diluar:
        return const Color(0xFFBA1A1A);
      case StatusJangkauan.memuat:
      case StatusJangkauan.izinDitolak:
      case StatusJangkauan.tidakDiketahui:
        return AppColors.textGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgScaffold,
      bottomNavigationBar: const CustomBottomNav(activeIndex: 0),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _muatSemua,
          color: AppColors.darkGreen,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.bgScaffold,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x0C000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Expanded: nama asli bisa jauh lebih panjang dari
                      // placeholder lama, dan tanpa ini Row akan overflow.
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.borderLight,
                                border: Border.all(
                                  color: const Color(0xFFBCEECF),
                                  width: 2,
                                ),
                                image: _fotoProfil != null
                                    ? DecorationImage(
                                        image: MemoryImage(_fotoProfil!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: _fotoProfil == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 22,
                                      color: AppColors.darkGreen,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Good Morning,",
                                    style: TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  _isLoadingProfil
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.darkGreen,
                                            ),
                                          ),
                                        )
                                      : Text(
                                          _nama,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.darkGreen,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.logout,
                          color: AppColors.darkGreen,
                        ),
                        onPressed: () => _prosesLogout(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Workspace",
                                style: TextStyle(
                                  color: AppColors.darkGreen,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                _tanggalHariIni,
                                style: const TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatJam(_now),
                                style: const TextStyle(
                                  color: AppColors.darkGreen,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _shiftBadge,
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildStatCard(
                        "Arrival",
                        _formatJam(_waktuAbsen),
                        AppColors.darkGreen,
                        Icons.login,
                      ),
                      const SizedBox(height: 12),
                      _buildStatCard(
                        "Status",
                        _statusLabel,
                        _statusColor,
                        Icons.warning_amber_rounded,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.darkGreen,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x142D5A43),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Total Hours Today",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _totalJamKerjaLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white30,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.timer_outlined,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderLight),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x142D5A43),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  height: 160,
                                  decoration: const BoxDecoration(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(15),
                                    ),
                                    image: DecorationImage(
                                      image: NetworkImage(
                                        "https://placehold.co/400x200/e0e0e0/909090.png?text=Map+Area",
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _ikonJangkauan,
                                          color: _warnaJangkauan,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _labelJangkauan,
                                          style: TextStyle(
                                            color: _warnaJangkauan,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  Text(
                                    _office?.namaLokasi ?? '—',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textDark,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // Subjudul memakai radius absensi, bukan nama
                                  // kota: /api/settings tidak menyimpan alamat,
                                  // dan radius lebih berguna karena itulah batas
                                  // yang menentukan absen diterima atau ditolak.
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.my_location,
                                        color: AppColors.textGrey,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _office == null
                                            ? 'Memuat aturan kantor...'
                                            : 'Radius absensi ${_office!.radiusMeter} meter',
                                        style: const TextStyle(
                                          color: AppColors.textGrey,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.darkGreen,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            AppColors.borderLight,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      onPressed:
                                          (_isLoadingToday || !_tombolAktif)
                                          ? null
                                          : () => _keKamera(context),
                                      icon: const Icon(
                                        Icons.camera_alt_outlined,
                                      ),
                                      label: Text(
                                        _isLoadingToday
                                            ? "Memuat..."
                                            : _tombolLabel,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color accentColor,
    IconData icon,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x142D5A43),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: title == "Status" ? accentColor : AppColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
