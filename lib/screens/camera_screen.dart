import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Sesuaikan jika path berbeda
import '../constants/app_styles.dart'; // Import File Warna Global
import '../widgets/custom_bottom_nav.dart'; // Import Custom Bottom Nav

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool isCameraInitialized = false;
  bool isLoading = false;
  bool isAbsensiSelesai = false;
  String statusPesan = "Scanning face...";

  // Animasi Garis Scanner
  late AnimationController _scanAnimationController;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
    ),
  );

  bool isDetecting = false;
  bool isFaceDetected = false;
  bool isBlinked = false;
  bool isEyeClosed = false;

  // === VARIABEL BARU UNTUK LOKASI BACKGROUND ===
  Position? _userPosition;
  bool _isFetchingGps = true;

  @override
  void initState() {
    super.initState();
    _inisialisasiKamera();

    // Langsung cari lokasi GPS di latar belakang saat halaman dibuka
    _ambilLokasiBackground();

    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  // === FUNGSI: Cari GPS di Latar Belakang ===
  Future<void> _ambilLokasiBackground() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _userPosition = position;
          _isFetchingGps = false; // Lokasi berhasil dikunci
        });
      }
    } catch (e) {
      debugPrint("Error GPS: $e");
      if (mounted) {
        setState(() {
          _isFetchingGps = false; // Berhenti loading meski gagal
        });
      }
    }
  }

  Future<void> _inisialisasiKamera() async {
    final kameraDepan = globalCameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => globalCameras.first,
    );

    _controller = CameraController(
      kameraDepan,
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;

      setState(() {
        isCameraInitialized = true;
      });

      _controller!.startImageStream((CameraImage image) {
        if (isLoading || isAbsensiSelesai) return;

        if (!isDetecting) {
          isDetecting = true;
          _prosesDeteksiWajah(image, kameraDepan);
        }
      });
    } catch (e) {
      setState(() {
        statusPesan = "Gagal buka kamera";
      });
    }
  }

  Future<void> _prosesDeteksiWajah(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (isLoading || isAbsensiSelesai) {
      isDetecting = false;
      return;
    }

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final imageRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;
      final inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageData,
      );
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (mounted && !isLoading && !isAbsensiSelesai) {
        setState(() {
          if (faces.isNotEmpty) {
            Face face = faces.first;
            if (!isBlinked) {
              double? mataKiri = face.leftEyeOpenProbability;
              double? mataKanan = face.rightEyeOpenProbability;
              if (mataKiri != null && mataKanan != null) {
                if (mataKiri < 0.2 && mataKanan < 0.2) {
                  isEyeClosed = true;
                } else if (isEyeClosed && mataKiri > 0.55 && mataKanan > 0.55) {
                  isBlinked = true;
                }
              }
              if (!isBlinked) {
                isFaceDetected = false;
                statusPesan = "Kedipkan Mata!";
              } else {
                isFaceDetected = true;
                statusPesan = "Verifikasi Asli!";
                _scanAnimationController.stop();
              }
            } else {
              isFaceDetected = true;
              statusPesan = "Verifikasi Asli!";
            }
          } else {
            isFaceDetected = false;
            isBlinked = false;
            isEyeClosed = false;
            statusPesan = "Scanning face...";
            if (!_scanAnimationController.isAnimating) {
              _scanAnimationController.repeat(reverse: true);
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Error AI: $e");
    } finally {
      isDetecting = false;
    }
  }

  Future<void> _prosesAbsensi() async {
    setState(() {
      isLoading = true;
      statusPesan = "Menyiapkan data...";
    });

    try {
      await _controller!.stopImageStream();
      XFile fotoFile = await _controller!.takePicture();

      // === LOGIKA PENGGUNAAN LOKASI YANG DIPERBARUI ===
      Position finalPosition;

      // Jika GPS belum selesai mencari di background, tunggu sebentar di sini
      if (_userPosition == null) {
        setState(() => statusPesan = "Menunggu akurasi GPS...");
        finalPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
      } else {
        // Jika sudah siap (kebanyakan kasus), langsung pakai!
        finalPosition = _userPosition!;
      }

      setState(() => statusPesan = "Mengirim data...");

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      if (token == null || token.isEmpty) {
        setState(() {
          isAbsensiSelesai = true;
          statusPesan = "Error: Sesi login habis.";
        });
        return;
      }

      String apiUrl =
          "http://192.168.100.234/backend-absensi/public/api/attendances";

      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.headers.addAll({
        "Accept": "application/json",
        "Authorization": "Bearer $token",
      });

      request.fields['nip'] = "TA-2026-001";
      request.fields['latitude'] = finalPosition.latitude.toString();
      request.fields['longitude'] = finalPosition.longitude.toString();
      request.files.add(
        await http.MultipartFile.fromPath('foto', fotoFile.path),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      var data = jsonDecode(response.body);

      setState(() {
        isAbsensiSelesai = true;
        if (response.statusCode == 200 || response.statusCode == 201) {
          String jarak = (data['data'] != null)
              ? data['data']['jarak_meter'].toString()
              : '?';
          statusPesan = "BERHASIL!\nJarak: $jarak m";
        } else {
          statusPesan = "Gagal: ${data['message'] ?? 'Kesalahan server'}";
        }
      });
    } catch (e) {
      setState(() {
        isAbsensiSelesai = true;
        statusPesan = "Error jaringan";
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    try {
      _controller?.stopImageStream();
    } catch (_) {}
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // === MENGGUNAKAN WARNA DARI APP_STYLES ===
    Color activeColor = isBlinked ? AppColors.darkGreen : AppColors.goldAccent;
    Color activeLightColor = isBlinked
        ? const Color(0xFFDCE9FF)
        : const Color(0x33FDC74E);

    return Scaffold(
      backgroundColor: AppColors.bgScaffold,
      // ---> SANGAT BERSIH: Bottom Nav sekarang hanya butuh 1 baris kode (Index 2 untuk Verify)! <---
      bottomNavigationBar: const CustomBottomNav(activeIndex: 1),

      body: SafeArea(
        child: Column(
          children: [
            // === HEADER ===
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
                          color: const Color(0xFFE5EEFF),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: const Icon(
                          Icons.shield,
                          color: AppColors.darkGreen,
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

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Column(
                  children: [
                    // === STATUS TAGS DENGAN LOGIKA GPS DINAMIS ===
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTag(
                          Icons.location_on,
                          _userPosition != null
                              ? "GPS location\nverified"
                              : "Mencari\nlokasi...",
                          _userPosition != null
                              ? AppColors.darkGreen
                              : Colors.orange.shade800,
                          _userPosition != null
                              ? const Color(0xFFDCE9FF)
                              : Colors.orange.shade100,
                        ),
                        const SizedBox(width: 8),
                        _buildTag(
                          isBlinked
                              ? Icons.check_circle
                              : Icons.face_retouching_natural,
                          statusPesan,
                          activeColor,
                          activeLightColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // === CAMERA CONTAINER ===
                    Container(
                      width: 320,
                      height: 400,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(
                          color: const Color(0xFFDCE9FF),
                          width: 4,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x142D5A43),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(36),
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: isCameraInitialized
                                  ? FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: _controller!
                                            .value
                                            .previewSize!
                                            .height,
                                        height: _controller!
                                            .value
                                            .previewSize!
                                            .width,
                                        child: CameraPreview(_controller!),
                                      ),
                                    )
                                  : const Center(
                                      child: CircularProgressIndicator(
                                        color: AppColors.darkGreen,
                                      ),
                                    ),
                            ),
                          ),

                          if (!isAbsensiSelesai)
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(36),
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),

                          if (isCameraInitialized && !isAbsensiSelesai)
                            Center(
                              child: SizedBox(
                                width: 250,
                                height: 235,
                                child: Stack(
                                  children: [
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      child: _buildCorner(
                                        true,
                                        true,
                                        activeColor,
                                      ),
                                    ),
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: _buildCorner(
                                        true,
                                        false,
                                        activeColor,
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      child: _buildCorner(
                                        false,
                                        true,
                                        activeColor,
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: _buildCorner(
                                        false,
                                        false,
                                        activeColor,
                                      ),
                                    ),

                                    if (!isBlinked && !isLoading)
                                      AnimatedBuilder(
                                        animation: _scanAnimationController,
                                        builder: (context, child) {
                                          return Positioned(
                                            top:
                                                _scanAnimationController.value *
                                                230,
                                            left: 10,
                                            right: 10,
                                            child: Container(
                                              height: 3,
                                              decoration: BoxDecoration(
                                                color: AppColors.goldLight,
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: AppColors.goldLight,
                                                    blurRadius: 10,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),

                          Positioned(
                            bottom: 24,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: isAbsensiSelesai
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        statusPesan,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: AppColors.darkGreen,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : isLoading
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.darkGreen.withValues(
                                          alpha: 0.9,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            "Memproses...",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : isBlinked
                                  ? ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.darkGreen,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 32,
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      // Tombol akan mati jika GPS masih loading
                                      onPressed: _isFetchingGps
                                          ? null
                                          : _prosesAbsensi,
                                      icon: _isFetchingGps
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.fingerprint,
                                              color: Colors.white,
                                            ),
                                      label: Text(
                                        _isFetchingGps
                                            ? "Menunggu GPS..."
                                            : "CLOCK IN",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.darkGreen.withValues(
                                          alpha: 0.9,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        "Align your face within the frame",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            "DEVICE ID",
                            "AP-7704-B",
                            AppColors.darkGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildInfoCard(
                            "TRUST SCORE",
                            "98.4% Secure",
                            AppColors.goldAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === LOCAL HELPERS ===
  Widget _buildCorner(bool isTop, bool isLeft, Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? BorderSide(color: color, width: 4) : BorderSide.none,
          bottom: !isTop ? BorderSide(color: color, width: 4) : BorderSide.none,
          left: isLeft ? BorderSide(color: color, width: 4) : BorderSide.none,
          right: !isLeft ? BorderSide(color: color, width: 4) : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: (isTop && isLeft) ? const Radius.circular(24) : Radius.zero,
          topRight: (isTop && !isLeft)
              ? const Radius.circular(24)
              : Radius.zero,
          bottomLeft: (!isTop && isLeft)
              ? const Radius.circular(24)
              : Radius.zero,
          bottomRight: (!isTop && !isLeft)
              ? const Radius.circular(24)
              : Radius.zero,
        ),
      ),
    );
  }

  Widget _buildTag(IconData icon, String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accentColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
