/// Tìm bàn cờ qua các điểm giao bốn ô (chỗ hai ô sáng và hai ô tối chụm đầu vào nhau, hình chữ X).
///
/// Các điểm này có dấu hiệu rất riêng nên dò được ở mọi góc xoay, mọi độ nghiêng, kể cả khi quân che mất một phần.
/// Sau đó ghép chúng thành một mạng lưới đều (qua phép chiếu) và đặt khung 8×8 lên mạng lưới đó.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'image.dart';

class XCorner {
  XCorner(this.x, this.y, this.score);
  final double x, y, score;
}

// 16 điểm trên vòng tròn quanh điểm đang xét: bán kính 5 cho ô cờ to, bán kính 3 cho ô nhỏ hoặc bị ép dẹt vì
// camera nhìn xiên (vòng to hơn nửa ô thì không còn nằm gọn trong bốn ô quanh điểm giao).
const _ring5 = [(5, 0), (5, 2), (4, 4), (2, 5), (0, 5), (-2, 5), (-4, 4), (-5, 2), (-5, 0), (-5, -2), (-4, -4), (-2, -5), (0, -5), (2, -5), (4, -4), (5, -2)];
const _ring3 = [(3, 0), (3, 1), (2, 2), (1, 3), (0, 3), (-1, 3), (-2, 2), (-3, 1), (-3, 0), (-3, -1), (-2, -2), (-1, -3), (0, -3), (1, -3), (2, -2), (3, -1)];

/// Dò điểm giao bốn ô (bộ dò ChESS): trên vòng tròn quanh một điểm giao, hai cung đối nhau cùng sáng, hai cung
/// vuông góc với chúng cùng tối. Cạnh thẳng và vùng phẳng cho đáp ứng âm.
List<XCorner> findXCorners(RgbImage img, {int max = 260, bool small = false}) {
  final w = img.width, h = img.height;
  final ring0 = small ? _ring3 : _ring5;
  final nms = small ? 3 : 4, sep = small ? 4 : 5;
  // Độ sáng, làm mờ nhẹ 3×3.
  final raw = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      raw[y * w + x] = img.lum(x, y).toDouble();
    }
  }
  final lum = Float32List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      var s = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          s += raw[(y + dy) * w + x + dx];
        }
      }
      lum[y * w + x] = s / 9;
    }
  }
  final resp = Float32List(w * h);
  final ring = Float32List(16);
  var top = 0.0;
  for (var y = 6; y < h - 6; y++) {
    for (var x = 6; x < w - 6; x++) {
      var mean = 0.0;
      for (var k = 0; k < 16; k++) {
        final v = lum[(y + ring0[k].$2) * w + x + ring0[k].$1];
        ring[k] = v;
        mean += v;
      }
      mean /= 16;
      var sr = 0.0, dr = 0.0;
      for (var k = 0; k < 4; k++) {
        sr += (ring[k] + ring[k + 8] - ring[k + 4] - ring[k + 12]).abs();
      }
      for (var k = 0; k < 8; k++) {
        dr += (ring[k] - ring[k + 8]).abs();
      }
      final i = y * w + x;
      final local = (lum[i] + lum[i - 1] + lum[i + 1] + lum[i - w] + lum[i + w]) / 5;
      final r = sr - dr - 16 * (local - mean).abs();
      if (r > 0) {
        resp[i] = r;
        if (r > top) top = r;
      }
    }
  }
  // Giữ các đỉnh cục bộ đủ mạnh.
  final out = <XCorner>[];
  final thr = top * 0.12;
  for (var y = 8; y < h - 8; y++) {
    for (var x = 8; x < w - 8; x++) {
      final r = resp[y * w + x];
      if (r < thr) continue;
      var isMax = true;
      var sx = 0.0, sy = 0.0, sw = 0.0;
      for (var dy = -nms; dy <= nms && isMax; dy++) {
        for (var dx = -nms; dx <= nms; dx++) {
          final v = resp[(y + dy) * w + x + dx];
          if (v > r) {
            isMax = false;
            break;
          }
          if (dx.abs() <= 2 && dy.abs() <= 2) {
            sx += v * dx;
            sy += v * dy;
            sw += v;
          }
        }
      }
      if (!isMax) continue;
      // Trọng tâm đáp ứng quanh đỉnh cho vị trí mịn hơn một điểm ảnh.
      out.add(XCorner(x + 0.5 + sx / sw, y + 0.5 + sy / sw, r));
    }
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  // Hai đỉnh sát nhau (bằng điểm trên mặt phẳng đáp ứng) chỉ giữ một.
  final kept = <XCorner>[];
  for (final c in out) {
    if (kept.length >= max) break;
    if (kept.every((k) => (k.x - c.x).abs() > sep || (k.y - c.y).abs() > sep)) kept.add(c);
  }
  return kept;
}

