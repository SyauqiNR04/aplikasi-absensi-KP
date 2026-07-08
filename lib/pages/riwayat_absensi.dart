import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RiwayatAbsensiPage extends StatefulWidget {
  final String nip;

  // ---> PERBAIKAN 1: Menggunakan super.key <---
  const RiwayatAbsensiPage({super.key, required this.nip});

  @override
  State<RiwayatAbsensiPage> createState() => _RiwayatAbsensiPageState();
}

class _RiwayatAbsensiPageState extends State<RiwayatAbsensiPage> {
  // === SESUAIKAN IP LAPTOP ANDA DI SINI ===
  final String baseUrl =
      "http://192.168.100.234/backend-absensi/public"; // Jika pakai Laragon
  

  List<dynamic> historyData = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchHistory();
  }

  Future<void> fetchHistory() async {
    final url = Uri.parse('$baseUrl/api/history/${widget.nip}');

    try {
      final response = await http.get(url);

      // ---> PERBAIKAN 2: Cek apakah halaman masih aktif sebelum menggunakan context <---
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          historyData = data['data'];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengambil riwayat absensi.')),
        );
      }
    } catch (e) {
      // ---> PERBAIKAN 3: Cek lagi di bagian catch (error jaringan) <---
      if (!mounted) return;

      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error jaringan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Absensi'),
        backgroundColor: Colors.blueAccent,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : historyData.isEmpty
          ? const Center(child: Text("Belum ada data absensi."))
          : ListView.builder(
              itemCount: historyData.length,
              itemBuilder: (context, index) {
                var absen = historyData[index];

                bool hasFoto =
                    absen['foto_bukti'] != null && absen['foto_bukti'] != "";
                String fullImageUrl = hasFoto
                    ? "$baseUrl/storage/${absen['foto_bukti']}"
                    : "";

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  elevation: 3,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: hasFoto
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              fullImageUrl,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.broken_image,
                                  size: 60,
                                  color: Colors.grey,
                                );
                              },
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.grey,
                          ),

                    title: Text(
                      "Status: ${absen['status']}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text("Waktu: ${absen['waktu_absen']}"),
                        Text("Lat: ${absen['latitude']}"),
                        Text("Long: ${absen['longitude']}"),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
