import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nipController = TextEditingController();
  bool _isLoading = false;

  // Fungsi untuk menembak API Login
  Future<void> _login() async {
    if (_nipController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('NIP tidak boleh kosong!')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Sesuaikan URL: 10.0.2.2 untuk Android Emulator, atau IP WiFi jika pakai HP Asli
    final url = Uri.parse(
      'http://10.46.249.83/backend-absensi/public/api/login',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Accept': 'application/json'},
        body: {'nip': _nipController.text},
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        // 1. Ambil Token dan Data Karyawan dari API
        String token = responseData['data']['token'];
        String nama = responseData['data']['karyawan']['nama_lengkap'];

        // 2. Simpan secara permanen di memori HP
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        await prefs.setString('nama_lengkap', nama);

        // 3. Pindah ke Halaman Dashboard & Hapus riwayat tombol "Back"
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
            (route) => false,
          );
        }
      } else {
        // Jika NIP salah / tidak terdaftar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(responseData['message'] ?? 'Login Gagal')),
          );
        }
      }
    } catch (e) {
      // TAMBAHKAN BARIS INI UNTUK MELIHAT PESAN ERROR ASLINYA
      print("===== ERROR KONEKSI =====");
      print(e.toString());
      print("=========================");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tidak dapat terhubung ke server. Pastikan API menyala.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.fingerprint, size: 80, color: Color(0xFF14422D)),
              const SizedBox(height: 24),
              const Text(
                'Login Karyawan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF14422D),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Masukkan Nomor Induk Pegawai (NIP) Anda untuk melanjutkan absensi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _nipController,
                decoration: InputDecoration(
                  labelText: 'NIP Karyawan',
                  hintText: 'Contoh: EMP-2026001',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14422D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Masuk Aplikasi',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
