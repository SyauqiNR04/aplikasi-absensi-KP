import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Sesuaikan jika path berbeda
import '../constants/app_styles.dart'; // Import File Warna Global
import '../widgets/custom_bottom_nav.dart'; // Import Custom Bottom Nav
import '../services/liveness_challenge.dart';
import '../services/face_verification_service.dart';
import '../services/attendance_api_service.dart';
import '../services/ml_kit_face_sample_extractor.dart';
import '../services/session_manager.dart';

class CameraScreen extends StatefulWidget {
  /// True kalau karyawan sudah absen masuk hari ini (jadi sesi ini adalah
  /// absen PULANG). Server tetap yang menentukan aksi sesungguhnya (masuk
  /// vs pulang) dari state di database -- ini cuma dipakai untuk label
  /// tombol/pesan supaya user tidak bingung.
  final bool isCheckOut;

  const CameraScreen({super.key, this.isCheckOut = false});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool isCameraInitialized = false;
  bool isLoading = false;
  bool isAbsensiSelesai = false;

  // Animasi Garis Scanner
  late AnimationController _scanAnimationController;

  final FaceDetector _faceDetector = FaceDetector(
    options: LivenessChallengeController.recommendedStreamOptions(),
  );

  // === LIVENESS CHALLENGE ACAK (kedip / tengok kiri / tengok kanan / senyum) ===
  // mirrorFrontCamera perlu dikalibrasi di perangkat asli: jika arah tengok
  // kiri/kanan terasa terbalik, ubah nilai ini.
  final LivenessChallengeController _liveness = LivenessChallengeController(
    challengeCount: 3,
    // Dikalibrasi di device asli (Xiaomi/Redmi, kamera depan): arah
    // tengok kiri/kanan yang dilaporkan ML Kit sudah sesuai tanpa mirror.
    mirrorFrontCamera: false,
  );
  LivenessState _livenessState = LivenessState.idle;
  StreamSubscription<LivenessState>? _livenessSub;

  bool isDetecting = false;

  // === FACE MATCHING (verifikasi identitas vs foto referensi karyawan) ===
  // Satu sumber alamat server dengan layar lain: saat IP backend berubah,
  // tidak ada endpoint yang tertinggal memakai host lama.
  static final _refPhotoUrl =
      "${SessionManager.baseUrl}/api/reference-photo";
  FaceVerificationService? _faceVerification;

  final AttendanceApiService _attendanceApi = AttendanceApiService();
  bool _isMatcherLoading = true;
  String? _matcherLoadError;

  // Pesan status selama proses ambil-foto & kirim-absensi (menimpa pesan
  // liveness saat isLoading/isAbsensiSelesai aktif).
  String? _captureStatusMessage;

  String get statusPesan {
    if (_captureStatusMessage != null) return _captureStatusMessage!;
    switch (_livenessState.status) {
      case LivenessStatus.idle:
        return "Bersiap...";
      case LivenessStatus.running:
        return _livenessState.instruction;
      case LivenessStatus.passed:
        return "Verifikasi Asli!";
      case LivenessStatus.failed:
        return _livenessState.instruction;
    }
  }

  bool get isBlinked => _livenessState.status == LivenessStatus.passed;
  bool get isLivenessFailed => _livenessState.status == LivenessStatus.failed;

  // === VARIABEL BARU UNTUK LOKASI BACKGROUND ===
  Position? _userPosition;
  bool _isFetchingGps = true;

  @override
  void initState() {
    super.initState();

    _livenessSub = _liveness.states.listen((state) {
      if (!mounted) return;
      setState(() => _livenessState = state);
      if (state.status == LivenessStatus.running) {
        if (!_scanAnimationController.isAnimating) {
          _scanAnimationController.repeat(reverse: true);
        }
      } else {
        _scanAnimationController.stop();
      }
    });

    _inisialisasiKamera();
    _inisialisasiFaceVerification();

    // Langsung cari lokasi GPS di latar belakang saat halaman dibuka
    _ambilLokasiBackground();

    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  void _mulaiUlangLiveness() {
    _liveness.start();
  }

  // === FUNGSI: Muat model MobileFaceNet + siapkan service face matching ===
  Future<void> _inisialisasiFaceVerification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final matcher = await EmbeddingFaceMatcher.load();
      final service = FaceVerificationService(
        referenceProvider: HttpReferenceImageProvider(
          headers: {'Authorization': 'Bearer $token'},
        ),
        extractor: MlKitFaceSampleExtractor(),
        matcher: matcher,
        matchThreshold: 0.80,
      );

      if (!mounted) {
        await service.dispose();
        return;
      }
      setState(() {
        _faceVerification = service;
        _isMatcherLoading = false;
      });
    } catch (e) {
      debugPrint("Error memuat model face matching: $e");
      if (!mounted) return;
      setState(() {
        _isMatcherLoading = false;
        _matcherLoadError = "Gagal memuat model verifikasi wajah.";
      });
    }
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

