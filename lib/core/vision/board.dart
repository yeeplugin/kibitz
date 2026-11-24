/// Lưới 8×8 của bàn cờ trong ảnh và cách tự tìm nó.
///
/// Toạ độ lưới (u, v) chạy 0…8: ô (c, r) là hình vuông [c, c+1] × [r, r+1]. Bốn góc lưới (0,0), (8,0), (8,8), (0,8)
/// ứng với bốn điểm [BoardGrid.corners] trong ảnh. Ô lưới nào là ô cờ nào thì do hướng [rot] quyết định.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../chess/position.dart';
import 'corners.dart';
import 'image.dart';

const gridPts = [Pt(0, 0), Pt(8, 0), Pt(8, 8), Pt(0, 8)];

class BoardGrid {
  BoardGrid(this.corners) : h = homography(gridPts, corners) ?? Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]);
  final List<Pt> corners;
  final Float64List h;

  Pt at(double u, double v) => project(h, u, v);
  Pt cellCenter(int c, int r) => at(c + 0.5, r + 0.5);

  BoardGrid moved(int i, Pt p) => BoardGrid([for (var k = 0; k < 4; k++) k == i ? p : corners[k]]);

  /// Bốn góc thành tứ giác lồi, đủ lớn.
  bool get valid {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4];
      final cr = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      final s = cr > 0 ? 1 : -1;
      if (cr.abs() < 1e-6) return false;
      if (sign == 0) sign = s;
      if (s != sign) return false;
    }
    return area > 400;
  }

  double get area {
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[(i + 1) % 4];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  List<double> toList() => [for (final c in corners) ...[c.x, c.y]];
  static BoardGrid fromList(List<dynamic> v) => BoardGrid([for (var i = 0; i < 4; i++) Pt((v[i * 2] as num).toDouble(), (v[i * 2 + 1] as num).toDouble())]);
}

/// Ô cờ ứng với ô lưới (c, r) khi bàn xoay [rot] lần 90°. rot = 0: bên trắng ở phía v = 8 (thường là phía dưới ảnh),
/// cột c = 0 là cột a.
int squareOfCell(int c, int r, int rot) {
  var cc = c, rr = r;
  for (var k = 0; k < (rot & 3); k++) {
    final t = cc;
    cc = 7 - rr;
    rr = t;
  }
  return sqOf(cc, 7 - rr);
}

/// Ngược lại của [squareOfCell]: ô lưới (c, r) chứa ô cờ [s].
(int, int) cellOfSquare(int s, int rot) {
  for (var r = 0; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      if (squareOfCell(c, r, rot) == s) return (c, r);
    }
  }
  return (0, 0);
}

/// Độ sáng tại (x, y), nội suy song tuyến; -1 nếu ngoài ảnh.
int _lumAt(RgbImage img, double x, double y) {
  final fx = x - 0.5, fy = y - 0.5;
  final x0 = fx.floor(), y0 = fy.floor();
  if (x0 < 0 || y0 < 0 || x0 >= img.width - 1 || y0 >= img.height - 1) return -1;
  final ax = fx - x0, ay = fy - y0;
  final a = img.lum(x0, y0), b = img.lum(x0 + 1, y0), c = img.lum(x0, y0 + 1), d = img.lum(x0 + 1, y0 + 1);
  return ((a + (b - a) * ax) * (1 - ay) + (c + (d - c) * ax) * ay).round();
}

/// Độ sáng trung bình vùng giữa ô (c, r) (chấp nhận c, r = -1 hoặc 8 cho dải viền ngoài).
double _cellMean(RgbImage img, BoardGrid g, int c, int r) {
  var s = 0, n = 0;
  for (final fv in const [0.3, 0.5, 0.7]) {
    for (final fu in const [0.3, 0.5, 0.7]) {
      final p = g.at(c + fu, r + fv);
      final v = _lumAt(img, p.x, p.y);
      if (v >= 0) {
        s += v;
        n++;
      }
    }
  }
  return n == 0 ? double.nan : s / n;
}

/// Trung bình. (Đã thử bỏ 30% giá trị nhỏ nhất cho đỡ ảnh hưởng của quân che: lưới lại dễ trượt lệch một hàng.)
double _trimmed(List<double> v) {
  if (v.isEmpty) return 0;
  return v.reduce((a, b) => a + b) / v.length;
}

