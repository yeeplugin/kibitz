/// Dựng ảnh "chụp" một bàn cờ thật: nhìn nghiêng, quân có chiều cao (đầu quân lấn sang ô phía sau), ánh sáng không đều,
/// nhiễu. Dùng cho unit test nhận dạng và cho chế độ mô phỏng khi máy không có camera (máy ảo iOS).
library;

import 'dart:math' as math;

import '../chess/position.dart';
import 'board.dart';
import 'classifier.dart' show pieceHeight, pieceRadius;
import 'image.dart';
import 'pose.dart';

class SynthScene {
  const SynthScene({
    this.width = 360,
    this.height = 480,
    this.corners = const [Pt(62, 120), Pt(298, 120), Pt(340, 400), Pt(20, 400)],
    this.rot = 0,
    this.light = const [238, 216, 180],
    this.dark = const [176, 124, 82],
    this.noise = 6,
    this.height3d = 1.0,
  });
  final int width, height;
  final List<Pt> corners;
  final int rot;
  final List<int> light, dark;
  final double noise;

  /// Độ cao quân (0 = nhìn thẳng từ trên xuống, quân không lấn ô).
  final double height3d;

  SynthScene copyWith({List<Pt>? corners, int? rot, double? noise, List<int>? light, List<int>? dark}) => SynthScene(
        width: width,
        height: height,
        corners: corners ?? this.corners,
        rot: rot ?? this.rot,
        light: light ?? this.light,
        dark: dark ?? this.dark,
        noise: noise ?? this.noise,
        height3d: height3d,
      );
}

/// Vẽ bàn cờ [board] (64 quân, a1 = 0). [hand] là tâm một bàn tay che bàn (toạ độ lưới), nếu có.
/// Quân là khối trụ thon đứng trên ô (cùng kích thước với mô hình của bộ nhận dạng), chiếu theo đúng vị trí camera
/// suy ra từ bốn góc bàn: quân phía trước che quân và ô phía sau như ảnh chụp thật.
RgbImage renderBoard(List<int> board, SynthScene s, {int seed = 1, Pt? hand}) {
  final img = RgbImage(s.width, s.height);
  final grid = BoardGrid(s.corners);
  final pose = BoardPose(grid, s.width, s.height);
  final inv = homography(s.corners, gridPts)!;
  final rnd = math.Random(seed);
  final d = img.data;
  final cell = <int>[0, 0, 0];
  // Quân theo ô lưới.
  final cells = List<int>.generate(64, (i) => board[squareOfCell(i % 8, i ~/ 8, s.rot)]);
  // Tia nhìn lùi về phía camera dài tối đa bao nhiêu ô (trên mặt bàn) khi lên tới độ cao của quân cao nhất.
  for (var y = 0; y < s.height; y++) {
    for (var x = 0; x < s.width; x++) {
      final g = project(inv, x + 0.5, y + 0.5);
      _shade(cells, s, pose, g.x, g.y, cell, hand);
      // Ánh sáng đèn từ góc trên trái.
      final lightK = 1.08 - 0.22 * (x / s.width * 0.4 + y / s.height * 0.6);
      final o = (y * s.width + x) * 3;
      for (var ch = 0; ch < 3; ch++) {
        final n = s.noise == 0 ? 0 : (rnd.nextDouble() + rnd.nextDouble() - 1) * s.noise * 1.7;
        d[o + ch] = (cell[ch] * lightK + n).round().clamp(0, 255);
      }
    }
  }
  return img;
}

void _set(List<int> out, num r, num g, num b) {
  out[0] = r.round();
  out[1] = g.round();
  out[2] = b.round();
}

void _shade(List<int> cells, SynthScene s, BoardPose pose, double u, double v, List<int> out, Pt? hand) {
  if (hand != null) {
    final dx = (u - hand.x) / 1.6, dy = (v - hand.y) / 2.4;
    if (dx * dx + dy * dy < 1 || (v > hand.y && (u - hand.x).abs() < 0.9)) return _set(out, 214, 160, 128);
  }
  // Tia nhìn qua điểm mặt bàn (u, v): ở độ cao z nó nằm trên (u, v) + k·z.
  final top = pose.ground(u, v, 0, 1.8 * s.height3d);
  final minX = math.min(u, top.x) - 0.31, maxX = math.max(u, top.x) + 0.31;
  final minY = math.min(v, top.y) - 0.31, maxY = math.max(v, top.y) + 0.31;
  var bestZ = -1.0, bestD = 0.0, bestRel = 0.0, bestPiece = 0;
  for (var r = math.max(0, (minY - 0.5).ceil()); r <= math.min(7, (maxY - 0.5).floor()); r++) {
    for (var c = math.max(0, (minX - 0.5).ceil()); c <= math.min(7, (maxX - 0.5).floor()); c++) {
      final p = cells[r * 8 + c];
      if (p == 0) continue;
      final h = pieceHeight[typeOf(p)] * s.height3d;
      // Từ đỉnh quân xuống: điểm cao nhất tia chạm vào thân quân là điểm nhìn thấy.
      for (var z = h; z >= 0; z -= 0.04) {
        if (z <= bestZ) break;
        final g = pose.ground(u, v, 0, z);
        final dd = math.sqrt((g.x - c - 0.5) * (g.x - c - 0.5) + (g.y - r - 0.5) * (g.y - r - 0.5));
        final rel = h <= 0 ? 0.0 : z / h;
        if (dd <= pieceRadius(rel)) {
          bestZ = z;
          bestD = dd / pieceRadius(rel);
          bestRel = rel;
          bestPiece = p;
          break;
        }
      }
    }
  }
  if (bestPiece != 0) {
    final w = colorOf(bestPiece) == white;
    // Viền tối quanh thân, thân sáng dần vào giữa, đầu quân sáng hơn.
    if (bestD > 0.86) return w ? _set(out, 120, 104, 84) : _set(out, 96, 88, 80);
    final k = (1 - 0.22 * bestD * bestD) * (bestRel > 0.8 ? 1.04 : 1.0);
    return w ? _set(out, 236 * k, 224 * k, 200 * k) : _set(out, 44 * k, 38 * k, 34 * k);
  }
  if (u < -0.7 || v < -0.7 || u > 8.7 || v > 8.7) return _set(out, 92, 96, 104); // mặt bàn
  if (u < 0 || v < 0 || u >= 8 || v >= 8) return _set(out, 112, 72, 42); // viền gỗ
  final c0 = u.floor(), r0 = v.floor();
  final sq = squareOfCell(c0, r0, s.rot);
  final lightSq = (fileOf(sq) + rankOf(sq)).isOdd;
  final col = lightSq ? s.light : s.dark;
  _set(out, col[0], col[1], col[2]);
}
