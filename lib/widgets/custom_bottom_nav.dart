import 'package:flutter/material.dart';
import '../constants/app_styles.dart';
import '../screens/dashboard_screen.dart';
import '../screens/camera_screen.dart';
import '../screens/riwayat_absensi.dart';
import '../screens/settings_screen.dart';

class CustomBottomNav extends StatelessWidget {
  final int activeIndex;

  const CustomBottomNav({super.key, required this.activeIndex});

  // Logika Navigasi
  void _onTap(BuildContext context, int index) {
    if (index == activeIndex) return;

    final List<Widget> pages = [
      const DashboardScreen(), // Index 0
      const CameraScreen(), // Index 1
      const RiwayatAbsensiPage(nip: 'TA-2026-001'), // Index 2
      const SettingsScreen(), // Index 3
    ];

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => pages[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: Colors.white, // Menggunakan warna putih bersih
        border: Border(top: BorderSide(color: AppColors.borderLight, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x142D5A43),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            Icons.home_outlined,
            "Home",
            0,
            () => _onTap(context, 0),
          ),
          _buildNavItem(
            Icons.fact_check_outlined,
            "Verify",
            1,
            () => _onTap(context, 1),
          ),
          _buildNavItem(
            Icons.bar_chart,
            "Reports",
            2,
            () => _onTap(context, 2),
          ),
          _buildNavItem(
            Icons.settings_outlined,
            "Settings",
            3,
            () => _onTap(context, 3),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    String label,
    int index,
    VoidCallback onTap,
  ) {
    final bool isActive = activeIndex == index;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              // Menggunakan warna dari AppColors agar clean
              color: isActive
                  ? AppColors.goldLight.withValues(alpha: 0.3)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isActive ? AppColors.darkGreen : AppColors.textGrey,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? AppColors.darkGreen : AppColors.textGrey,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
