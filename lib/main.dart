import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
// Import layar dashboard dari folder screens
import 'screens/dashboard_screen.dart';

// Variabel global agar kamera bisa diakses dari file mana saja
List<CameraDescription> globalCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    globalCameras = await availableCameras();
  } catch (e) {
    debugPrint("Error mencari kamera: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Absensi TA',
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner:
          false, // Menghilangkan pita debug di pojok kanan atas
      home: const DashboardScreen(),
    );
  }
}
