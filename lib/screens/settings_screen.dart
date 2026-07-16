import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_styles.dart';
import '../widgets/custom_bottom_nav.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBiometricEnabled = true;
  bool _isPushEnabled = true;

  Future<void> _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
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
                    const CircleAvatar(
                      radius: 32,
                      backgroundImage: NetworkImage(
                        "https://placehold.co/60x60",
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Alex Rivera",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            "EMP-2024-001",
                            style: TextStyle(color: AppColors.textGrey),
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
              ),
              _buildToggleItem(
                Icons.fingerprint,
                "Biometric (Face ID)",
                _isBiometricEnabled,
                (v) => setState(() => _isBiometricEnabled = v),
              ),
              _buildSettingItem(
                Icons.privacy_tip,
                "Privacy Settings",
                Icons.chevron_right,
              ),

              const SizedBox(height: 24),
              _buildSectionTitle("NOTIFICATIONS"),
              _buildToggleItem(
                Icons.notifications,
                "Push Notifications",
                _isPushEnabled,
                (v) => setState(() => _isPushEnabled = v),
              ),
              _buildToggleItem(Icons.email, "Email Alerts", false, (v) => {}),

              const SizedBox(height: 24),

              // LOGOUT BUTTON
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(double.infinity, 56),
                ),
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text(
                  "Logout",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  Widget _buildSettingItem(IconData icon, String title, IconData trailing) =>
      Container(
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
            Text(title, style: const TextStyle(fontSize: 16)),
            const Spacer(),
            Icon(trailing, color: AppColors.textGrey),
          ],
        ),
      );

  Widget _buildToggleItem(
    IconData icon,
    String title,
    bool value,
    Function(bool) onChanged,
  ) => Container(
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
        Text(title, style: const TextStyle(fontSize: 16)),
        const Spacer(),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.darkGreen, // Warna track saat aktif
          activeThumbColor: Colors.white, // Warna tombol bulat saat aktif
          inactiveThumbColor: Colors.white, // Warna tombol bulat saat mati
          inactiveTrackColor: AppColors.borderLight, // Warna track saat mati
        ),
      ],
    ),
  );
}