/// Lưới khớp với ô bàn cờ trong ảnh tới đâu: độ tương phản sáng/tối xen kẽ giữa các ô và qua các đường kẻ,
/// trừ đi phần hoa văn ô cờ còn kéo dài ra ngoài lưới (dấu hiệu lưới bị lệch mất một hàng/cột).
double gridScore(RgbImage img, BoardGrid g) {
  if (!g.valid) return -1e9;
  var inner = 0.0;
  final m = List.generate(10, (_) => Float64List(10));
  for (var r = -1; r <= 8; r++) {
    for (var c = -1; c <= 8; c++) {
      m[r + 1][c + 1] = _cellMean(img, g, c, r);
    }
  }
  // Bàn bị cắt mất một phần khỏi ảnh: chấm theo các ô còn thấy, miễn là còn thấy phần lớn bàn.
  var seenEven = 0, seenOdd = 0;
  var sumEven = 0.0, sumOdd = 0.0;
  for (var r = 0; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      final v = m[r + 1][c + 1];
      if (v.isNaN) continue;
      if ((c + r).isEven) {
        sumEven += v;
        seenEven++;
      } else {
        sumOdd += v;
        seenOdd++;
      }
    }
  }
  if (seenEven < 20 || seenOdd < 20) return -1e9;
  inner = sumEven / seenEven - sumOdd / seenOdd;
  // Chênh sáng hai bên mỗi đoạn đường kẻ trong lưới.
  final gradV = <double>[];
  for (var k = 1; k < 8; k++) {
    for (var j = 0; j < 8; j++) {
      final par = (k + j).isEven ? 1 : -1;
      for (final t in const [0.3, 0.7]) {
        final a = g.at(k + 0.12, j + t), b = g.at(k - 0.12, j + t);
        final va = _lumAt(img, a.x, a.y), vb = _lumAt(img, b.x, b.y);
        if (va >= 0 && vb >= 0) gradV.add(par * (va - vb).toDouble());
        final c2 = g.at(j + t, k + 0.12), d2 = g.at(j + t, k - 0.12);
        final vc = _lumAt(img, c2.x, c2.y), vd = _lumAt(img, d2.x, d2.y);
        if (vc >= 0 && vd >= 0) gradV.add(par * (vc - vd).toDouble());
      }
    }
  }
  final grad = _trimmed(gradV);
  // Các điểm giao bốn ô bên trong lưới (hình chữ X sáng/tối): quân tròn ít khi che tới góc ô, nên các điểm này
  // vẫn thấy được cả ở hàng có quân và giữ lưới đúng cỡ, đúng chỗ.
  final xcV = <double>[];
  const dl = 0.18;
  for (var i = 1; i < 8; i++) {
    for (var j = 1; j < 8; j++) {
      final p1 = g.at(i + dl, j + dl), p2 = g.at(i - dl, j - dl), p3 = g.at(i + dl, j - dl), p4 = g.at(i - dl, j + dl);
      final a = _lumAt(img, p1.x, p1.y), b = _lumAt(img, p2.x, p2.y), c = _lumAt(img, p3.x, p3.y), d = _lumAt(img, p4.x, p4.y);
      if (a < 0 || b < 0 || c < 0 || d < 0) continue;
      final v = (a + b - c - d) / 2;
      xcV.add((i + j).isEven ? v : -v);
    }
  }
  final xc = _trimmed(xcV);
  final base = (inner + grad + 2 * xc).abs() / 4;
  var outer = 0.0;
  for (final side in const [0, 1, 2, 3]) {
    var s = 0.0, cnt = 0;
    for (var i = 0; i < 8; i++) {
      final (c, r) = switch (side) { 0 => (i, -1), 1 => (i, 8), 2 => (-1, i), _ => (8, i) };
      final v = m[r + 1][c + 1];
      if (v.isNaN) continue;
      s += (c + r).isEven ? v : -v;
      cnt++;
    }
    if (cnt >= 6) outer += (s / cnt * 2).abs();
  }
  return base - 0.35 * outer;
}

