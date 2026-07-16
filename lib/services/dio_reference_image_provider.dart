// dio_reference_image_provider.dart
//
// Mengunduh foto referensi memakai instance Dio milik aplikasi — sehingga
// auth interceptor (Bearer token, refresh, dsb) dari fase keamanan otomatis
// ikut. Memetakan setiap kegagalan jaringan ke ReferenceDownloadException.
//
// dependencies: dio: ^5.7.0

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'face_verification_service.dart';

class DioReferenceImageProvider implements ReferenceImageProvider {
  final Dio _dio;

  /// Header tambahan opsional (auth utama diasumsikan dari interceptor Dio).
  final Map<String, String>? extraHeaders;

  DioReferenceImageProvider(this._dio, {this.extraHeaders});

  @override
  Future<Uint8List> fetch(String url) async {
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: extraHeaders,
          // Jangan lempar untuk non-2xx; kita tangani manual agar pesannya jelas.
          validateStatus: (_) => true,
        ),
      );

      final data = res.data;
      if (res.statusCode != 200) {
        throw ReferenceDownloadException(
            'Server membalas ${res.statusCode} saat mengunduh referensi.');
      }
      if (data == null || data.isEmpty) {
        throw ReferenceDownloadException('Gambar referensi kosong.');
      }
      return Uint8List.fromList(data);
    } on ReferenceDownloadException {
      rethrow;
    } on DioException catch (e) {
      throw ReferenceDownloadException(_mapDioError(e));
    } catch (e) {
      throw ReferenceDownloadException('Gagal mengunduh referensi: $e');
    }
  }

  String _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Timeout saat mengunduh gambar referensi.';
      case DioExceptionType.badResponse:
        return 'Server membalas ${e.response?.statusCode} saat mengunduh referensi.';
      case DioExceptionType.connectionError:
        return 'Tidak ada koneksi ke server referensi.';
      case DioExceptionType.cancel:
        return 'Pengunduhan referensi dibatalkan.';
      default:
        return 'Gagal mengunduh referensi: ${e.message ?? e.type.name}.';
    }
  }
}
