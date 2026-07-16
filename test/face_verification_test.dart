// face_verification_test.dart
//
// Jalankan: flutter test
// dev_dependencies:
//   flutter_test:
//     sdk: flutter
//   mocktail: ^1.0.4
//
// GANTI `your_app` di bawah dengan nama package dari pubspec.yaml kamu.

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';

import 'package:flutter_application_1/services/face_verification_service.dart';
import 'package:flutter_application_1/services/dio_reference_image_provider.dart';

// --- Mocks -------------------------------------------------------------------
class MockReferenceImageProvider extends Mock implements ReferenceImageProvider {}

class MockFaceSampleExtractor extends Mock implements FaceSampleExtractor {}

class MockFaceMatcher extends Mock implements FaceMatcher {}

class MockFace extends Mock implements Face {}

class MockDio extends Mock implements Dio {}

// FaceSample palsu — service tidak pernah menyentuh isinya (matcher dimock),
// jadi cukup nilai dummy yang tidak memanggil platform.
FaceSample _dummySample() => FaceSample(img.Image(width: 2, height: 2), MockFace());

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(_dummySample());
    registerFallbackValue(Options());
  });

  // ===========================================================================
  group('FaceVerificationService.verifyFaceMatch', () {
    late MockReferenceImageProvider provider;
    late MockFaceSampleExtractor extractor;
    late MockFaceMatcher matcher;
    late FaceVerificationService service;
    late File liveFile;

    setUp(() {
      provider = MockReferenceImageProvider();
      extractor = MockFaceSampleExtractor();
      matcher = MockFaceMatcher();
      service = FaceVerificationService(
        referenceProvider: provider,
        extractor: extractor,
        matcher: matcher,
        matchThreshold: 0.85,
      );
      liveFile = File(
          '${Directory.systemTemp.path}/live_${DateTime.now().microsecondsSinceEpoch}.jpg')
        ..writeAsBytesSync([0, 1, 2, 3]);
    });

    tearDown(() {
      if (liveFile.existsSync()) liveFile.deleteSync();
    });

    void stubDownloadOk() =>
        when(() => provider.fetch(any())).thenAnswer((_) async => Uint8List.fromList([9, 9]));

    void stubExtractOk() => when(() => extractor.extract(any(), isLive: any(named: 'isLive')))
        .thenAnswer((_) async => _dummySample());

    test('skor >= threshold -> matched', () async {
      stubDownloadOk();
      stubExtractOk();
      when(() => matcher.similarity(any(), any())).thenAnswer((_) async => 0.90);

      final r = await service.verifyFaceMatch(liveFile, 'https://cdn/x.jpg');

      expect(r.status, FaceMatchStatus.matched);
      expect(r.isMatch, isTrue);
      expect(r.similarity, 0.90);
    });

    test('skor tepat di threshold -> matched (batas inklusif)', () async {
      stubDownloadOk();
      stubExtractOk();
      when(() => matcher.similarity(any(), any())).thenAnswer((_) async => 0.85);

      final r = await service.verifyFaceMatch(liveFile, 'u');
      expect(r.isMatch, isTrue);
    });

    test('skor < threshold -> notMatched', () async {
      stubDownloadOk();
      stubExtractOk();
      when(() => matcher.similarity(any(), any())).thenAnswer((_) async => 0.50);

      final r = await service.verifyFaceMatch(liveFile, 'u');
      expect(r.status, FaceMatchStatus.notMatched);
      expect(r.isMatch, isFalse);
    });

    test('gagal unduh referensi -> referenceDownloadFailed, matcher tak dipanggil',
        () async {
      when(() => provider.fetch(any()))
          .thenThrow(ReferenceDownloadException('timeout'));

      final r = await service.verifyFaceMatch(liveFile, 'u');

      expect(r.status, FaceMatchStatus.referenceDownloadFailed);
      verifyNever(() => matcher.similarity(any(), any()));
    });

    test('wajah tak terdeteksi di live -> noFaceInLiveImage', () async {
      stubDownloadOk();
      when(() => extractor.extract(any(), isLive: true)).thenThrow(
          FaceProcessingException(FaceMatchStatus.noFaceInLiveImage, 'gelap'));

      final r = await service.verifyFaceMatch(liveFile, 'u');
      expect(r.status, FaceMatchStatus.noFaceInLiveImage);
    });

    test('>1 wajah di live -> multipleFacesInLiveImage', () async {
      stubDownloadOk();
      when(() => extractor.extract(any(), isLive: true)).thenThrow(
          FaceProcessingException(
              FaceMatchStatus.multipleFacesInLiveImage, '2 wajah'));

      final r = await service.verifyFaceMatch(liveFile, 'u');
      expect(r.status, FaceMatchStatus.multipleFacesInLiveImage);
    });

    test('live blur/gelap -> lowQualityLiveImage', () async {
      stubDownloadOk();
      when(() => extractor.extract(any(), isLive: true)).thenThrow(
          FaceProcessingException(
              FaceMatchStatus.lowQualityLiveImage, 'buram'));

      final r = await service.verifyFaceMatch(liveFile, 'u');
      expect(r.status, FaceMatchStatus.lowQualityLiveImage);
    });

    test('referensi tanpa wajah -> noFaceInReferenceImage', () async {
      stubDownloadOk();
      when(() => extractor.extract(any(), isLive: true))
          .thenAnswer((_) async => _dummySample());
      when(() => extractor.extract(any(), isLive: false)).thenThrow(
          FaceProcessingException(
              FaceMatchStatus.noFaceInReferenceImage, 'x'));

      final r = await service.verifyFaceMatch(liveFile, 'u');
      expect(r.status, FaceMatchStatus.noFaceInReferenceImage);
    });

    test('error tak terduga -> unexpectedError', () async {
      stubDownloadOk();
      when(() => extractor.extract(any(), isLive: any(named: 'isLive')))
          .thenThrow(StateError('boom'));

      final r = await service.verifyFaceMatch(liveFile, 'u');
      expect(r.status, FaceMatchStatus.unexpectedError);
    });
  });

  // ===========================================================================
  group('DioReferenceImageProvider', () {
    late MockDio dio;
    late DioReferenceImageProvider sut;

    setUp(() {
      dio = MockDio();
      sut = DioReferenceImageProvider(dio);
    });

    Response<List<int>> resp(int status, List<int>? data) => Response<List<int>>(
          requestOptions: RequestOptions(path: 'u'),
          statusCode: status,
          data: data,
        );

    test('200 -> mengembalikan bytes', () async {
      when(() => dio.get<List<int>>(any(), options: any(named: 'options')))
          .thenAnswer((_) async => resp(200, [1, 2, 3]));

      final bytes = await sut.fetch('https://cdn/x.jpg');
      expect(bytes, Uint8List.fromList([1, 2, 3]));
    });

    test('data kosong -> ReferenceDownloadException', () async {
      when(() => dio.get<List<int>>(any(), options: any(named: 'options')))
          .thenAnswer((_) async => resp(200, <int>[]));

      expect(() => sut.fetch('u'), throwsA(isA<ReferenceDownloadException>()));
    });

    test('status non-200 -> ReferenceDownloadException', () async {
      when(() => dio.get<List<int>>(any(), options: any(named: 'options')))
          .thenAnswer((_) async => resp(404, [1]));

      expect(() => sut.fetch('u'), throwsA(isA<ReferenceDownloadException>()));
    });

    test('DioException timeout -> ReferenceDownloadException', () async {
      when(() => dio.get<List<int>>(any(), options: any(named: 'options')))
          .thenThrow(DioException(
              requestOptions: RequestOptions(path: 'u'),
              type: DioExceptionType.receiveTimeout));

      expect(() => sut.fetch('u'), throwsA(isA<ReferenceDownloadException>()));
    });
  });
}
