// face_verification_service.dart
//
// Orkestrasi verifikasi wajah. SEMUA dependency di-inject (DIP) sehingga
// service ini bisa di-unit test tanpa platform channel:
//   - ReferenceImageProvider : sumber byte foto referensi (Dio/http/mock)
//   - FaceSampleExtractor     : deteksi + quality gate + crop/align (ML Kit/mock)
//   - FaceMatcher             : strategi kemiripan (embedding/landmark/mock)
//
// Tidak menyentuh UI. Tidak pernah melempar exception ke pemanggil.
//
// Dependencies inti:
//   google_mlkit_face_detection: ^0.13.1   // tipe Face dipakai FaceSample
//   image: ^4.3.0
//   tflite_flutter: ^0.11.0                // hanya untuk EmbeddingFaceMatcher
//   http: ^1.2.2                           // hanya untuk HttpReferenceImageProvider

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:tflite_flutter/tflite_flutter.dart';

// =============================================================================
// HASIL
// =============================================================================

enum FaceMatchStatus {
  matched,
  notMatched,
  noFaceInLiveImage,
  noFaceInReferenceImage,
  multipleFacesInLiveImage,
  multipleFacesInReferenceImage,
  lowQualityLiveImage,
  referenceDownloadFailed,
  processingFailed,
  unexpectedError,
}

class FaceMatchResult {
  final bool isMatch;
  final double? similarity; // 0.0 - 1.0
  final double threshold;
  final FaceMatchStatus status;
  final String message;

  const FaceMatchResult({
    required this.isMatch,
    required this.status,
    required this.message,
    required this.threshold,
    this.similarity,
  });

  double? get similarityPercent =>
      similarity == null ? null : similarity! * 100;

  factory FaceMatchResult.success({
    required double similarity,
    required double threshold,
  }) =>
      FaceMatchResult(
        isMatch: true,
        similarity: similarity,
        threshold: threshold,
        status: FaceMatchStatus.matched,
        message:
            'Wajah cocok (skor: ${(similarity * 100).toStringAsFixed(1)}%).',
      );

  factory FaceMatchResult.mismatch({
    required double similarity,
    required double threshold,
  }) =>
      FaceMatchResult(
        isMatch: false,
        similarity: similarity,
        threshold: threshold,
        status: FaceMatchStatus.notMatched,
        message:
            'Wajah tidak cocok (skor: ${(similarity * 100).toStringAsFixed(1)}%, '
            'butuh >= ${(threshold * 100).toStringAsFixed(1)}%).',
      );

  factory FaceMatchResult.failure(
    FaceMatchStatus status,
    String message, {
    double threshold = 0,
  }) =>
      FaceMatchResult(
        isMatch: false,
        status: status,
        message: message,
        threshold: threshold,
      );

  @override
  String toString() =>
      'FaceMatchResult(status: $status, isMatch: $isMatch, '
      'similarity: ${similarityPercent?.toStringAsFixed(1)}%)';
}

// =============================================================================
// ABSTRAKSI (semua mockable)
// =============================================================================

abstract class ReferenceImageProvider {
  Future<Uint8List> fetch(String url);
}

class ReferenceDownloadException implements Exception {
  final String message;
  ReferenceDownloadException(this.message);
  @override
  String toString() => 'ReferenceDownloadException: $message';
}

/// Wajah yang sudah dideteksi + crop + align, siap dibandingkan.
class FaceSample {
  final img.Image alignedFace;
  final Face detection;
  FaceSample(this.alignedFace, this.detection);
}

/// Dilempar oleh extractor saat gambar tidak lolos deteksi/kualitas.
class FaceProcessingException implements Exception {
  final FaceMatchStatus status;
  final String message;
  FaceProcessingException(this.status, this.message);
  @override
  String toString() => 'FaceProcessingException($status): $message';
}

