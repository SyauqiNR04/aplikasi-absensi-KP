// liveness_challenge.dart
//
// Active liveness: menuntut user melakukan urutan AKSI ACAK (kedip, tengok,
// senyum) yang berbeda tiap sesi. Mengalahkan serangan foto/video-replay yang
// lolos deteksi kedipan pasif.
//
// Desain:
//   - ActionDetector          : strategi deteksi 1 aksi (Strategy pattern).
//   - LivenessChallengeController: state machine yang mengonsumsi hasil deteksi
//     ML Kit per frame dan memajukan tantangan. UI-agnostic (emit via Stream).
//   - Clock & Random di-inject  -> logika bisa di-unit test tanpa timer nyata.
//
// Controller ini TIDAK memegang kamera / detektor. Pemanggil menjalankan
// FaceDetector pada frame kamera lalu meneruskan List<Face> ke onDetection().
//
// dependencies: google_mlkit_face_detection: ^0.13.1

import 'dart:async';
import 'dart:math';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// =============================================================================
// TIPE
// =============================================================================

enum LivenessAction { blink, turnLeft, turnRight, smile }

enum LivenessStatus { idle, running, passed, failed }

enum LivenessFailure { none, timeout, faceLost, multipleFaces, cancelled }

extension LivenessActionInstruction on LivenessAction {
  String get instruction {
    switch (this) {
      case LivenessAction.blink:
        return 'Kedipkan mata';
      case LivenessAction.turnLeft:
        return 'Tengok perlahan ke kiri';
      case LivenessAction.turnRight:
        return 'Tengok perlahan ke kanan';
      case LivenessAction.smile:
        return 'Tersenyum';
    }
  }
}

class LivenessState {
  final LivenessStatus status;
  final LivenessAction? currentAction;
  final String instruction;
  final int completed; // jumlah tantangan yang sudah lolos
  final int total;
  final LivenessFailure failure;

  const LivenessState({
    required this.status,
    required this.currentAction,
    required this.instruction,
    required this.completed,
    required this.total,
    this.failure = LivenessFailure.none,
  });

  double get progress => total == 0 ? 0 : completed / total;
  bool get isDone =>
      status == LivenessStatus.passed || status == LivenessStatus.failed;

  static const idle = LivenessState(
    status: LivenessStatus.idle,
    currentAction: null,
    instruction: '',
    completed: 0,
    total: 0,
  );
}

// =============================================================================
// STRATEGI DETEKSI AKSI
// =============================================================================

abstract class ActionDetector {
  LivenessAction get action;

  /// Dipanggil per frame dengan satu wajah valid. True saat aksi tuntas.
  /// Harus stateful (mis. kedip = terbuka -> tertutup -> terbuka).
  bool update(Face face);

  void reset();
}

/// Kedip = mata terbuka, lalu tertutup, lalu terbuka lagi.
class BlinkActionDetector implements ActionDetector {
  final double openThreshold;
  final double closedThreshold;
  bool _sawOpen = false;
  bool _sawClosed = false;

  BlinkActionDetector({this.openThreshold = 0.6, this.closedThreshold = 0.25});

  @override
  LivenessAction get action => LivenessAction.blink;

  @override
  bool update(Face face) {
    final l = face.leftEyeOpenProbability;
    final r = face.rightEyeOpenProbability;
    if (l == null || r == null) return false; // butuh enableClassification
    final open = (l + r) / 2;

    if (!_sawOpen) {
      if (open > openThreshold) _sawOpen = true;
      return false;
    }
    if (!_sawClosed) {
      if (open < closedThreshold) _sawClosed = true;
      return false;
    }
    return open > openThreshold; // terbuka kembali -> kedip tuntas
  }

  @override
  void reset() {
    _sawOpen = false;
    _sawClosed = false;
  }
}

/// Tengok kepala berdasarkan yaw (headEulerAngleY).
///
/// PENTING: tanda yaw pada kamera DEPAN sering ter-mirror antar device.
/// Kalibrasi di perangkat target; gunakan [mirror] untuk membalik bila perlu.
class HeadTurnActionDetector implements ActionDetector {
  final bool toLeft;
  final double yawThresholdDeg;
  final bool mirror;

  HeadTurnActionDetector({
    required this.toLeft,
    this.yawThresholdDeg = 20,
    this.mirror = false,
  });

  @override
  LivenessAction get action =>
      toLeft ? LivenessAction.turnLeft : LivenessAction.turnRight;

  @override
  bool update(Face face) {
    var yaw = face.headEulerAngleY;
    if (yaw == null) return false;
    if (mirror) yaw = -yaw;
    return toLeft ? yaw > yawThresholdDeg : yaw < -yawThresholdDeg;
  }

  @override
  void reset() {}
}

class SmileActionDetector implements ActionDetector {
  final double threshold;
  SmileActionDetector({this.threshold = 0.7});

  @override
  LivenessAction get action => LivenessAction.smile;

  @override
  bool update(Face face) {
    final s = face.smilingProbability;
    return s != null && s > threshold; // butuh enableClassification
  }

  @override
  void reset() {}
}

// =============================================================================
// CONTROLLER (state machine)
// =============================================================================

class LivenessChallengeController {
  final int challengeCount;
  final Duration perChallengeTimeout;

  /// Toleransi wajah hilang sesaat (flicker) sebelum dianggap gagal.
  final Duration faceLostGrace;

  final bool mirrorFrontCamera;
  final DateTime Function() _now;
  final Random _random;

  /// Untuk test: paksa urutan aksi tertentu (lewati pengacakan).
  final List<LivenessAction>? overrideSequence;