/// Các phép biến đổi cả khung (dời, phóng, co một chiều, nghiêng phối cảnh) — giúp thoát khỏi chỗ khớp nửa vời
/// mà dời từng góc một không thoát được.
BoardGrid _globalMove(BoardGrid g, int kind, double step) {
  final c = g.corners;
  final cx = c.map((p) => p.x).reduce((a, b) => a + b) / 4, cy = c.map((p) => p.y).reduce((a, b) => a + b) / 4;
  final size = math.sqrt(g.area);
  final k = step / size;
  Pt f(int i, Pt p) => switch (kind) {
        0 => Pt(p.x + step, p.y),
        1 => Pt(p.x - step, p.y),
        2 => Pt(p.x, p.y + step),
        3 => Pt(p.x, p.y - step),
        4 => Pt(cx + (p.x - cx) * (1 + k), cy + (p.y - cy) * (1 + k)),
        5 => Pt(cx + (p.x - cx) * (1 - k), cy + (p.y - cy) * (1 - k)),
        6 => Pt(cx + (p.x - cx) * (1 + k), p.y),
        7 => Pt(cx + (p.x - cx) * (1 - k), p.y),
        8 => Pt(p.x, cy + (p.y - cy) * (1 + k)),
        9 => Pt(p.x, cy + (p.y - cy) * (1 - k)),
        // Cạnh trên hẹp lại / rộng ra (camera nghiêng nhiều / ít).
        10 => i < 2 ? Pt(cx + (p.x - cx) * (1 - k), p.y) : Pt(cx + (p.x - cx) * (1 + k), p.y),
        11 => i < 2 ? Pt(cx + (p.x - cx) * (1 + k), p.y) : Pt(cx + (p.x - cx) * (1 - k), p.y),
        // Xoay nhẹ.
        12 => Pt(cx + (p.x - cx) - (p.y - cy) * k, cy + (p.y - cy) + (p.x - cx) * k),
        _ => Pt(cx + (p.x - cx) + (p.y - cy) * k, cy + (p.y - cy) - (p.x - cx) * k),
      };
  return BoardGrid([for (var i = 0; i < 4; i++) f(i, c[i])]);
}

/// Tinh chỉnh bốn góc lưới để [gridScore] lớn nhất: dò cả khung rồi từng góc, bước nhỏ dần; cuối cùng thử dời
/// lưới đi đúng một ô theo mỗi hướng (lưới khớp lệch một hàng vẫn có hoa văn ô cờ gần như đủ).
BoardGrid refineGrid(RgbImage img, BoardGrid g, {double? startStep, double minStep = 0.5, bool shifts = true}) {
  var best = g;
  var bestScore = gridScore(img, g);
  var step = startStep ?? math.sqrt(g.area) / 20;
  while (step >= minStep) {
    var improved = true;
    var rounds = 0;
    while (improved && rounds++ < 20) {
      improved = false;
      for (var kind = 0; kind < 14; kind++) {
        final cand = _globalMove(best, kind, step);
        final s = gridScore(img, cand);
        if (s > bestScore + 1e-6) {
          best = cand;
          bestScore = s;
          improved = true;
        }
      }
      for (var i = 0; i < 4; i++) {
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final c = best.corners[i];
          final cand = best.moved(i, Pt(c.x + dx * step, c.y + dy * step));
          final s = gridScore(img, cand);
          if (s > bestScore + 1e-6) {
            best = cand;
            bestScore = s;
            improved = true;
          }
        }
      }
    }
    step /= 2;
  }
  if (shifts) {
    for (final (du, dv) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final sh = BoardGrid([best.at(du.toDouble(), dv.toDouble()), best.at(8.0 + du, dv.toDouble()), best.at(8.0 + du, 8.0 + dv), best.at(du.toDouble(), 8.0 + dv)]);
      if (!sh.valid) continue;
      final r = refineGrid(img, sh, startStep: 2, minStep: minStep, shifts: false);
      final s = gridScore(img, r);
      if (s > bestScore + 1e-6) {
        best = r;
        bestScore = s;
      }
    }
  }
  return best;
}