      _liveness.start();
      _mulaiStreamDeteksi(kameraDepan);
    } catch (e) {
      setState(() {
        _captureStatusMessage = "Gagal buka kamera";
      });
    }
  }

  void _mulaiStreamDeteksi(CameraDescription camera) {
    _controller!.startImageStream((CameraImage image) {
      if (isLoading || isAbsensiSelesai) return;

      if (!isDetecting) {
        isDetecting = true;
        _prosesDeteksiWajah(image, camera);
      }
    });
  }

  /// Reset layar absensi tanpa keluar dari halaman: dipakai tombol
  /// "Absen Ulang" setelah wajah tidak cocok / gagal, atau setelah sukses
  /// bila ingin absen device lain di sesi yang sama.
  Future<void> _absenUlang() async {
    setState(() {
      isAbsensiSelesai = false;
      isLoading = false;
      _captureStatusMessage = null;
    });

    try {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          !_controller!.value.isStreamingImages) {
        _mulaiStreamDeteksi(_controller!.description);
      }
    } catch (e) {
      debugPrint("Error restart stream: $e");
    }

    _liveness.start();
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
        _liveness.onDetection(faces);
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
      _captureStatusMessage = "Menyiapkan data...";
    });

    try {
      await _controller!.stopImageStream();
      XFile fotoFile = await _controller!.takePicture();

      // === FACE MATCHING: bandingkan wajah live dengan foto referensi ===
      setState(() => _captureStatusMessage = "Memverifikasi wajah...");

      final faceService = _faceVerification;
      if (faceService == null) {
        setState(() {
          isAbsensiSelesai = true;
          _captureStatusMessage = "Model verifikasi wajah belum siap.";
        });
        return;
      }

      final matchResult = await faceService.verifyFaceMatch(
        File(fotoFile.path),
        _refPhotoUrl,
      );
      if (!matchResult.isMatch) {
        debugPrint(
          "FaceMatch gagal: status=${matchResult.status} pesan_asli=${matchResult.message}",
        );

        // 401 saat mengunduh referensi = token mati, bukan foto bermasalah.
        // Tanpa cabang ini, sesi kedaluwarsa muncul sebagai pesan yang
        // menyesatkan ("foto referensi bermasalah, hubungi admin").
        if (matchResult.status == FaceMatchStatus.referenceDownloadFailed &&
            matchResult.message.contains('401')) {
          if (!mounted) return;
          await SessionManager.forceLogout(context);
          return;
        }

        setState(() {
          isAbsensiSelesai = true;
          _captureStatusMessage = _pesanGagalVerifikasi(matchResult);
        });
        return;
      }

      // === LOGIKA PENGGUNAAN LOKASI YANG DIPERBARUI ===
      Position finalPosition;

      // Jika GPS belum selesai mencari di background, tunggu sebentar di sini
      if (_userPosition == null) {
        setState(() => _captureStatusMessage = "Menunggu akurasi GPS...");
        finalPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
      } else {
        // Jika sudah siap (kebanyakan kasus), langsung pakai!
        finalPosition = _userPosition!;
      }

      setState(() => _captureStatusMessage = "Mengirim data...");

      // Pengiriman lewat AttendanceApiService, bukan MultipartRequest rakitan
      // sendiri. Versi rakitan melewati gerbang integritas perangkat
      // (root/emulator/Fake GPS) dan pemeriksaan HTTPS build rilis, sehingga
      // kontrol-kontrol itu tidak pernah benar-benar berjalan saat absensi.
      // Bukti verifikasi wajah juga dirakit di sana.
      final hasil = await _attendanceApi.submitAttendance(
        latitude: finalPosition.latitude,
        longitude: finalPosition.longitude,
        foto: File(fotoFile.path),
        faceMatchScore: matchResult.similarity,
        faceMatchThreshold: matchResult.threshold,
        livenessPassed: _livenessState.status == LivenessStatus.passed,
        livenessChallenges: _liveness.sequenceNames,
      );

      if (hasil.sessionExpired) {
        if (!mounted) return;
        await SessionManager.forceLogout(context);
        return;
      }

      setState(() {
        isAbsensiSelesai = true;
        if (hasil.success) {
          final tipe = hasil.data?['type'];
          if (tipe == 'pulang') {
            final totalJam = hasil.data?['total_jam_kerja'] ?? '-';
            _captureStatusMessage =
                "ABSEN PULANG BERHASIL!\nTotal jam kerja: $totalJam";
          } else {
            final jarak = hasil.data?['jarak_meter']?.toString() ?? '?';
            _captureStatusMessage = "ABSEN MASUK BERHASIL!\nJarak: $jarak m";
          }
        } else {
          _captureStatusMessage = "Gagal: ${hasil.message}";
        }
      });
    } on AttendanceBlockedException catch (e) {
      // Perangkat ditolak atau konfigurasi jaringan tidak aman: sebabnya
      // spesifik dan bisa ditindaklanjuti, jadi jangan disamarkan sebagai
      // "error jaringan" seperti sebelumnya.
      setState(() {
        isAbsensiSelesai = true;
        _captureStatusMessage = "Gagal: ${e.message}";
      });
    } catch (e) {
      setState(() {
        isAbsensiSelesai = true;
        _captureStatusMessage = "Error jaringan";
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// Pesan gagal verifikasi wajah yang ramah pengguna (tanpa skor mentah).
  String _pesanGagalVerifikasi(FaceMatchResult result) {
    switch (result.status) {
      case FaceMatchStatus.notMatched:
        return "Wajah tidak dikenali sebagai kamu. Coba lagi.";
      case FaceMatchStatus.noFaceInLiveImage:
      case FaceMatchStatus.multipleFacesInLiveImage:
      case FaceMatchStatus.lowQualityLiveImage:
        return "Posisikan wajah ke dalam bingkai atau pastikan wajah "
            "tidak terhalang rambut/masker, lalu coba lagi.";
      case FaceMatchStatus.noFaceInReferenceImage:
      case FaceMatchStatus.multipleFacesInReferenceImage:
      case FaceMatchStatus.referenceDownloadFailed:
        return "Foto referensi wajah bermasalah. Hubungi admin.";
      case FaceMatchStatus.processingFailed:
      case FaceMatchStatus.unexpectedError:
        return "Terjadi kesalahan saat memverifikasi wajah. Coba lagi.";
      case FaceMatchStatus.matched:
        return "Verifikasi Asli!";
    }
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    _livenessSub?.cancel();
    _liveness.dispose();
    _faceVerification?.dispose();
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
    Color activeColor = isBlinked
        ? AppColors.darkGreen
        : isLivenessFailed
        ? Colors.red.shade700
        : AppColors.goldAccent;
    Color activeLightColor = isBlinked
        ? const Color(0xFFDCE9FF)
        : isLivenessFailed
        ? const Color(0x33E53935)
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
                          isBlinked ? "Face: Verified" : "Face: Unverified",
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
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            statusPesan,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: AppColors.darkGreen,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.darkGreen,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 10,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                            onPressed: _absenUlang,
                                            icon: const Icon(
                                              Icons.refresh,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                            label: const Text(
                                              "Absen Ulang",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
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
                                      // Tombol akan mati jika GPS atau model verifikasi wajah masih loading
                                      onPressed: (_isFetchingGps || _isMatcherLoading)
                                          ? null
                                          : _prosesAbsensi,
                                      icon: (_isFetchingGps || _isMatcherLoading)
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
                                        _matcherLoadError != null
                                            ? _matcherLoadError!
                                            : _isMatcherLoading
                                            ? "Memuat model wajah..."
                                            : _isFetchingGps
                                            ? "Menunggu GPS..."
                                            : (widget.isCheckOut
                                                  ? "CLOCK OUT"
                                                  : "CLOCK IN"),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : isLivenessFailed
                                  ? ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.shade700,
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
                                      onPressed: _mulaiUlangLiveness,
                                      icon: const Icon(
                                        Icons.refresh,
                                        color: Colors.white,
                                      ),
                                      label: const Text(
                                        "Coba Lagi",
                                        style: TextStyle(
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
                                      child: Text(
                                        _livenessState.total == 0
                                            ? statusPesan
                                            : "$statusPesan  (${_livenessState.completed}/${_livenessState.total})",
                                        style: const TextStyle(
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
