import 'package:flutter/material.dart';
// Import layar kamera untuk navigasi
import 'camera_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard Karyawan')),
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
          ),
          onPressed: () {
            // Berpindah ke Halaman Kamera
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CameraScreen()),
            );
          },
          child: const Text("MULAI ABSEN", style: TextStyle(fontSize: 18)),
        ),
      ),
    );
  }
}