/// Mengubah byte gambar menjadi FaceSample. Menyembunyikan seluruh
/// ketergantungan platform (ML Kit, decode, file temp) dari service.
abstract class FaceSampleExtractor {
  Future<FaceSample> extract(Uint8List bytes, {required bool isLive});
  Future<void> dispose();
}

/// Strategi perbandingan (Open/Closed + DIP).
abstract class FaceMatcher {
  Future<double> similarity(FaceSample live, FaceSample reference); // 0..1
  void dispose() {}
}

// =============================================================================
// DEFAULT: downloader http sederhana (tanpa dependency). Untuk produksi,
// gunakan DioReferenceImageProvider agar dapat auth interceptor.
// =============================================================================

class HttpReferenceImageProvider implements ReferenceImageProvider {
  final http.Client _client;
  final Duration timeout;
  final Map<String, String>? headers;

  HttpReferenceImageProvider({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.headers,
  }) : _client = client ?? http.Client();

  @override
  Future<Uint8List> fetch(String url) async {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      throw ReferenceDownloadException('URL referensi tidak valid: $url');
    }
    try {
      final res = await _client.get(uri, headers: headers).timeout(timeout);
      if (res.statusCode != 200) {
        throw ReferenceDownloadException(
            'Server membalas ${res.statusCode} saat mengunduh referensi.');
      }
      if (res.bodyBytes.isEmpty) {
        throw ReferenceDownloadException('Gambar referensi kosong.');
      }
      return res.bodyBytes;
    } on ReferenceDownloadException {
      rethrow;
    } catch (e) {
      throw ReferenceDownloadException('Gagal mengunduh referensi: $e');
    }
  }
}

// =============================================================================
// MATCHER REKOMENDASI: MobileFaceNet + cosine
// =============================================================================

class EmbeddingFaceMatcher implements FaceMatcher {
  final int inputSize;
  final int embeddingSize;
  final Interpreter _interpreter;

  EmbeddingFaceMatcher._(this._interpreter, this.inputSize, this.embeddingSize);

  static Future<EmbeddingFaceMatcher> load({
    String assetPath = 'assets/models/mobilefacenet.tflite',
    int inputSize = 112,
    int embeddingSize = 192,
    int threads = 2,
  }) async {
    final options = InterpreterOptions()..threads = threads;
    final interpreter = await Interpreter.fromAsset(assetPath, options: options);
    return EmbeddingFaceMatcher._(interpreter, inputSize, embeddingSize);
  }

  @override
  Future<double> similarity(FaceSample live, FaceSample reference) async {
    final a = _embed(live.alignedFace);
    final b = _embed(reference.alignedFace);
    final cos = _cosine(a, b); // [-1,1]
    return ((cos + 1) / 2).clamp(0.0, 1.0);
  }

  List<double> _embed(img.Image face) {
    final resized = (face.width == inputSize && face.height == inputSize)
        ? face
        : img.copyResize(face, width: inputSize, height: inputSize);
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(inputSize, (x) {
          final p = resized.getPixel(x, y);
          return <double>[
            (p.r - 127.5) / 127.5,
            (p.g - 127.5) / 127.5,
            (p.b - 127.5) / 127.5,
          ];
        }),
      ),
    );
    final output = List.generate(1, (_) => List.filled(embeddingSize, 0.0));
    _interpreter.run(input, output);
    return _l2normalize(output[0]);
  }

  static List<double> _l2normalize(List<double> v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final norm = math.sqrt(sum);
    return norm == 0 ? v : [for (final x in v) x / norm];
  }

  static double _cosine(List<double> a, List<double> b) {
    var dot = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot; // sudah L2-normalized
  }

  @override
  void dispose() => _interpreter.close();
}

// =============================================================================
// MATCHER FALLBACK: geometri landmark (PROTOTIPE SAJA — bukan biometrik andal)
// =============================================================================

class LandmarkFaceMatcher implements FaceMatcher {
  @override
  void dispose() {}

