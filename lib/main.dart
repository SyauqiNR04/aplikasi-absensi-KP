import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import layar dari folder screens
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';

// Variabel global agar kamera bisa diakses dari file mana saja
List<CameraDescription> globalCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi Kamera
  try {
    globalCameras = await availableCameras();
  } catch (e) {
    debugPrint("Error mencari kamera: $e");
  }

  // Cek sesi login (Apakah token Sanctum sudah tersimpan?)
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? token = prefs.getString('token');

  // Jalankan aplikasi dan kirim status login
  runApp(MyApp(isLoggedIn: token != null));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Absensi TA',
      theme: ThemeData(
        fontFamily: 'Manrope',
        primaryColor: const Color(
          0xFF14422D,
        ), // Menggunakan warna hijau gelap dari template
        scaffoldBackgroundColor: const Color(0xFFF8F9FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF14422D),
          foregroundColor: Colors.white,
        ),
      ),
      debugShowCheckedModeBanner: false,

      // Logika Penentu Halaman Pertama:
      home: isLoggedIn ? const DashboardScreen() : const LoginScreen(),

      // ---> PERBAIKAN: Mendaftarkan Rute agar fungsi Logout berjalan mulus <---
      routes: {
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}
