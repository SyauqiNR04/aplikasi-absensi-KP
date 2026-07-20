import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../constants/app_styles.dart'; // Import File Warna Global
import '../widgets/custom_bottom_nav.dart'; // Import Custom Bottom Nav
import '../services/session_manager.dart';

class RiwayatAbsensiPage extends StatefulWidget {
  final String nip;
  const RiwayatAbsensiPage({super.key, required this.nip});

  @override
  State<RiwayatAbsensiPage> createState() => _RiwayatAbsensiPageState();
}

class _RiwayatAbsensiPageState extends State<RiwayatAbsensiPage> {
  // Satu sumber alamat server dengan layar lain, supaya saat IP backend
  // berubah tidak ada endpoint yang tertinggal memakai host lama.
  String get baseUrl => SessionManager.baseUrl;

  List<dynamic> historyData = [];
  bool isLoading = true;

  /// Token untuk memuat foto absensi. Fotonya ada di disk privat dan hanya
  /// bisa diambil lewat endpoint ber-token, sehingga Image.network harus
  /// membawa header Authorization -- URL polos akan dijawab 401.
  String? _token;

  // === FILTER TANGGAL ===
  DateTime? _filterStart;
  DateTime? _filterEnd;
  List<dynamic>? _filteredData;
  bool _isExporting = false;

  List<dynamic> get _visibleData => _filteredData ?? historyData;

  @override
  void initState() {
    super.initState();
    fetchHistory();
  }

  // === FUNGSI AMBIL DATA RIWAYAT ===
  Future<void> fetchHistory() async {
    final url = Uri.parse('$baseUrl/api/history/${widget.nip}');

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      _token = token;

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

      if (response.statusCode == 401) {
        setState(() => isLoading = false);
        await SessionManager.forceLogout(context);
        return;
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          historyData = data['data'];
          isLoading = false;
        });
        if (_filterStart != null || _filterEnd != null) {
          _terapkanFilter();
        }
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
      // .toLocal() wajib: server kirim UTC ("...Z"), tanpa ini jam yang
      // ditampilkan akan mundur 7 jam (selisih WIB) dari waktu sebenarnya.
      DateTime dt = DateTime.parse(datetime).toLocal();
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
      DateTime dt = DateTime.parse(datetime).toLocal();
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