/// Phép chiếu khớp nhất (bình phương tối thiểu) biến src[i] thành dst[i], cần ít nhất 4 cặp điểm.
Float64List? fitHomography(List<Pt> src, List<Pt> dst) {
  if (src.length < 4) return null;
  if (src.length == 4) return homography(src, dst);
  // Chuẩn hoá toạ độ ảnh cho hệ phương trình ổn định.
  var mx = 0.0, my = 0.0;
  for (final p in dst) {
    mx += p.x;
    my += p.y;
  }
  mx /= dst.length;
  my /= dst.length;
  var sc = 0.0;
  for (final p in dst) {
    sc += math.sqrt((p.x - mx) * (p.x - mx) + (p.y - my) * (p.y - my));
  }
  sc = sc / dst.length;
  if (sc < 1e-9) return null;
  final ata = List.generate(8, (_) => Float64List(9));
  void acc(List<double> row, double rhs) {
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 8; j++) {
        ata[i][j] += row[i] * row[j];
      }
      ata[i][8] += row[i] * rhs;
    }
  }

  for (var k = 0; k < src.length; k++) {
    final x = src[k].x, y = src[k].y, u = (dst[k].x - mx) / sc, v = (dst[k].y - my) / sc;
    acc([x, y, 1, 0, 0, 0, -u * x, -u * y], u);
    acc([0, 0, 0, x, y, 1, -v * x, -v * y], v);
  }
  for (var c = 0; c < 8; c++) {
    var p = c;
    for (var r = c + 1; r < 8; r++) {
      if (ata[r][c].abs() > ata[p][c].abs()) p = r;
    }
    if (ata[p][c].abs() < 1e-12) return null;
    final tmp = ata[c];
    ata[c] = ata[p];
    ata[p] = tmp;
    for (var r = 0; r < 8; r++) {
      if (r == c) continue;
      final f = ata[r][c] / ata[c][c];
      if (f != 0) {
        for (var k = c; k < 9; k++) {
          ata[r][k] -= f * ata[c][k];
        }
      }
    }
  }
  final n = [for (var i = 0; i < 8; i++) ata[i][8] / ata[i][i], 1.0];
  // Bỏ chuẩn hoá: ảnh = T⁻¹ · N.
  return Float64List.fromList([
    sc * n[0] + mx * n[6], sc * n[1] + mx * n[7], sc * n[2] + mx * n[8], //
    sc * n[3] + my * n[6], sc * n[4] + my * n[7], sc * n[5] + my * n[8], //
    n[6], n[7], n[8],
  ]);
}

