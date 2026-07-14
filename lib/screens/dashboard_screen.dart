import 'package:flutter/material.dart';
// Import layar kamera untuk navigasi
import 'camera_screen.dart';
// Import layar riwayat yang baru kita buat
// (Sesuaikan path-nya jika file riwayat_absensi.dart berada di folder berbeda)
import '../pages/riwayat_absensi.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // VARIABEL DUMMY UNTUK TESTING
    // Pastikan angka ini adalah 'nip' yang benar-benar ada di tabel employees Anda
    const String nipKaryawan = 'TA-2026-001';

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard Karyawan')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // TOMBOL 1: MULAI ABSEN
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 15,
                ),
                minimumSize: const Size(250, 50), // Menyeragamkan lebar tombol
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

            const SizedBox(height: 20), // Memberikan jarak antar tombol
            // TOMBOL 2: LIHAT RIWAYAT (BARU)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 15,
                ),
                minimumSize: const Size(250, 50), // Menyeragamkan lebar tombol
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                // Berpindah ke Halaman Riwayat
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const RiwayatAbsensiPage(nip: nipKaryawan),
                  ),
                );
              },
              child: const Text(
                "LIHAT RIWAYAT",
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
