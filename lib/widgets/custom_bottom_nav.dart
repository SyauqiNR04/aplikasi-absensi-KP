import 'package:flutter/material.dart';
import '../constants/app_styles.dart';
import '../screens/dashboard_screen.dart';
import '../screens/camera_screen.dart';
import '../pages/riwayat_absensi.dart';

class CustomBottomNav extends StatelessWidget {
  final int activeIndex;

  const CustomBottomNav({super.key, required this.activeIndex});

  void _onTap(BuildContext context, int index) {
    if (index == activeIndex)
      return; // Jangan lakukan apa-apa jika menekan menu yang sedang aktif

    // Logika pindah halaman tanpa menumpuk rute (menggunakan pushReplacement)
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const RiwayatAbsensiPage(nip: 'TA-2026-001'),
        ),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CameraScreen()),
      );
    }
    // Tambahkan index 3 (Reports) dan 4 (Settings) nanti jika halamannya sudah dibuat
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: AppColors.bgScaffold,
        border: Border(top: BorderSide(color: AppColors.borderLight, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            Icons.home_outlined,
            "Home",
            activeIndex == 0,
            () => _onTap(context, 0),
          ),
          _buildNavItem(
            Icons.history,
            "History",
            activeIndex == 1,
            () => _onTap(context, 1),
          ),
          _buildNavItem(
            Icons.fact_check,
            "Verify",
            activeIndex == 2,
            () => _onTap(context, 2),
          ),
          _buildNavItem(
            Icons.bar_chart,
            "Reports",
            activeIndex == 3,
            () => _onTap(context, 3),
          ),
          _buildNavItem(
            Icons.settings,
            "Settings",
            activeIndex == 4,
            () => _onTap(context, 4),
          ),
        ],
      ),
    );
  }

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
              color: isActive ? const Color(0x4DFDC74E) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isActive ? AppColors.darkGreen : AppColors.textGrey,
              size: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? AppColors.darkGreen : AppColors.textGrey,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