/// Tự tìm bàn cờ trong ảnh. Cách chính: dò các điểm giao bốn ô, ghép thành mạng lưới, rồi chọn chỗ đặt khung 8×8
/// trên mạng lưới sao cho hoa văn ô cờ khớp nhất. Không ghép được (ảnh mờ, bàn quá nhỏ) thì thử nhiều khung quanh
/// giữa ảnh như cách cũ. Trả về null nếu không thấy hoa văn ô cờ đủ rõ.
BoardGrid? findBoard(RgbImage img, {double minContrast = 18}) => _findByCorners(img, minContrast) ?? _findBySearch(img, minContrast);

/// Xếp bốn góc theo chiều kim đồng hồ (trong ảnh), bắt đầu từ góc gần phía trên bên trái nhất — để lưới không bị
/// lật gương và hướng mặc định dễ đoán.
BoardGrid _ordered(List<Pt> c) {
  var s = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = c[i], b = c[(i + 1) % 4];
    s += a.x * b.y - b.x * a.y;
  }
  var q = s >= 0 ? c : [c[0], c[3], c[2], c[1]];
  var first = 0;
  for (var i = 1; i < 4; i++) {
    if (q[i].x + q[i].y < q[first].x + q[first].y) first = i;
  }
  q = [for (var i = 0; i < 4; i++) q[(first + i) % 4]];
  return BoardGrid(q);
}

BoardGrid? _findByCorners(RgbImage img, double minContrast) {
  // Dò ở hai cỡ vòng, lấy mạng lưới ghép được nhiều điểm giao hơn.
  final big = fitLattice(findXCorners(img)), small = fitLattice(findXCorners(img, small: true));
  final lat = big == null || (small != null && small.strength > big.strength) ? small : big;
  if (lat == null) return null;
  final (eu, ev) = placeBoard(img, lat);
  final a = eu.toDouble(), b = ev.toDouble();
  final g = _ordered([project(lat.h, a, b), project(lat.h, a + 8, b), project(lat.h, a + 8, b + 8), project(lat.h, a, b + 8)]);
  if (!g.valid) return null;
  final score = gridScore(img, g);
  if (score > -1e8 && score < minContrast * 0.5) return null;
  // Mạng lưới đã khớp sát điểm giao; chỉ chỉnh rất nhẹ (và chỉ khi cả bàn nằm trong ảnh).
  if (score < -1e8) return g;
  final r = refineGrid(img, g, startStep: 1.5, shifts: false);
  return gridScore(img, r) >= score ? r : g;
}

BoardGrid? _findBySearch(RgbImage img, double minContrast) {
  final w = img.width.toDouble(), h = img.height.toDouble();
  final side = math.min(w, h);
  final cands = <(double, BoardGrid)>[];
  for (final rotDeg in const [0, -12, 12, -24, 24]) {
    final ca = math.cos(rotDeg * math.pi / 180), sa = math.sin(rotDeg * math.pi / 180);
    for (final s in const [0.45, 0.55, 0.65, 0.75, 0.85, 0.95]) {
      for (final taper in const [1.0, 0.85, 0.7]) {
        for (final aspect in const [1.0, 0.8]) {
          for (final oy in const [-0.2, -0.1, 0.0, 0.1, 0.2]) {
            for (final ox in const [-0.15, 0.0, 0.15]) {
              final cx = w / 2 + ox * w, cy = h / 2 + oy * h;
              final bw = s * side, bh = bw * aspect;
              final tw = bw * taper;
              Pt at(double dx, double dy) => Pt(cx + dx * ca - dy * sa, cy + dx * sa + dy * ca);
              final g = BoardGrid([at(-tw / 2, -bh / 2), at(tw / 2, -bh / 2), at(bw / 2, bh / 2), at(-bw / 2, bh / 2)]);
              cands.add((gridScore(img, g), g));
            }
          }
        }
      }
    }
  }
  cands.sort((a, b) => b.$1.compareTo(a.$1));
  BoardGrid? best;
  var bestScore = -1e9;
  for (final (_, g) in cands.take(5)) {
    final r = refineGrid(img, g);
    final s = gridScore(img, r);
    if (s > bestScore) {
      bestScore = s;
      best = r;
    }
  }
  return bestScore >= minContrast ? best : null;
}
