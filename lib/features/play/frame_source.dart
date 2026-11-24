/// Nguồn hình cho màn chơi: camera thật, hoặc bàn cờ mô phỏng (máy ảo, máy không có camera).
/// Cả hai đưa ra ảnh RGB nhỏ (cạnh dài ~480 điểm) đã xoay đúng chiều đang hiển thị.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/chess/position.dart';
import '../../core/vision/board.dart';
import '../../core/vision/image.dart';
import '../../core/vision/synth.dart';

abstract class FrameSource {
  /// Khoá để nhớ vị trí bàn cờ riêng cho từng nguồn.
  String get id;
  Stream<RgbImage> get frames;
  Future<void> start();
  Future<void> dispose();

  /// Hình đang thấy, phủ kín khung có cùng tỉ lệ với ảnh phân tích.
  Widget preview();
}

class CameraUnavailable implements Exception {
  CameraUnavailable(this.denied);
  final bool denied;
}

class CameraSource extends FrameSource {
  CameraSource({required this.portrait});

  /// Màn hình đang dọc không (khung camera của cảm biến thường nằm ngang, phải xoay cho khớp hình hiển thị).
  final bool Function() portrait;
  CameraController? _ctl;
  final _out = StreamController<RgbImage>.broadcast();
  DateTime _last = DateTime(2000);
  int _turns = 0;

  @override
  String get id => 'camera';
  @override
  Stream<RgbImage> get frames => _out.stream;

  @override
  Future<void> start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraUnavailable(false);
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final ctl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      await ctl.initialize();
      _turns = back.sensorOrientation ~/ 90;
      _ctl = ctl;
      await ctl.startImageStream(_onImage);
    } on CameraException catch (e) {
      final code = e.code.toLowerCase();
      throw CameraUnavailable(code.contains('denied') || code.contains('restricted') || code.contains('permission'));
    }
  }

  void _onImage(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds < 110 || _out.isClosed) return;
    _last = now;
    final turns = image.width > image.height && portrait() ? _turns : 0;
    final p = image.planes;
    final img = image.format.group == ImageFormatGroup.bgra8888
        ? RgbImage.fromBgra(p[0].bytes, image.width, image.height, p[0].bytesPerRow, maxSide: 720, quarterTurns: turns)
        : RgbImage.fromYuv(p[0].bytes, p[1].bytes, p[2].bytes, image.width, image.height, p[0].bytesPerRow, p[1].bytesPerRow, p[1].bytesPerPixel ?? 1,
            maxSide: 720, quarterTurns: turns);
    _out.add(img);
  }

  @override
  Widget preview() {
    final c = _ctl;
    if (c == null || !c.value.isInitialized) return const ColoredBox(color: Colors.black);
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: c.value.previewSize?.height ?? 300, height: c.value.previewSize?.width ?? 400, child: CameraPreview(c)),
    );
  }

  @override
  Future<void> dispose() async {
    final c = _ctl;
    _ctl = null;
    await _out.close();
    try {
      await c?.stopImageStream();
    } catch (_) {}
    await c?.dispose();
  }
}

Future<RgbImage> _renderInIsolate(List<int> board, SynthScene sc, int seed, Pt? hand) =>
    Isolate.run(() => renderBoard(board, sc, seed: seed, hand: hand));

/// Bàn cờ "thật" vẽ giả lập: người dùng đi quân trên bàn này (chạm bàn nhỏ), app nhận ra nước đi qua đúng đường
/// nhận dạng ảnh như với camera thật.
class SimSource extends FrameSource {
  SimSource(Position start) : real = Position.fromFen(start.fen);

  /// Thế cờ trên bàn "thật".
  Position real;
  final scene = const SynthScene();
  final _out = StreamController<RgbImage>.broadcast();
  final image = ValueNotifier<ui.Image?>(null);
  RgbImage? _img;
  Timer? _tick;
  int _seed = 1;
  int _gen = 0;

  @override
  String get id => 'sim';
  @override
  Stream<RgbImage> get frames => _out.stream;

  @override
  Future<void> start() async {
    await _render();
    _tick = Timer.periodic(const Duration(milliseconds: 150), (_) {
      final i = _img;
      if (i != null && !_out.isClosed) _out.add(i);
    });
  }

  Future<void> _render({Pt? hand}) async {
    final gen = ++_gen;
    final board = List<int>.of(real.board), sc = scene, seed = _seed++;
    final img = await _renderInIsolate(board, sc, seed, hand);
    if (gen != _gen) return;
    _img = img;
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(img.toRgba(), img.width, img.height, ui.PixelFormat.rgba8888, c.complete);
    final old = image.value;
    image.value = await c.future;
    old?.dispose();
  }

  /// Đi nước [m] trên bàn "thật": tay đưa vào che bàn một lúc rồi rút ra.
  Future<void> play(int m) async {
    final (c, r) = cellOfSquare(mFrom(m), scene.rot);
    await _render(hand: Pt(c + 0.5, r + 0.5));
    await Future<void>.delayed(const Duration(milliseconds: 450));
    real.make(m);
    await _render();
  }

  /// Đặt bàn "thật" về thế [p] (khi lùi nước, nhập tay).
  Future<void> setPosition(Position p) async {
    real = Position.fromFen(p.fen);
    await _render();
  }

  @override
  Widget preview() => ValueListenableBuilder<ui.Image?>(
        valueListenable: image,
        builder: (_, img, _) => img == null ? const ColoredBox(color: Colors.black) : RawImage(image: img, fit: BoxFit.fill),
      );

  @override
  Future<void> dispose() async {
    _tick?.cancel();
    await _out.close();
  }
}

/// Ảnh tĩnh của bàn cờ (chọn từ thư viện hoặc chụp): để thử nhận dạng trên bàn thật mà không cần gắn máy cố định.
/// Mỗi nước đi thì đưa vào một ảnh mới; ảnh đang có được phát lặp lại như một camera đứng yên.
class PhotoSource extends FrameSource {
  final _out = StreamController<RgbImage>.broadcast();
  final image = ValueNotifier<ui.Image?>(null);
  RgbImage? _img;
  Timer? _tick;

  @override
  String get id => 'photo';
  @override
  Stream<RgbImage> get frames => _out.stream;
  RgbImage? get current => _img;

  @override
  Future<void> start() async {
    _tick = Timer.periodic(const Duration(milliseconds: 150), (_) {
      final i = _img;
      if (i != null && !_out.isClosed) _out.add(i);
    });
  }

  /// Giải mã tệp ảnh (JPEG, PNG, HEIC… theo bộ giải mã của hệ điều hành, đã xoay đúng chiều) thành ảnh hiển thị và
  /// ảnh phân tích (cạnh dài 500–1000 điểm).
  static Future<(ui.Image, RgbImage)> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: null);
    final frame = await codec.getNextFrame();
    final im = frame.image;
    final data = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (im, RgbImage.fromRgba(data!.buffer.asUint8List(), im.width, im.height, maxSide: 1000));
  }

  void show(ui.Image display, RgbImage analysis) {
    final old = image.value;
    image.value = display;
    _img = analysis;
    old?.dispose();
  }

  @override
  Widget preview() => ValueListenableBuilder<ui.Image?>(
        valueListenable: image,
        builder: (_, img, _) => img == null ? const ColoredBox(color: Colors.black) : RawImage(image: img, fit: BoxFit.fill),
      );

  @override
  Future<void> dispose() async {
    _tick?.cancel();
    await _out.close();
  }
}
