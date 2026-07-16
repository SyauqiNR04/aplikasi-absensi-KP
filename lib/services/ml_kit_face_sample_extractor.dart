// ml_kit_face_sample_extractor.dart
//
// Implementasi FaceSampleExtractor berbasis Google ML Kit + package image.
// Menangani: decode, downscale (hemat memori), deteksi, aturan jumlah wajah,
// gerbang kualitas (gelap/blur/terlalu jauh), crop + align, dan pembersihan
// file temp. Semua kegagalan dilempar sebagai FaceProcessingException.
//
// Diuji lewat integration test di device (butuh platform channel ML Kit).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'face_verification_service.dart';

class MlKitFaceSampleExtractor implements FaceSampleExtractor {
  final FaceDetector _detector;

  /// Batas dimensi terpanjang (px) saat proses -> menekan puncak memori foto
  /// resolusi tinggi. 1280 cukup untuk deteksi & embedding.
  final int maxProcessingDimension;

  // Gerbang kualitas (hanya diberlakukan untuk gambar live).
  final double minFaceRatio; // lebar wajah / lebar gambar
  final double minBrightness; // luminance rata-rata 0-255
  final double minSharpness; // varians Laplacian

  MlKitFaceSampleExtractor({
    FaceDetector? detector,
    this.maxProcessingDimension = 1280,
    this.minFaceRatio = 0.12,
    this.minBrightness = 45,
    this.minSharpness = 90,
  }) : _detector = detector ??
            FaceDetector(
              options: FaceDetectorOptions(
                enableLandmarks: true,
                enableClassification: false,
                enableContours: false,
                enableTracking: false,
                performanceMode: FaceDetectorMode.accurate,
                minFaceSize: 0.1,
              ),
            );

  @override
  Future<FaceSample> extract(Uint8List bytes, {required bool isLive}) async {
    final tempFiles = <File>[];
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw FaceProcessingException(
          FaceMatchStatus.processingFailed,
          'Gagal membaca ${isLive ? "gambar live" : "gambar referensi"} '
          '(format tidak dikenali/korup).',
        );
      }

      final scaled = _downscale(decoded);

      // ML Kit InputImage.fromFilePath butuh file -> tulis versi downscaled.
      final tempPath = await _writeTempJpeg(scaled, isLive ? 'live' : 'ref');
      tempFiles.add(File(tempPath));

      final faces =
          await _detector.processImage(InputImage.fromFilePath(tempPath));

      if (faces.isEmpty) {
        throw FaceProcessingException(
          isLive
              ? FaceMatchStatus.noFaceInLiveImage
              : FaceMatchStatus.noFaceInReferenceImage,
          isLive
              ? 'Wajah tidak terdeteksi. Pastikan pencahayaan cukup dan wajah '
                  'menghadap kamera.'
              : 'Wajah tidak terdeteksi pada foto referensi.',
        );
      }
      if (faces.length > 1) {
        throw FaceProcessingException(
          isLive
              ? FaceMatchStatus.multipleFacesInLiveImage
              : FaceMatchStatus.multipleFacesInReferenceImage,
          'Terdeteksi ${faces.length} wajah pada '
          '${isLive ? "kamera" : "foto referensi"}. Harus tepat satu wajah.',
        );
      }

      final face = faces.first;

      if (isLive) {
        final reason = _assessQuality(scaled, face);
        if (reason != null) {
          throw FaceProcessingException(
              FaceMatchStatus.lowQualityLiveImage, reason);
        }
      }

      return FaceSample(_cropAndAlign(scaled, face), face);
    } finally {
      for (final f in tempFiles) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {/* diamkan */}
      }
    }
  }

  @override
  Future<void> dispose() async => _detector.close();

  // --------------------------------------------------------------------------
  img.Image _downscale(img.Image src) {
    final longest = math.max(src.width, src.height);
    if (longest <= maxProcessingDimension) return src;
    final scale = maxProcessingDimension / longest;
    return img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  Future<String> _writeTempJpeg(img.Image image, String tag) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/face_${tag}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(img.encodeJpg(image, quality: 90));
    return path;
  }

  /// Return null jika lolos; alasan (String) jika gagal.
  String? _assessQuality(img.Image image, Face face) {
    final ratio = face.boundingBox.width / image.width;
    if (ratio < minFaceRatio) {
      return 'Wajah terlalu kecil/jauh. Dekatkan wajah ke kamera.';
    }
    final r = _clampRect(face.boundingBox, image.width, image.height);
    final crop = img.copyCrop(image,
        x: r.left, y: r.top, width: r.width, height: r.height);

    if (_meanLuminance(crop) < minBrightness) {
      return 'Gambar terlalu gelap. Tambahkan pencahayaan.';
    }
    if (_laplacianVariance(crop) < minSharpness) {
      return 'Gambar buram. Tahan ponsel lebih stabil dan fokuskan wajah.';
    }
    return null;
  }

  double _meanLuminance(img.Image im) {
    var sum = 0.0;
    var count = 0;
    final stepX = math.max(1, im.width ~/ 64);
    final stepY = math.max(1, im.height ~/ 64);
    for (var y = 0; y < im.height; y += stepY) {
      for (var x = 0; x < im.width; x += stepX) {
        sum += img.getLuminance(im.getPixel(x, y));
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  double _laplacianVariance(img.Image im) {
    final small = img.copyResize(
      img.grayscale(im),
      width: math.min(im.width, 160),
      height: math.min(im.height, 160),
      interpolation: img.Interpolation.average,
    );
    final w = small.width, h = small.height;
    final values = <double>[];
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final c = img.getLuminance(small.getPixel(x, y));
        final up = img.getLuminance(small.getPixel(x, y - 1));
        final down = img.getLuminance(small.getPixel(x, y + 1));
        final left = img.getLuminance(small.getPixel(x - 1, y));
        final right = img.getLuminance(small.getPixel(x + 1, y));
        values.add((up + down + left + right - 4 * c).toDouble());
      }
    }
    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    var variance = 0.0;
    for (final v in values) {
      variance += (v - mean) * (v - mean);
    }
    return variance / values.length;
  }

  img.Image _cropAndAlign(img.Image image, Face face) {
    final box = face.boundingBox;
    final mx = box.width * 0.20;
    final my = box.height * 0.20;
    final r = _clampRect(
      Rect.fromLTRB(
          box.left - mx, box.top - my, box.right + mx, box.bottom + my),
      image.width,
      image.height,
    );
    var crop = img.copyCrop(image,
        x: r.left, y: r.top, width: r.width, height: r.height);

    // Luruskan roll wajah via euler angle Z (tersedia di mode accurate).
    final roll = face.headEulerAngleZ;
    if (roll != null && roll.abs() > 3) {
      crop = img.copyRotate(crop, angle: -roll);
    }
    return crop;
  }

  _IntRect _clampRect(Rect r, int maxW, int maxH) {
    final left = r.left.floor().clamp(0, maxW - 1);
    final top = r.top.floor().clamp(0, maxH - 1);
    final right = r.right.ceil().clamp(left + 1, maxW);
    final bottom = r.bottom.ceil().clamp(top + 1, maxH);
    return _IntRect(left, top, right - left, bottom - top);
  }
}

class _IntRect {
  final int left, top, width, height;
  const _IntRect(this.left, this.top, this.width, this.height);
}
