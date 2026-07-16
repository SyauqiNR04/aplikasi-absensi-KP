import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_styles.dart'; // Import File Warna Global
import '../widgets/custom_bottom_nav.dart'; // Import Custom Bottom Nav

class RiwayatAbsensiPage extends StatefulWidget {
  final String nip;
  const RiwayatAbsensiPage({super.key, required this.nip});

  @override
  State<RiwayatAbsensiPage> createState() => _RiwayatAbsensiPageState();
}

class _RiwayatAbsensiPageState extends State<RiwayatAbsensiPage> {
  final String baseUrl = "http://192.168.100.234/backend-absensi/public";

  List<dynamic> historyData = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchHistory();
  }

  // === FUNGSI AMBIL DATA RIWAYAT ===
  Future<void> fetchHistory() async {
    final url = Uri.parse('$baseUrl/api/history');

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      if (token == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anda belum login. Token tidak ditemukan.'),
          ),
        );
        return;
      }

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

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
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error jaringan: $e')));
    }
  }

  // === HELPER PARSING TANGGAL ===
  List<String> _parseDate(String datetime) {
    try {
      DateTime dt = DateTime.parse(datetime);
      const months = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ];
      return [months[dt.month - 1], "${dt.day},", "${dt.year}"];
    } catch (e) {
      return ["-", "-", "-"];
    }
  }

  // === HELPER PARSING JAM ===
  List<String> _parseTime(String datetime) {
    try {
      DateTime dt = DateTime.parse(datetime);
      int hour = dt.hour;
      String minute = dt.minute.toString().padLeft(2, '0');
      String period = hour >= 12 ? "PM" : "AM";
      hour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      String hourStr = hour.toString().padLeft(2, '0');
      return ["$hourStr:$minute", period];
    } catch (e) {
      return ["--:--", "--"];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgScaffold,
      // ---> SANGAT BERSIH: Bottom Nav terpusat (Index 1 untuk History) <---
      bottomNavigationBar: const CustomBottomNav(activeIndex: 2),

      body: SafeArea(
        child: Column(
          children: [
            // === HEADER APP BAR ===
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.bgScaffold,
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
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.accentGreen,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.shield,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        "Attendance Pro",
                        style: TextStyle(
                          color: AppColors.darkGreen,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.darkGreen),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // === MAIN CONTENT ===
            Expanded(
              child: RefreshIndicator(
                onRefresh: fetchHistory,
                color: AppColors.darkGreen,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TITLE & SUBTITLE
                      const Text(
                        "Reports & History",
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Review and manage your attendance records",
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // EXPORT BUTTONS
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                side: const BorderSide(
                                  color: AppColors.borderLight,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {},
                              icon: const Icon(
                                Icons.file_download_outlined,
                                color: AppColors.darkGreen,
                                size: 18,
                              ),
                              label: const Text(
                                "Export to Excel",
                                style: TextStyle(
                                  color: AppColors.darkGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.darkGreen,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {},
                              icon: const Icon(
                                Icons.picture_as_pdf_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                              label: const Text(
                                "Export to PDF",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // FILTER CARD
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.borderLight.withValues(alpha: 0.3),
                          ),
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
                            _buildFilterField("Date Range Start", "mm/dd/yyyy"),
                            const SizedBox(height: 16),
                            _buildFilterField("Date Range End", "mm/dd/yyyy"),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.goldLight,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () {},
                                icon: const Icon(
                                  Icons.filter_list,
                                  color: Color(0xFF725300),
                                  size: 20,
                                ),
                                label: const Text(
                                  "Apply Filters",
                                  style: TextStyle(
                                    color: Color(0xFF725300),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // DATA TABLE CARD
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.borderLight.withValues(alpha: 0.3),
                          ),
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
                            // Horizontal Scroll untuk Tabel
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: isLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(40),
                                      child: CircularProgressIndicator(
                                        color: AppColors.darkGreen,
                                      ),
                                    )
                                  : historyData.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.all(40),
                                      child: Text("Belum ada data absensi."),
                                    )
                                  : DataTable(
                                      headingRowColor: WidgetStateProperty.all(
                                        const Color(0xFFEFF4FF),
                                      ),
                                      dataRowMinHeight: 70,
                                      dataRowMaxHeight: 80,
                                      columnSpacing: 24,
                                      dividerThickness: 1,
                                      horizontalMargin: 24,
                                      columns: const [
                                        DataColumn(
                                          label: Text(
                                            "DATE",
                                            style: TextStyle(
                                              color: Color(0xFF717973),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            "CLOCK\nIN",
                                            style: TextStyle(
                                              color: Color(0xFF717973),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            "CLOCK\nOUT",
                                            style: TextStyle(
                                              color: Color(0xFF717973),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            "STATUS",
                                            style: TextStyle(
                                              color: Color(0xFF717973),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            "LOCATION",
                                            style: TextStyle(
                                              color: Color(0xFF717973),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                      ],
                                      rows: historyData.map((absen) {
                                        List<String> dateParts = _parseDate(
                                          absen['waktu_absen'],
                                        );
                                        List<String> timeParts = _parseTime(
                                          absen['waktu_absen'],
                                        );

                                        // Warna Status Dinamis
                                        bool isHadir =
                                            absen['status'] == 'hadir';
                                        Color statusBg = isHadir
                                            ? const Color(0xFFCAEAD5)
                                            : const Color(0xFFFFDAD6);
                                        Color statusText = isHadir
                                            ? const Color(0xFF244031)
                                            : const Color(0xFF93000A);
                                        String statusLabel = isHadir
                                            ? "On-time"
                                            : "Late";

                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    dateParts[0],
                                                    style: const TextStyle(
                                                      color: AppColors.textDark,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    dateParts[1],
                                                    style: const TextStyle(
                                                      color: AppColors.textDark,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    dateParts[2],
                                                    style: const TextStyle(
                                                      color: AppColors.textDark,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            DataCell(
                                              Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    timeParts[0],
                                                    style: TextStyle(
                                                      color: isHadir
                                                          ? AppColors.textDark
                                                          : const Color(
                                                              0xFFBA1A1A,
                                                            ),
                                                      fontSize: 14,
                                                      fontWeight: isHadir
                                                          ? FontWeight.normal
                                                          : FontWeight.bold,
                                                    ),
                                                  ),
                                                  Text(
                                                    timeParts[1],
                                                    style: TextStyle(
                                                      color: isHadir
                                                          ? AppColors.textDark
                                                          : const Color(
                                                              0xFFBA1A1A,
                                                            ),
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            DataCell(
                                              Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: const [
                                                  Text(
                                                    "--:--",
                                                    style: TextStyle(
                                                      color: AppColors.textGrey,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    "--",
                                                    style: TextStyle(
                                                      color: AppColors.textGrey,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            DataCell(
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: statusBg,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  statusLabel,
                                                  style: TextStyle(
                                                    color: statusText,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.location_on,
                                                  color: AppColors.darkGreen,
                                                ),
                                                onPressed: () =>
                                                    _tampilkanDetailLokasi(
                                                      absen,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                            ),
                            // PAGINATION FOOTER
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEFF4FF),
                                borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(12),
                                ),
                                border: Border(
                                  top: BorderSide(color: AppColors.borderLight),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Showing ${historyData.length} entries",
                                    style: const TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: AppColors.borderLight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.chevron_left,
                                          color: AppColors.borderLight,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: AppColors.borderLight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.chevron_right,
                                          color: AppColors.textDark,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === WIDGET HELPER: TEXTFIELD FILTER ===
  Widget _buildFilterField(String label, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF717973),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                hint,
                style: const TextStyle(
                  color: AppColors.borderLight,
                  fontSize: 16,
                ),
              ),
              const Icon(
                Icons.calendar_today_outlined,
                color: Color(0xFF717973),
                size: 18,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // === MODAL POPUP DETAIL LOKASI & FOTO ===
  void _tampilkanDetailLokasi(dynamic absen) {
    bool hasFoto = absen['foto_bukti'] != null && absen['foto_bukti'] != "";
    String fullImageUrl = hasFoto
        ? "$baseUrl/storage/${absen['foto_bukti']}"
        : "";

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "Detail Kehadiran",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.darkGreen,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasFoto)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    fullImageUrl,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => const Icon(
                      Icons.broken_image,
                      size: 100,
                      color: Colors.grey,
                    ),
                  ),
                )
              else
                const Icon(Icons.person_off, size: 100, color: Colors.grey),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.gps_fixed,
                    color: Color(0xFF717973),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Lat: ${absen['latitude']}",
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.gps_fixed,
                    color: Color(0xFF717973),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Long: ${absen['longitude']}",
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text(
                "Tutup",
                style: TextStyle(
                  color: AppColors.darkGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }
}