  String _formatTanggalFilter(DateTime? d) {
    if (d == null) return '';
    return '${d.month.toString().padLeft(2, '0')}/'
        '${d.day.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _pilihTanggal(bool isStart) async {
    final now = DateTime.now();
    final initial = isStart ? (_filterStart ?? now) : (_filterEnd ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _filterStart = picked;
      } else {
        _filterEnd = picked;
      }
    });
  }

  void _terapkanFilter() {
    if (_filterStart == null && _filterEnd == null) {
      setState(() => _filteredData = null);
      return;
    }
    if (_filterStart != null &&
        _filterEnd != null &&
        _filterStart!.isAfter(_filterEnd!)) {
      _snack('Date Range Start tidak boleh setelah Date Range End.');
      return;
    }

    final start = _filterStart == null
        ? null
        : DateTime(_filterStart!.year, _filterStart!.month, _filterStart!.day);
    final end = _filterEnd == null
        ? null
        : DateTime(
            _filterEnd!.year,
            _filterEnd!.month,
            _filterEnd!.day,
            23,
            59,
            59,
          );

    setState(() {
      _filteredData = historyData.where((absen) {
        final dt = DateTime.tryParse(
          absen['waktu_absen']?.toString() ?? '',
        )?.toLocal();
        if (dt == null) return false;
        if (start != null && dt.isBefore(start)) return false;
        if (end != null && dt.isAfter(end)) return false;
        return true;
      }).toList();
    });
  }

  void _resetFilter() {
    setState(() {
      _filterStart = null;
      _filterEnd = null;
      _filteredData = null;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<List<String>> _dataUntukExport() {
    return _visibleData.map<List<String>>((absen) {
      final dt = DateTime.tryParse(
        absen['waktu_absen']?.toString() ?? '',
      )?.toLocal();
      final tanggal = dt == null
          ? '-'
          : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
                '${dt.day.toString().padLeft(2, '0')}';
      final jam = dt == null
          ? '-'
          : '${dt.hour.toString().padLeft(2, '0')}:'
                '${dt.minute.toString().padLeft(2, '0')}';
      return [
        tanggal,
        jam,
        (absen['status'] ?? '-').toString(),
        (absen['latitude'] ?? '-').toString(),
        (absen['longitude'] ?? '-').toString(),
      ];
    }).toList();
  }

  Future<void> _exportExcel() async {
    if (_visibleData.isEmpty) {
      _snack('Tidak ada data untuk diekspor.');
      return;
    }
    setState(() => _isExporting = true);
    try {
      final workbook = Excel.createExcel();
      const sheetName = 'Riwayat Absensi';
      final sheet = workbook[sheetName];
      workbook.setDefaultSheet(sheetName);
      if (workbook.sheets.containsKey('Sheet1') && sheetName != 'Sheet1') {
        workbook.delete('Sheet1');
      }

      sheet.appendRow([
        TextCellValue('Tanggal'),
        TextCellValue('Jam'),
        TextCellValue('Status'),
        TextCellValue('Latitude'),
        TextCellValue('Longitude'),
      ]);
      for (final row in _dataUntukExport()) {
        sheet.appendRow(row.map(TextCellValue.new).toList());
      }

      final bytes = workbook.encode();
      if (bytes == null) throw Exception('Gagal encode file Excel.');

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/riwayat_absensi_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await File(path).writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Riwayat Absensi (Excel)'),
      );
    } catch (e) {
      _snack('Gagal export Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_visibleData.isEmpty) {
      _snack('Tidak ada data untuk diekspor.');
      return;
    }
    setState(() => _isExporting = true);
    try {
      final doc = pw.Document();
      final rows = _dataUntukExport();

      doc.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Header(level: 0, text: 'Riwayat Absensi'),
            pw.TableHelper.fromTextArray(
              headers: ['Tanggal', 'Jam', 'Status', 'Latitude', 'Longitude'],
              data: rows,
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/riwayat_absensi_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(path).writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Riwayat Absensi (PDF)'),
      );
    } catch (e) {
      _snack('Gagal export PDF: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
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
                              onPressed: _isExporting ? null : _exportExcel,
                              icon: _isExporting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.darkGreen,
                                      ),
                                    )
                                  : const Icon(
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
                              onPressed: _isExporting ? null : _exportPdf,
                              icon: _isExporting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
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
                            _buildFilterField(
                              "Date Range Start",
                              _formatTanggalFilter(_filterStart),
                              onTap: () => _pilihTanggal(true),
                              onClear: _filterStart == null
                                  ? null
                                  : () => setState(() => _filterStart = null),
                            ),
                            const SizedBox(height: 16),
                            _buildFilterField(
                              "Date Range End",
                              _formatTanggalFilter(_filterEnd),
                              onTap: () => _pilihTanggal(false),
                              onClear: _filterEnd == null
                                  ? null
                                  : () => setState(() => _filterEnd = null),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.goldLight,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      onPressed: _terapkanFilter,
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
                                ),
                                if (_filteredData != null ||
                                    _filterStart != null ||
                                    _filterEnd != null) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    height: 48,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: AppColors.borderLight,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: _resetFilter,
                                      child: const Icon(
                                        Icons.clear,
                                        color: AppColors.textGrey,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
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
                                  : _visibleData.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(40),
                                      child: Text(
                                        historyData.isEmpty
                                            ? "Belum ada data absensi."
                                            : "Tidak ada data pada rentang tanggal ini.",
                                      ),
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
                                      rows: _visibleData.map((absen) {
                                        List<String> dateParts = _parseDate(
                                          absen['waktu_absen'],
                                        );
                                        List<String> timeParts = _parseTime(
                                          absen['waktu_absen'],
                                        );
                                        final waktuPulang =
                                            absen['waktu_pulang'];
                                        List<String> pulangParts =
                                            (waktuPulang == null ||
                                                waktuPulang == '')
                                            ? ["--:--", "--"]
                                            : _parseTime(waktuPulang);

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
                                                children: [
                                                  Text(
                                                    pulangParts[0],
                                                    style: const TextStyle(
                                                      color: AppColors.textGrey,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    pulangParts[1],
                                                    style: const TextStyle(
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
                                    "Showing ${_visibleData.length} entries",
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
  Widget _buildFilterField(
    String label,
    String value, {
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final hasValue = value.isNotEmpty;
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
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
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
                  hasValue ? value : "mm/dd/yyyy",
                  style: TextStyle(
                    color: hasValue
                        ? AppColors.textDark
                        : AppColors.borderLight,
                    fontSize: 16,
                  ),
                ),
                if (hasValue && onClear != null)
                  InkWell(
                    onTap: onClear,
                    child: const Icon(
                      Icons.close,
                      color: Color(0xFF717973),
                      size: 18,
                    ),
                  )
                else
                  const Icon(
                    Icons.calendar_today_outlined,
                    color: Color(0xFF717973),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // === MODAL POPUP DETAIL LOKASI & FOTO ===
  void _tampilkanDetailLokasi(dynamic absen) {
    // URL datang dari server (foto_masuk_url), bukan dirakit dari path
    // penyimpanan. Sebelumnya layar ini menebak "$baseUrl/storage/<path>",
    // padahal foto absensi sudah dipindah ke disk privat -- sehingga setiap
    // foto baru gagal dimuat dan hanya menyisakan ikon gambar rusak.
    final String? fullImageUrl = absen['foto_masuk_url'] as String?;
    final bool hasFoto = fullImageUrl != null && fullImageUrl.isNotEmpty;

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
                    // Endpoint fotonya ber-token: tanpa header ini server
                    // menjawab 401 dan gambar tidak pernah tampil.
                    headers: {
                      if (_token != null) 'Authorization': 'Bearer $_token',
                      'Accept': 'image/*',
                    },
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