  @override
  Future<double> similarity(FaceSample live, FaceSample reference) async {
    final a = _signature(live.detection);
    final b = _signature(reference.detection);
    if (a == null || b == null) return 0;
    var sq = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sq += d * d;
    }
    return (1 / (1 + math.sqrt(sq))).clamp(0.0, 1.0);
  }

  List<double>? _signature(Face f) {
    math.Point<int>? pt(FaceLandmarkType t) => f.landmarks[t]?.position;
    final le = pt(FaceLandmarkType.leftEye);
    final re = pt(FaceLandmarkType.rightEye);
    final nose = pt(FaceLandmarkType.noseBase);
    final lm = pt(FaceLandmarkType.leftMouth);
    final rm = pt(FaceLandmarkType.rightMouth);
    if ([le, re, nose, lm, rm].any((p) => p == null)) return null;
    final eye = _dist(le!, re!);
    if (eye == 0) return null;
    double n(math.Point<int> a, math.Point<int> b) => _dist(a, b) / eye;
    return [
      n(le, nose!),
      n(re, nose),
      n(le, lm!),
      n(re, rm!),
      n(nose, lm),
      n(nose, rm),
      n(lm, rm),
    ];
  }

  static double _dist(math.Point<int> a, math.Point<int> b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }
}

// =============================================================================
// SERVICE (orkestrasi murni — testable)
// =============================================================================

class FaceVerificationService {
  final ReferenceImageProvider _referenceProvider;
  final FaceSampleExtractor _extractor;
  final FaceMatcher _matcher;

  /// Ambang kecocokan (0..1). Untuk MobileFaceNet+cosine yang dipetakan ke
  /// [0,1], operating point wajar ~0.75-0.80. 0.85 sesuai spesifikasi awal —
  /// WAJIB dikalibrasi dg dataset-mu (ukur FAR/FRR).
  final double matchThreshold;

  FaceVerificationService({
    required ReferenceImageProvider referenceProvider,
    required FaceSampleExtractor extractor,
    required FaceMatcher matcher,
    this.matchThreshold = 0.85,
  })  : _referenceProvider = referenceProvider,
        _extractor = extractor,
        _matcher = matcher;

  Future<FaceMatchResult> verifyFaceMatch(
    File liveImage,
    String referenceImageUrl,
  ) async {
    try {
      // 1. Unduh referensi.
      final Uint8List referenceBytes;
      try {
        referenceBytes = await _referenceProvider.fetch(referenceImageUrl);
      } on ReferenceDownloadException catch (e) {
        return FaceMatchResult.failure(
          FaceMatchStatus.referenceDownloadFailed,
          e.message,
          threshold: matchThreshold,
        );
      }

      final liveBytes = await liveImage.readAsBytes();

      // 2. Ekstraksi sampel (live dulu -> fail-fast).
      final FaceSample liveSample;
      try {
        liveSample = await _extractor.extract(liveBytes, isLive: true);
      } on FaceProcessingException catch (e) {
        return FaceMatchResult.failure(e.status, e.message,
            threshold: matchThreshold);
      }

      final FaceSample refSample;
      try {
        refSample = await _extractor.extract(referenceBytes, isLive: false);
      } on FaceProcessingException catch (e) {
        return FaceMatchResult.failure(e.status, e.message,
            threshold: matchThreshold);
      }

      // 3. Bandingkan + putuskan.
      final score = await _matcher.similarity(liveSample, refSample);
      return score >= matchThreshold
          ? FaceMatchResult.success(similarity: score, threshold: matchThreshold)
          : FaceMatchResult.mismatch(
              similarity: score, threshold: matchThreshold);
    } catch (e) {
      return FaceMatchResult.failure(
        FaceMatchStatus.unexpectedError,
        'Kesalahan tak terduga saat verifikasi: $e',
        threshold: matchThreshold,
      );
    }
  }

  Future<void> dispose() async {
    await _extractor.dispose();
    _matcher.dispose();
  }
}
