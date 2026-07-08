import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:convert';
import '../main.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool isCameraInitialized = false;
  bool isLoading = false;
  bool isAbsensiSelesai = false;
  String statusPesan = "Menyiapkan AI...";

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

  @override
  void initState() {
    super.initState();
    _inisialisasiKamera();
  }

  Future<void> _inisialisasiKamera() async {
    final kameraDepan = globalCameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => globalCameras.first,
    );

    _controller = CameraController(
      kameraDepan,
      ResolutionPreset.low,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;

      setState(() {
        isCameraInitialized = true;
        statusPesan = "Arahkan wajah ke kamera";
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
        statusPesan = "Gagal membuka kamera: $e";
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
                }
                // Toleransi mata sipit (0.55)
                else if (isEyeClosed && mataKiri > 0.55 && mataKanan > 0.55) {
                  isBlinked = true;
                }
              }

              if (!isBlinked) {
                isFaceDetected = false;
                statusPesan = "Wajah terdeteksi.\nSilakan KEDIPKAN MATA Anda!";
              } else {
                isFaceDetected = true;
                statusPesan =
                    "Verifikasi Asli Sukses!\nSilakan klik tombol Absen.";
              }
            } else {
              isFaceDetected = true;
              statusPesan =
                  "Verifikasi Asli Sukses!\nSilakan klik tombol Absen.";
            }
          } else {
            isFaceDetected = false;
            isBlinked = false;
            isEyeClosed = false;
            statusPesan = "Mencari wajah...";
          }
        });
      }
    } catch (e) {
      debugPrint("Error AI: $e");
    } finally {
      isDetecting = false;
    }
  }

  @override
  void dispose() {
    try {
      _controller?.stopImageStream();
    } catch (_) {}
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _prosesAbsensi() async {
    setState(() {
      isLoading = true;
      statusPesan = "Mengambil foto bukti...";
    });

    String base64Image = "";

    try {
      // LOGIKA BARU: Hentikan aliran video sejenak untuk mengambil foto statis
      await _controller!.stopImageStream();
      XFile fotoFile = await _controller!.takePicture();

      // LOGIKA BARU: Ubah file gambar menjadi teks Base64
      List<int> imageBytes = await fotoFile.readAsBytes();
      base64Image = base64Encode(imageBytes);

      setState(() {
        statusPesan = "Memeriksa izin lokasi...";
      });

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            statusPesan = "Akses lokasi ditolak.";
            isLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          statusPesan = "Akses lokasi diblokir permanen.";
          isLoading = false;
        });
        return;
      }

      setState(() {
        statusPesan = "Mencatat lokasi satelit...";
      });

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        statusPesan = "Mengirim data & foto ke server...";
      });

      String apiUrl =
          "http://192.168.100.234/backend-absensi/public/api/attendances";

      var response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "nip": "TA-2026-001",
          "latitude": position.latitude,
          "longitude": position.longitude,
          "image": base64Image, // LOGIKA BARU: Mengirimkan teks foto ke Laravel
        }),
      );

      var data = jsonDecode(response.body);

      setState(() {
        isAbsensiSelesai = true;

        if (response.statusCode == 201) {
          statusPesan = "BERHASIL!\nJarak: ${data['jarak_anda']}";
        } else {
          statusPesan = "Gagal: ${data['detail'] ?? data['message']}";
        }
      });
    } catch (e) {
      setState(() {
        isAbsensiSelesai = true;
        statusPesan = "Terjadi kesalahan koneksi server: $e";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verifikasi Wajah')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: isCameraInitialized
                  ? CameraPreview(_controller!)
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
            ),
          ),

          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    statusPesan,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isAbsensiSelesai
                          ? Colors.blue
                          : (isBlinked
                                ? Colors.green
                                : (isFaceDetected
                                      ? Colors.orange
                                      : Colors.black)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (isAbsensiSelesai)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        backgroundColor: Colors.blue,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        "KEMBALI KE DASHBOARD",
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    )
                  else if (isLoading)
                    const CircularProgressIndicator()
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        backgroundColor: isFaceDetected
                            ? Colors.green
                            : Colors.grey,
                      ),
                      onPressed: isFaceDetected ? _prosesAbsensi : null,
                      child: const Text(
                        "KIRIM DATA ABSENSI",
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
