import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'camera_screen.dart';
import '../pages/riwayat_absensi.dart'; // Sesuaikan path jika berbeda
// import 'login_page.dart'; // Buka komentar ini sesuaikan dengan halaman login Anda

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  // === FUNGSI LOGOUT ===
  Future<void> _prosesLogout(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');

    if (context.mounted) {
      // Sesuaikan nama route atau class Halaman Login Anda
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  // === FUNGSI NAVIGASI ===
  void _keKamera(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );
  }

  void _keRiwayat(BuildContext context) {
    const String nipKaryawan = 'TA-2026-001';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RiwayatAbsensiPage(nip: nipKaryawan),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Definisi Warna dari Template
    const Color bgScaffold = Color(0xFFF8F9FF);
    const Color darkGreen = Color(0xFF14422D);
    const Color textDark = Color(0xFF0B1C30);
    const Color textGrey = Color(0xFF414943);

    return Scaffold(
      backgroundColor: bgScaffold,
      // === BOTTOM NAVIGATION BAR (Sesuai Template HTML) ===
      bottomNavigationBar: Container(
        height: 70,
        decoration: const BoxDecoration(
          color: bgScaffold,
          border: Border(top: BorderSide(color: Color(0xFFC0C9C1), width: 1)),
          boxShadow: [
            BoxShadow(
              color: Color(0x142D5A43), // rgba(45, 90, 67, 0.08)
              blurRadius: 12,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home_filled, "Home", true, () {}),
            _buildNavItem(
              Icons.history,
              "History",
              false,
              () => _keRiwayat(context),
            ),
            _buildNavItem(Icons.fact_check_outlined, "Verify", false, () {}),
            _buildNavItem(Icons.bar_chart, "Reports", false, () {}),
            _buildNavItem(Icons.settings, "Settings", false, () {}),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === HEADER (Profil & Logout) ===
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: bgScaffold,
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
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFBCEECF),
                              width: 2,
                            ),
                            image: const DecorationImage(
                              image: NetworkImage(
                                "https://placehold.co/100x100.png",
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Good Morning,",
                              style: TextStyle(
                                color: textGrey,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              "Alex Rivera",
                              style: TextStyle(
                                color: darkGreen,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, color: darkGreen),
                      tooltip: "Logout",
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
                    // === WORKSPACE & DATE ===
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Workspace",
                              style: TextStyle(
                                color: darkGreen,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              "July 15, 2026",
                              style: TextStyle(color: textGrey, fontSize: 16),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              "08:52 AM",
                              style: TextStyle(
                                color: darkGreen,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "SHIFT ACTIVE",
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // === STATS CARDS ===
                    _buildStatCard(
                      "Arrival",
                      "08:52 AM",
                      darkGreen,
                      Icons.login,
                    ),
                    const SizedBox(height: 12),
                    _buildStatCard(
                      "Status",
                      "Late (22m)",
                      const Color(0xFFBA1A1A),
                      Icons.warning_amber_rounded,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: darkGreen,
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
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Total Hours Today",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                "00h 00m",
                                style: TextStyle(
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

                    // === MAP & ACTION CARD (TOMOL ABSEN) ===
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFC0C9C1)),
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
                          // Map Area Dummy
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
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: darkGreen,
                                        size: 14,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        "In Range",
                                        style: TextStyle(
                                          color: darkGreen,
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
                          // Detail & Tombol Absen
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                const Text(
                                  "Kantor Utama",
                                  style: TextStyle(
                                    color: textDark,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      color: textGrey,
                                      size: 14,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      "Pekanbaru, Riau",
                                      style: TextStyle(
                                        color: textGrey,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                // TOMBOL MULAI ABSEN
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: darkGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () => _keKamera(context),
                                    icon: const Icon(Icons.camera_alt_outlined),
                                    label: const Text(
                                      "CLOCK IN / ABSEN",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  "Biometric verification required for clock in.",
                                  style: TextStyle(
                                    color: textGrey,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // === UPCOMING SCHEDULE ===
                    const Text(
                      "UPCOMING SCHEDULE",
                      style: TextStyle(
                        color: darkGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF4FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC0C9C1)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDC74E),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  "15",
                                  style: TextStyle(
                                    color: Colors.brown.shade800,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "JUL",
                                  style: TextStyle(
                                    color: Colors.brown.shade800,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Presentasi Tugas Akhir",
                                  style: TextStyle(
                                    color: textDark,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "13:00 PM • Ruang Sidang Utama",
                                  style: TextStyle(
                                    color: textGrey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper untuk membuat Card Status (Arrival / Late)
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
                  color: Color(0xFF414943),
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
              color: title == "Status" ? accentColor : const Color(0xFF0B1C30),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // Helper untuk Bottom Navigation Item
  Widget _buildNavItem(
    IconData icon,
    String label,
    bool isActive,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0x4DFDC74E)
                  : Colors.transparent, // rgba(253, 199, 78, 0.30)
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isActive
                  ? const Color(0xFF14422D)
                  : const Color(0xFF414943),
              size: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive
                  ? const Color(0xFF14422D)
                  : const Color(0xFF414943),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
