import 'dart:io';

import 'package:chess_coach/core/chess/engine.dart';
import 'package:chess_coach/core/chess/position.dart';
import 'package:chess_coach/core/vision/board.dart';
import 'package:chess_coach/core/vision/classifier.dart';
import 'package:chess_coach/core/vision/image.dart';
import 'package:chess_coach/core/vision/pose.dart';
import 'package:chess_coach/core/vision/synth.dart';
import 'package:chess_coach/core/vision/tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

void save(RgbImage img, String name) {
  final dir = Platform.environment['SHOTS'];
  if (dir == null) return;
  final o = im.Image.fromBytes(width: img.width, height: img.height, bytes: img.data.buffer, numChannels: 3);
  File('$dir/$name.png').writeAsBytesSync(im.encodePng(o));
}

List<int> boardOf(Position p) => List.of(p.board);

void main() {
  const scene = SynthScene();

  // Bàn chiếm cỡ 240–330 điểm ảnh (ô cờ 30–40 điểm): góc tìm được lệch không quá 1/3 ô; người dùng kéo góc để chỉnh.
  for (final (k, s) in [
    scene,
    const SynthScene(corners: [Pt(40, 140), Pt(300, 100), Pt(350, 380), Pt(30, 430)]),
    const SynthScene(corners: [Pt(90, 150), Pt(270, 150), Pt(300, 350), Pt(60, 350)]),
  ].indexed) {
    test('tự tìm bàn cờ trong ảnh thế khởi đầu (khung $k)', () {
      final img = renderBoard(boardOf(Position.start()), s);
      if (k == 0) save(img, 'start');
      final g = findBoard(img);
      expect(g, isNotNull);
      for (var i = 0; i < 4; i++) {
        expect(g!.corners[i].dist(s.corners[i]), lessThan(13), reason: 'góc $i: ${g.corners[i]} ≠ ${s.corners[i]}');
      }
    });
  }

  test('đọc đúng 64 ô với lưới tự tìm (chưa chỉnh tay)', () {
    final board = boardOf(Position.start());
    final img = renderBoard(board, scene);
    final g = findBoard(img)!;
    final rot = guessRotation(img, g, board);
    expect(rot, 0);
    final cl = SquareClassifier.calibrate(img, g, rot, board)!;
    final obs = cl.observe(renderBoard(board, scene, seed: 42))..setBase(board);
    expect(obs.odd().map(sqName), isEmpty);
  });

  for (final rot in [0, 1, 2, 3]) {
    test('đoán hướng bàn (xoay $rot) và đọc đúng 64 ô', () {
      final s = scene.copyWith(rot: rot);
      final board = boardOf(Position.start());
      final img = renderBoard(board, s, seed: 3 + rot);
      final g = BoardGrid(s.corners);
      expect(guessRotation(img, g, board), rot);
      final cl = SquareClassifier.calibrate(img, g, rot, board)!;
      final obs = cl.observe(renderBoard(board, s, seed: 99))..setBase(board);
      expect(obs.odd().map(sqName), isEmpty);
    });
  }

  /// Đi lần lượt [ucis] trên bàn "thật" từ [fen], mỗi nước có một khung tay che; bộ theo dõi phải nhận đúng từng nước.
  void play(String fen, List<String> ucis, {SynthScene sc = scene, String tag = ''}) {
    final real = Position.fromFen(fen);
    final g = BoardGrid(sc.corners);
    final cl = SquareClassifier.calibrate(renderBoard(boardOf(real), sc), g, sc.rot, boardOf(real))!;
    final tr = Tracker(Position.fromFen(fen));
    var seed = 10;
    for (final u in ucis) {
      final m = real.parseUci(u);
      expect(m, isNotNull, reason: 'nước không hợp lệ trong test: $u');
      final (fc, fr) = cellOfSquare(mFrom(m!), sc.rot);
      final hand = renderBoard(boardOf(real), sc, seed: seed++, hand: Pt(fc + 0.5, fr + 0.5));
      if (tag.isNotEmpty && seed == 14) save(hand, '$tag-hand');
      final hu = tr.update(cl.observe(hand));
      expect(hu.state, isNot(TrackState.moved), reason: 'tay che lúc $u');
      real.make(m);
      TrackUpdate? last;
      for (var f = 0; f < 4 && last?.state != TrackState.moved; f++) {
        final img = renderBoard(boardOf(real), sc, seed: seed++);
        last = tr.update(cl.observe(img));
        if (last.state == TrackState.stable) cl.adapt(img, boardOf(real));
      }
      expect(last!.state, TrackState.moved, reason: 'không nhận ra $u (lệch ${last.mismatch.map(sqName)})');
      expect(last.moves.map(uci).toList(), [u]);
      // Bàn đứng yên sau nước đi: học lại màu ô vừa trống.
      final still = renderBoard(boardOf(real), sc, seed: seed++);
      final su = tr.update(cl.observe(still));
      expect(su.state, TrackState.stable, reason: 'sau $u (lệch ${su.mismatch.map(sqName)})');
      cl.adapt(still, boardOf(real));
    }
    if (tag.isNotEmpty) save(renderBoard(boardOf(real), sc), '$tag-end');
    expect(tr.pos.fen, real.fen);
  }

  test('theo dõi một ván 50 nước do engine tự đánh, có tay che', () {
    final p = Position.start();
    final ucis = <String>[];
    for (var i = 0; i < 50 && p.legalMoves().isNotEmpty; i++) {
      final a = analyzeSync(p.fen, [], ms: 5000, maxDepth: 2);
      ucis.add(a.best);
      p.make(p.parseUci(a.best)!);
    }
    play(startFen, ucis, tag: 'game');
  });

  test('nhập thành hai cánh, bắt tốt qua đường, phong cấp', () {
    play('r3k2r/pppq1ppp/2n5/3pP3/8/8/PPPQ1PPP/R3K2R w KQkq d6 0 10', ['e5d6', 'e8c8', 'e1g1', 'c8b8', 'd6c7', 'b8a8', 'c7d8q', 'h8d8']);
  });

  test('bàn xoay ngang (camera ở cạnh bàn)', () {
    play(startFen, ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5', 'a7a6', 'b5c6', 'd7c6', 'e1g1'], sc: scene.copyWith(rot: 1), tag: 'rot1');
  });

  test('camera thấp, nhìn chéo từ góc bàn (quân che nhau nhiều)', () {
    // Góc nâng chừng 40°, bàn xoay chéo như ảnh chụp cầm tay.
    const low = SynthScene(width: 480, height: 400, corners: [Pt(250, 70), Pt(440, 150), Pt(250, 330), Pt(40, 160)]);
    final pose = BoardPose(BoardGrid(low.corners), low.width, low.height);
    expect(pose.elevation, inInclusiveRange(25, 50));
    play(startFen, ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5', 'c2c3', 'g8f6', 'd2d4', 'e5d4', 'c3d4', 'c5b4', 'b1c3', 'f6e4', 'e1g1'], sc: low, tag: 'low');
  });

  test('tự tìm bàn khi bàn xoay chéo, camera thấp', () {
    const low = SynthScene(width: 480, height: 400, corners: [Pt(250, 70), Pt(440, 150), Pt(250, 330), Pt(40, 160)]);
    final img = renderBoard(boardOf(Position.start()), low);
    final g = findBoard(img);
    expect(g, isNotNull);
    // Góc nào của lưới tìm được cũng phải trùng một góc bàn thật.
    for (final c in g!.corners) {
      expect(low.corners.map((t) => t.dist(c)).reduce((a, b) => a < b ? a : b), lessThan(13), reason: '$c');
    }
  });

  test('bỏ lỡ một nước: nhận cả chuỗi hai nước', () {
    final real = Position.start();
    final g = BoardGrid(scene.corners);
    final cl = SquareClassifier.calibrate(renderBoard(boardOf(real), scene), g, 0, boardOf(real))!;
    final tr = Tracker(Position.start());
    real.make(real.parseUci('e2e4')!);
    real.make(real.parseUci('c7c5')!);
    TrackUpdate? last;
    for (var f = 0; f < 4 && last?.state != TrackState.moved; f++) {
      last = tr.update(cl.observe(renderBoard(boardOf(real), scene, seed: 50 + f)));
    }
    expect(last!.moves.map(uci).toList(), ['e2e4', 'c7c5']);
  });

  test('đặt sai quân: báo ô lệch, không nhận bừa', () {
    final real = Position.start();
    final g = BoardGrid(scene.corners);
    final cl = SquareClassifier.calibrate(renderBoard(boardOf(real), scene), g, 0, boardOf(real))!;
    final tr = Tracker(Position.start(), mismatchFrames: 4);
    final b = boardOf(real);
    b[sqOf(4, 3)] = b[sqOf(3, 1)]; // tốt d2 nhảy lên e4: không hợp lệ
    b[sqOf(3, 1)] = 0;
    TrackUpdate? last;
    for (var f = 0; f < 5; f++) {
      last = tr.update(cl.observe(renderBoard(b, scene, seed: 70 + f)));
      expect(last.state, isNot(TrackState.moved));
    }
    expect(last!.state, TrackState.mismatch);
    expect(last.mismatch, {sqOf(4, 3), sqOf(3, 1)});
  });
}
