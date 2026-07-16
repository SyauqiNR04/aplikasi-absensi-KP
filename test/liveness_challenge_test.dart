// liveness_challenge_test.dart
//
// flutter test
// GANTI `your_app` dengan nama package di pubspec.yaml.

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_application_1/services/liveness_challenge.dart';

class MockFace extends Mock implements Face {}

/// Bangun Face palsu dengan atribut yang dibutuhkan detektor.
Face _face({
  double? leftEye,
  double? rightEye,
  double? smile,
  double? yaw,
}) {
  final f = MockFace();
  when(() => f.leftEyeOpenProbability).thenReturn(leftEye);
  when(() => f.rightEyeOpenProbability).thenReturn(rightEye);
  when(() => f.smilingProbability).thenReturn(smile);
  when(() => f.headEulerAngleY).thenReturn(yaw);
  return f;
}

/// Clock yang bisa dimajukan manual.
class FakeClock {
  DateTime t = DateTime(2025, 1, 1, 12, 0, 0);
  DateTime now() => t;
  void advance(Duration d) => t = t.add(d);
}

void main() {
  // ===========================================================================
  group('ActionDetector', () {
    test('Blink: butuh terbuka -> tertutup -> terbuka', () {
      final d = BlinkActionDetector();
      expect(d.update(_face(leftEye: 0.9, rightEye: 0.9)), isFalse); // terbuka
      expect(d.update(_face(leftEye: 0.1, rightEye: 0.1)), isFalse); // tertutup
      expect(d.update(_face(leftEye: 0.9, rightEye: 0.9)), isTrue); // terbuka lagi
    });

    test('Blink: mata terbuka terus tidak lolos', () {
      final d = BlinkActionDetector();
      for (var i = 0; i < 5; i++) {
        expect(d.update(_face(leftEye: 0.9, rightEye: 0.9)), isFalse);
      }
    });

    test('Smile: di atas threshold lolos', () {
      final d = SmileActionDetector(threshold: 0.7);
      expect(d.update(_face(smile: 0.3)), isFalse);
      expect(d.update(_face(smile: 0.85)), isTrue);
    });

    test('HeadTurn kiri: yaw melebihi threshold positif', () {
      final d = HeadTurnActionDetector(toLeft: true, yawThresholdDeg: 20);
      expect(d.update(_face(yaw: 5)), isFalse);
      expect(d.update(_face(yaw: 25)), isTrue);
    });

    test('HeadTurn mirror membalik tanda yaw', () {
      final d = HeadTurnActionDetector(
          toLeft: true, yawThresholdDeg: 20, mirror: true);
      expect(d.update(_face(yaw: -25)), isTrue);
    });
  });

  // ===========================================================================
  group('LivenessChallengeController', () {
    late FakeClock clock;

    LivenessChallengeController build(List<LivenessAction> seq) =>
        LivenessChallengeController(
          clock: clock.now,
          overrideSequence: seq,
          perChallengeTimeout: const Duration(seconds: 10),
          faceLostGrace: const Duration(milliseconds: 800),
        );

    setUp(() => clock = FakeClock());

    test('urutan penuh sukses -> passed', () {
      final c = build([LivenessAction.smile, LivenessAction.blink]);
      c.start();
      expect(c.state.currentAction, LivenessAction.smile);

      c.onDetection([_face(smile: 0.9)]); // tantangan 1 selesai
      expect(c.state.currentAction, LivenessAction.blink);
      expect(c.state.completed, 1);

      c.onDetection([_face(leftEye: 0.9, rightEye: 0.9)]);
      c.onDetection([_face(leftEye: 0.1, rightEye: 0.1)]);
      c.onDetection([_face(leftEye: 0.9, rightEye: 0.9)]);

      expect(c.state.status, LivenessStatus.passed);
      expect(c.state.progress, 1.0);
      c.dispose();
    });

    test('timeout per tantangan -> failed timeout', () {
      final c = build([LivenessAction.smile]);
      c.start();
      clock.advance(const Duration(seconds: 11));
      c.onDetection([_face(smile: 0.9)]);
      expect(c.state.status, LivenessStatus.failed);
      expect(c.state.failure, LivenessFailure.timeout);
      c.dispose();
    });

    test('lebih dari satu wajah -> failed multipleFaces', () {
      final c = build([LivenessAction.smile]);
      c.start();
      c.onDetection([_face(smile: 0.9), _face(smile: 0.2)]);
      expect(c.state.failure, LivenessFailure.multipleFaces);
      c.dispose();
    });

    test('wajah hilang melewati grace -> failed faceLost', () {
      final c = build([LivenessAction.smile]);
      c.start();
      c.onDetection([]); // mulai hitung grace
      clock.advance(const Duration(seconds: 1)); // > 800ms
      c.onDetection([]);
      expect(c.state.failure, LivenessFailure.faceLost);
      c.dispose();
    });

    test('flicker wajah singkat tidak menggagalkan', () {
      final c = build([LivenessAction.smile]);
      c.start();
      c.onDetection([]); // hilang sesaat
      clock.advance(const Duration(milliseconds: 200));
      c.onDetection([_face(smile: 0.9)]); // muncul lagi & selesai
      expect(c.state.status, LivenessStatus.passed);
      c.dispose();
    });

    test('cancel -> failed cancelled', () {
      final c = build([LivenessAction.smile]);
      c.start();
      c.cancel();
      expect(c.state.failure, LivenessFailure.cancelled);
      c.dispose();
    });

    test('stream memancarkan perubahan state', () async {
      final c = build([LivenessAction.smile]);
      final emitted = <LivenessStatus>[];
      final sub = c.states.listen((s) => emitted.add(s.status));
      c.start();
      c.onDetection([_face(smile: 0.9)]);
      await Future<void>.delayed(Duration.zero);
      expect(emitted, containsAllInOrder(
          [LivenessStatus.running, LivenessStatus.passed]));
      await sub.cancel();
      c.dispose();
    });
  });
}