  final _controller = StreamController<LivenessState>.broadcast();

  List<ActionDetector> _sequence = [];
  int _index = 0;
  DateTime _challengeStart = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _faceLostSince;
  LivenessState _state = LivenessState.idle;

  LivenessChallengeController({
    this.challengeCount = 3,
    this.perChallengeTimeout = const Duration(seconds: 10),
    this.faceLostGrace = const Duration(milliseconds: 800),
    this.mirrorFrontCamera = false,
    DateTime Function()? clock,
    Random? random,
    this.overrideSequence,
  })  : _now = clock ?? DateTime.now,
        _random = random ?? Random();

  Stream<LivenessState> get states => _controller.stream;
  LivenessState get state => _state;

  /// Urutan aksi yang diminta pada sesi berjalan, mis. ["blink","smile"].
  ///
  /// Dilampirkan ke server sebagai bukti absensi. Karena urutannya diacak tiap
  /// sesi, urutan yang selalu identik antar-absensi menjadi sinyal bahwa
  /// prosesnya tidak benar-benar dijalankan (rekaman diputar ulang atau nilai
  /// tetap hasil modifikasi aplikasi).
  List<String> get sequenceNames =>
      _sequence.map((d) => d.action.name).toList(growable: false);

  /// Mulai sesi baru: bangun urutan acak, mulai tantangan pertama.
  void start() {
    _sequence = _buildSequence();
    _index = 0;
    _challengeStart = _now();
    _faceLostSince = null;
    _emitRunning();
  }

  /// Umpankan hasil deteksi ML Kit dari satu frame kamera.
  void onDetection(List<Face> faces) {
    if (_state.status != LivenessStatus.running) return;

    final now = _now();
    if (now.difference(_challengeStart) > perChallengeTimeout) {
      _fail(LivenessFailure.timeout);
      return;
    }
    if (faces.length > 1) {
      _fail(LivenessFailure.multipleFaces);
      return;
    }
    if (faces.isEmpty) {
      _faceLostSince ??= now;
      if (now.difference(_faceLostSince!) > faceLostGrace) {
        _fail(LivenessFailure.faceLost);
      }
      return;
    }
    _faceLostSince = null;

    if (_sequence[_index].update(faces.first)) {
      _advance();
    }
  }

  void cancel() {
    if (_state.status == LivenessStatus.running) {
      _fail(LivenessFailure.cancelled);
    }
  }

  void dispose() => _controller.close();

  // --------------------------------------------------------------------------
  List<ActionDetector> _buildSequence() {
    final actions = overrideSequence ?? _randomActions(challengeCount);
    return actions.map(_detectorFor).toList();
  }

  List<LivenessAction> _randomActions(int n) {
    const pool = LivenessAction.values;
    final result = <LivenessAction>[];
    LivenessAction? last;
    for (var i = 0; i < n; i++) {
      LivenessAction pick;
      do {
        pick = pool[_random.nextInt(pool.length)];
      } while (pick == last && pool.length > 1); // hindari repeat beruntun
      result.add(pick);
      last = pick;
    }
    return result;
  }

  ActionDetector _detectorFor(LivenessAction a) {
    switch (a) {
      case LivenessAction.blink:
        return BlinkActionDetector();
      case LivenessAction.turnLeft:
        return HeadTurnActionDetector(toLeft: true, mirror: mirrorFrontCamera);
      case LivenessAction.turnRight:
        return HeadTurnActionDetector(toLeft: false, mirror: mirrorFrontCamera);
      case LivenessAction.smile:
        return SmileActionDetector();
    }
  }

  void _advance() {
    _index++;
    if (_index >= _sequence.length) {
      _state = LivenessState(
        status: LivenessStatus.passed,
        currentAction: null,
        instruction: 'Verifikasi liveness berhasil',
        completed: _sequence.length,
        total: _sequence.length,
      );
      _controller.add(_state);
      return;
    }
    _sequence[_index].reset();
    _challengeStart = _now();
    _faceLostSince = null;
    _emitRunning();
  }

  void _emitRunning() {
    final action = _sequence[_index].action;
    _state = LivenessState(
      status: LivenessStatus.running,
      currentAction: action,
      instruction: action.instruction,
      completed: _index,
      total: _sequence.length,
    );
    _controller.add(_state);
  }

  void _fail(LivenessFailure reason) {
    _state = LivenessState(
      status: LivenessStatus.failed,
      currentAction: _state.currentAction,
      instruction: _messageFor(reason),
      completed: _index,
      total: _sequence.length,
      failure: reason,
    );
    _controller.add(_state);
  }

  String _messageFor(LivenessFailure reason) {
    switch (reason) {
      case LivenessFailure.timeout:
        return 'Waktu habis. Ulangi verifikasi.';
      case LivenessFailure.faceLost:
        return 'Wajah keluar dari bingkai. Ulangi verifikasi.';
      case LivenessFailure.multipleFaces:
        return 'Terdeteksi lebih dari satu wajah. Pastikan hanya kamu di kamera.';
      case LivenessFailure.cancelled:
        return 'Verifikasi dibatalkan.';
      case LivenessFailure.none:
        return '';
    }
  }

  /// Konfigurasi FaceDetector yang disarankan untuk stream kamera.
  /// (classification WAJIB untuk kedip & senyum; fast untuk realtime.)
  static FaceDetectorOptions recommendedStreamOptions() => FaceDetectorOptions(
        enableClassification: true, // eye-open & smiling probability
        enableTracking: true, // stabil antar frame + euler angle
        enableLandmarks: false,
        enableContours: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      );
}