/// Nghịch đảo ma trận 3×3.
Float64List? invert3(Float64List m) {
  final a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  if (det.abs() < 1e-14) return null;
  return Float64List.fromList([
    (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det, //
    (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det, //
    (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det,
  ]);
}

/// Mạng lưới ghép được: [h] biến toạ độ nút (số nguyên) thành điểm ảnh, [nodes] là các nút có điểm giao thật.
class Lattice {
  Lattice(this.h, this.nodes);
  final Float64List h;
  final Set<(int, int)> nodes;

  /// Số nút nằm trong cửa sổ 7×7 tốt nhất (tối đa 49 = thấy đủ mọi điểm giao của bàn).
  int get strength => _bestWindow(nodes).$3;
}

/// Ghép các điểm giao thành mạng lưới đều lớn nhất. Thử từng "ô đơn vị" dựng từ một điểm và hai láng giềng của nó,
/// rồi lan dần ra: điểm nào rơi đúng nút lưới thì nhận, và khớp lại phép chiếu với tất cả điểm đã nhận.
Lattice? fitLattice(List<XCorner> corners) {
  final n = corners.length;
  if (n < 9) return null;
  final pts = [for (final c in corners) Pt(c.x, c.y)];
  // Láng giềng gần nhất của từng điểm.
  final near = <List<int>>[];
  for (var i = 0; i < n; i++) {
    final idx = [for (var j = 0; j < n; j++) if (j != i) j]..sort((a, b) => pts[i].dist(pts[a]).compareTo(pts[i].dist(pts[b])));
    near.add(idx.take(7).toList());
  }

  Map<(int, int), int> inliers(Float64List h, double radius, double cu, double cv) {
    final inv = invert3(h);
    final got = <(int, int), int>{};
    if (inv == null) return got;
    final err = <(int, int), double>{};
    for (var k = 0; k < n; k++) {
      final q = project(inv, pts[k].x, pts[k].y);
      if ((q.x - cu).abs() > radius || (q.y - cv).abs() > radius) continue;
      final iu = q.x.round(), iv = q.y.round();
      final e = math.max((q.x - iu).abs(), (q.y - iv).abs());
      if (e > 0.2) continue;
      final key = (iu, iv);
      if (!err.containsKey(key) || e < err[key]!) {
        err[key] = e;
        got[key] = k;
      }
    }
    return got;
  }

  Lattice? best;
  var bestCount = 0;
  const unit = [Pt(0, 0), Pt(1, 0), Pt(1, 1), Pt(0, 1)];
  for (var a = 0; a < math.min(n, 140); a++) {
    final na = near[a];
    for (var bi = 0; bi < na.length; bi++) {
      for (var ci = bi + 1; ci < na.length; ci++) {
        final b = na[bi], c = na[ci];
        final abx = pts[b].x - pts[a].x, aby = pts[b].y - pts[a].y, acx = pts[c].x - pts[a].x, acy = pts[c].y - pts[a].y;
        final lb = math.sqrt(abx * abx + aby * aby), lc = math.sqrt(acx * acx + acy * acy);
        if (lb < 5 || lc < 5 || lb / lc > 3 || lc / lb > 3) continue;
        final cos = (abx * acx + aby * acy) / (lb * lc);
        if (cos.abs() > 0.8) continue;
        // Đỉnh thứ tư của ô đơn vị phải có điểm giao thật ở gần.
        final dx = pts[b].x + acx, dy = pts[b].y + acy;
        var d = -1;
        var dd = 0.3 * math.min(lb, lc);
        for (var k = 0; k < n; k++) {
          if (k == a || k == b || k == c) continue;
          final e = math.sqrt((pts[k].x - dx) * (pts[k].x - dx) + (pts[k].y - dy) * (pts[k].y - dy));
          if (e < dd) {
            dd = e;
            d = k;
          }
        }
        if (d < 0) continue;
        var h = homography(unit, [pts[a], pts[b], pts[d], pts[c]]);
        if (h == null) continue;
        Map<(int, int), int> got = {};
        var ok = true;
        for (final radius in const [1.6, 2.6, 3.6, 5.0, 7.0, 9.0]) {
          // Lan quanh trọng tâm các nút đã nhận.
          var cu = 0.5, cv = 0.5;
          if (got.isNotEmpty) {
            cu = got.keys.map((k) => k.$1).reduce((x, y) => x + y) / got.length;
            cv = got.keys.map((k) => k.$2).reduce((x, y) => x + y) / got.length;
          }
          got = inliers(h!, radius, cu, cv);
          if (got.length < (radius < 2 ? 5 : 7)) {
            ok = false;
            break;
          }
          final hn = fitHomography([for (final k in got.keys) Pt(k.$1.toDouble(), k.$2.toDouble())], [for (final v in got.values) pts[v]]);
          if (hn == null) {
            ok = false;
            break;
          }
          h = hn;
        }
        if (!ok) continue;
        // Chỉ tính các nút nằm trong một cửa sổ 7×7 (số điểm giao bên trong một bàn cờ).
        final count = _bestWindow(got.keys.toSet()).$3;
        if (count > bestCount) {
          bestCount = count;
          best = Lattice(h!, got.keys.toSet());
        }
      }
    }
  }
  return bestCount >= 12 ? best : null;
}

/// Cửa sổ 7×7 nút chứa nhiều nút nhất: (u đầu, v đầu, số nút).
(int, int, int) _bestWindow(Set<(int, int)> nodes) {
  var best = (0, 0, 0);
  final us = nodes.map((k) => k.$1), vs = nodes.map((k) => k.$2);
  for (var u0 = us.reduce(math.min) - 6; u0 <= us.reduce(math.max); u0++) {
    for (var v0 = vs.reduce(math.min) - 6; v0 <= vs.reduce(math.max); v0++) {
      var c = 0;
      for (final k in nodes) {
        if (k.$1 >= u0 && k.$1 <= u0 + 6 && k.$2 >= v0 && k.$2 <= v0 + 6) c++;
      }
      if (c > best.$3) best = (u0, v0, c);
    }
  }
  return best;
}

double _lumAt(RgbImage img, Pt p) {
  final fx = p.x - 0.5, fy = p.y - 0.5;
  final x0 = fx.floor(), y0 = fy.floor();
  if (x0 < 0 || y0 < 0 || x0 >= img.width - 1 || y0 >= img.height - 1) return double.nan;
  final ax = fx - x0, ay = fy - y0;
  final a = img.lum(x0, y0), b = img.lum(x0 + 1, y0), c = img.lum(x0, y0 + 1), d = img.lum(x0 + 1, y0 + 1);
  return (a + (b - a) * ax) * (1 - ay) + (c + (d - c) * ax) * ay;
}

/// Đường lưới số k theo trục [axis] (0: đường u = k, 1: đường v = k) trông thế nào, xét từng đoạn dài một ô trong
/// khoảng [from, to) của trục kia: chênh sáng hai bên đường có đủ mạnh và đúng dấu đảo xen kẽ của bàn cờ không.
/// Trả về k → (phần đoạn chẵn khớp, phần đoạn lẻ khớp); không có mục nào nếu đường nằm ngoài ảnh.
///  - đường kẻ giữa hai hàng ô: cả đoạn chẵn lẫn đoạn lẻ đều khớp (trừ chỗ quân che);
///  - mép bàn: chỉ một loại đoạn khớp (ô sáng nổi trên viền tối, hoặc ô tối nổi trên viền sáng);
///  - ngoài bàn: không đoạn nào khớp.
Map<int, (double, double)> lineProfile(RgbImage img, Lattice l, int axis, int kFrom, int kTo, int from, int to) {
  Pt at(double k, double t) => axis == 0 ? project(l.h, k, t) : project(l.h, t, k);
  final vals = <int, List<(int, double)>>{};
  for (var k = kFrom; k <= kTo; k++) {
    final row = <(int, double)>[];
    for (var j = from; j < to; j++) {
      var d = 0.0, n = 0;
      for (final t in const [0.25, 0.5, 0.75]) {
        final a = _lumAt(img, at(k + 0.15, j + t)), b = _lumAt(img, at(k - 0.15, j + t));
        if (a.isNaN || b.isNaN) continue;
        d += a - b;
        n++;
      }
      if (n > 0) row.add((j, ((k + j).isEven ? 1 : -1) * d / n));
    }
    if (row.length >= (to - from) / 2) vals[k] = row;
  }
  // Dấu chung và độ tương phản mốc lấy từ toàn bộ các đoạn.
  final all = [for (final r in vals.values) ...r.map((e) => e.$2)];
  if (all.isEmpty) return {};
  final sign = all.reduce((a, b) => a + b) >= 0 ? 1.0 : -1.0;
  final mags = [for (final v in all) v.abs()]..sort();
  final cref = mags[(mags.length * 0.75).floor()];
  double share(Iterable<(int, double)> seg) => seg.isEmpty ? 0 : seg.where((e) => e.$2 * sign > 0.45 * cref).length / seg.length;
  return {
    for (final e in vals.entries)
      e.key: () {
        // Nhiều đoạn chênh sáng mạnh nhưng ngược dấu hoa văn: đây là một mép thẳng thường (mép khung gỗ, mép bàn
        // với nền), không thuộc bàn cờ — đường kẻ giữa hai hàng ô không bao giờ ngược dấu, mép bàn thì các đoạn
        // "không khớp" chỉ nhạt đi chứ không đảo dấu.
        final wrong = e.value.where((x) => x.$2 * sign < -0.45 * cref).length / e.value.length;
        if (wrong >= 0.3) return (0.0, 0.0);
        return (share(e.value.where((x) => (x.$1 + e.key).isEven)), share(e.value.where((x) => (x.$1 + e.key).isOdd)));
      }(),
  };
}

/// Chọn chỗ đặt khung bàn trên mạng lưới: trả về (u, v) của mép đầu (mép kia cách 8 ô).
///
/// Bắt đầu từ cửa sổ chứa nhiều nút nhất, rồi với từng trục thử dời khung vài ô và chấm theo [lineProfile]: bảy
/// đường bên trong phải là đường kẻ giữa hai hàng ô, hai đường mép phải là mép bàn, bên ngoài phải hết hoa văn.
(int, int) placeBoard(RgbImage img, Lattice l) {
  final w = _bestWindow(l.nodes);
  final start = [w.$1 - 1, w.$2 - 1];
  final edge = [start[0], start[1]];
  for (final axis in const [0, 1]) {
    final k0 = start[axis], o0 = start[1 - axis] + 1;
    final prof = lineProfile(img, l, axis, k0 - 5, k0 + 13, o0 - 1, o0 + 7);
    // Mức "đường kẻ bên trong" và mức "mép bàn" của từng đường; đường ngoài ảnh thì không biết (null).
    double? inner(int k) => prof[k] == null ? null : math.min(prof[k]!.$1, prof[k]!.$2);
    double? rim(int k) => prof[k] == null ? null : (prof[k]!.$1 - prof[k]!.$2).abs();
    double? any(int k) => prof[k] == null ? null : math.max(prof[k]!.$1, prof[k]!.$2);
    var best = k0;
    var bestScore = -1e9;
    for (var a = k0 - 2; a <= k0 + 2; a++) {
      var s = 0.0;
      for (var k = a + 1; k <= a + 7; k++) {
        // Đường ngoài ảnh: coi như đường kẻ trung bình, để khung thò ra ngoài ảnh không bị thiệt cũng không được lợi.
        s += inner(k) ?? 0.35;
      }
      for (final e in [a, a + 8]) {
        s += 0.6 * (rim(e) ?? 0.2);
      }
      // Ngay ngoài mép mà còn hoa văn ô cờ thì khung đang đặt lọt vào trong bàn. (Viền bàn có màu trung gian thì
      // chính đường mép cũng trông như đường kẻ bên trong, nên dấu hiệu này mới là cái phân định.)
      for (final (o, wgt) in [(a - 1, 1.0), (a - 2, 0.3), (a + 9, 1.0), (a + 10, 0.3)]) {
        s -= wgt * (any(o) ?? 0);
      }
      // Điểm giao bốn ô chỉ có ở bên trong bàn: mép bàn và bên ngoài không có. Khung nào để điểm giao rơi lên
      // đường mép hay ra ngoài là đặt lệch.
      for (final n in l.nodes) {
        final k = axis == 0 ? n.$1 : n.$2;
        s += k > a && k < a + 8 ? 0.1 : -0.3;
      }
      if (a == k0) s += 0.1;
      if (s > bestScore) {
        bestScore = s;
        best = a;
      }
    }
    edge[axis] = best;
  }
  return (edge[0], edge[1]);
}
