/// Đọc bàn cờ trong ảnh bằng cách "dựng lại rồi so": với một thế cờ giả định, mỗi tia nhìn (một điểm ảnh) phải
/// thấy mặt ô nào đó, hoặc một quân trắng, hoặc một quân đen — có tính quân cao phía trước che quân và ô phía sau.
/// Thế cờ nào dự đoán đúng màu ở nhiều tia nhất là thế cờ đang có trên bàn.
///
/// Không nhận ra loại quân (mã, tượng…): app biết thế cờ từ đầu ván và suy ra nước đi từ những chỗ thay đổi.
/// Màu từng ô và màu quân được học từ chính bàn cờ của người dùng lúc căn chỉnh (thế cờ đã biết).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../chess/position.dart';
import 'board.dart';
import 'image.dart';
import 'pose.dart';

const clsEmpty = 0, clsWhite = 1, clsBlack = 2;

/// Lớp mà thế cờ đòi hỏi ở ô có quân [p].
int clsOf(int p) => p == 0 ? clsEmpty : (colorOf(p) == white ? clsWhite : clsBlack);

/// Chiều cao quân theo loại, tính bằng cạnh ô (bộ cờ Staunton thông dụng).
const pieceHeight = [0.0, 0.95, 1.2, 1.4, 1.05, 1.6, 1.8];

/// Bán kính quân ở độ cao tương đối [rel] (0 = đế, 1 = đỉnh): đế to, thân và đầu nhỏ.
double pieceRadius(double rel) => rel < 0.22 ? 0.3 : 0.17;

/// Độ cao cao nhất (≤ chiều cao quân [h]) mà tia nhìn chạm quân đứng ở ô đó; -1 nếu không chạm.
/// [zs], [ds]: các điểm trên tia đi qua vùng ô — độ cao và khoảng cách ngang tới tâm ô, xếp từ cao xuống thấp.
double _hitZ(Float32List zs, Float32List ds, double h) {
  for (var k = 0; k < zs.length; k++) {
    final z = zs[k];
    if (z <= h && ds[k] <= pieceRadius(z / h)) return z;
  }
  return -1;
}

class _Pass {
  _Pass(this.cell, this.zs, this.ds);
  final int cell;
  final Float32List zs, ds;
}

/// Một tia nhìn: điểm ảnh (px, py), ô lưới [cell] mà tia được đặt ra để soi, ô mặt bàn [plane] tia chạm tới
/// (-1 = ngoài bàn), và các ô mà tia bay ngang qua bên trên ([passes]).
class _Ray {
  _Ray(this.cell, this.px, this.py, this.plane, this.passes, this.core);
  final int cell, px, py, plane;
  final List<_Pass> passes;

  /// Tia đi qua trục giữa thân quân của ô mình — chắc chắn thấy quân nếu ô có quân và không bị che.
  final bool core;
}

const _heights = [0.06, 0.2, 0.35, 0.5, 0.65, 0.8];
const _lateral = [-0.11, 0.0, 0.11];
const _disc = [(0.0, 0.0), (0.13, 0.0), (-0.13, 0.0), (0.0, 0.13), (0.0, -0.13), (0.2, 0.2), (-0.2, 0.2), (0.2, -0.2), (-0.2, -0.2), (0.26, 0.0), (-0.26, 0.0), (0.0, 0.26), (0.0, -0.26)];

/// Hình học cố định của một lần căn bàn: tập tia nhìn và quan hệ che khuất giữa các ô.
class _Geometry {
  _Geometry(this.grid, this.width, this.height) : pose = BoardPose(grid, width, height) {
    for (var cell = 0; cell < 64; cell++) {
      final cx = cell % 8 + 0.5, cy = cell ~/ 8 + 0.5;
      if (pose.topDown) {
        // Nhìn thẳng xuống: quân chỉ che ô của chính nó, lấy mẫu một đĩa giữa ô.
        for (final (dx, dy) in _disc) {
          _add(cell, cx + dx, cy + dy, 0.3, dx.abs() + dy.abs() < 0.2);
        }
        continue;
      }
      // Hướng ngang vuông góc với hướng nhìn: các tia trải theo bề ngang thân quân.
      var vx = pose.camX - cx, vy = pose.camY - cy;
      final vn = math.sqrt(vx * vx + vy * vy);
      if (vn < 1e-6) {
        vx = 0;
        vy = 1;
      } else {
        vx /= vn;
        vy /= vn;
      }
      for (final z in _heights) {
        for (final l in _lateral) {
          _add(cell, cx - vy * l, cy + vx * l, z, l == 0 && z >= 0.2 && z <= 0.65);
        }
      }
    }
    for (final (i, r) in rays.indexed) {
      for (final p in r.passes) {
        byCell[p.cell].add(i);
      }
      if (r.plane >= 0 && !byCell[r.plane].contains(i)) byCell[r.plane].add(i);
    }
  }

  final BoardGrid grid;
  final int width, height;
  final BoardPose pose;
  final List<_Ray> rays = [];

  /// Các tia mà nội dung ô lưới này ảnh hưởng tới (bay qua bên trên ô, hoặc chạm mặt ô).
  final List<List<int>> byCell = List.generate(64, (_) => []);

  void _add(int cell, double x, double y, double z, bool core) {
    final p = pose.project(x, y, z);
    final px = p.x.floor(), py = p.y.floor();
    if (px < 0 || py < 0 || px >= width || py >= height) return;
    final g0 = pose.ground(x, y, z, 0);
    final plane = g0.x >= 0 && g0.y >= 0 && g0.x < 8 && g0.y < 8 ? g0.y.floor() * 8 + g0.x.floor() : -1;
    // Dọc tia từ cao xuống thấp: tia bay qua trên những ô nào, sát tâm ô tới đâu.
    final per = <int, (List<double>, List<double>)>{};
    for (var zz = 1.8; zz >= 0.02; zz -= 0.06) {
      final g = pose.ground(x, y, z, zz);
      final c0 = g.x.floor(), r0 = g.y.floor();
      for (var r = r0 - 1; r <= r0 + 1; r++) {
        for (var c = c0 - 1; c <= c0 + 1; c++) {
          if (c < 0 || r < 0 || c > 7 || r > 7) continue;
          final d = math.sqrt((g.x - c - 0.5) * (g.x - c - 0.5) + (g.y - r - 0.5) * (g.y - r - 0.5));
          if (d > 0.3) continue;
          final e = per.putIfAbsent(r * 8 + c, () => (<double>[], <double>[]));
          e.$1.add(zz);
          e.$2.add(d);
        }
      }
    }
    rays.add(_Ray(cell, px, py, plane, [for (final e in per.entries) _Pass(e.key, Float32List.fromList(e.value.$1), Float32List.fromList(e.value.$2))], core));
  }

  /// Tia [r] thấy gì khi bàn cờ là [cells] (quân theo ô lưới): 0 = mặt bàn, 1 = quân trắng, 2 = quân đen.
  /// Quân bị chạm ở chỗ cao nhất là quân gần camera nhất. [lastHit] nhận ô của quân đó.
  int label(_Ray r, Int8List cells) {
    var best = -1.0, lab = 0;
    lastHit = -1;
    for (final p in r.passes) {
      final q = cells[p.cell];
      if (q == 0) continue;
      final z = _hitZ(p.zs, p.ds, pieceHeight[typeOf(q)]);
      if (z > best) {
        best = z;
        lab = colorOf(q) == white ? 1 : 2;
        lastHit = p.cell;
      }
    }
    return lab;
  }

  int lastHit = -1;
}

/// Chi phí tối đa của một tia (chênh âm log khả năng so với cách hiểu khớp nhất) và hệ số quy về "đơn vị ô": một ô đổi
/// trạng thái rõ ràng làm tổng chi phí lệch chừng 2–5 đơn vị.
const _cap = 6.0, _norm = 10.0;
const _unknown = 1.5;

class SquareClassifier {
  SquareClassifier._(this._geo, this.rot, this._ref, this._refSd, this._models) {
    for (var i = 0; i < 64; i++) {
      _cellSq[i] = squareOfCell(i % 8, i ~/ 8, rot);
    }
  }

  _Geometry _geo;
  final int rot;

  /// Màu mặt ô trống của từng ô lưới (ánh sáng không đều nên mỗi ô một màu), và độ lệch chuẩn từng kênh màu theo
  /// loại ô (chẵn lẻ của cột + hàng).
  final List<List<double>> _ref;
  final List<List<double>> _refSd;

  /// Màu quân: [trắng, đen] → vài cụm màu (mặt sáng, mặt tối), mỗi cụm một phân bố chuẩn.
  final List<List<_Gauss>> _models;
  final Int32List _cellSq = Int32List(64);

  BoardGrid get grid => _geo.grid;

  /// Góc nâng camera (độ) ước lượng từ lưới; 90 = nhìn thẳng xuống.
  double get elevation => _geo.pose.elevation;

  /// Quân trắng sáng hơn quân đen bao nhiêu (độ sáng 0…255); âm nghĩa là hướng bàn đang bị ngược.
  double get whiteBrighter => _lumOf(_mixMean(_models[0])) - _lumOf(_mixMean(_models[1]));

  Int8List _cells(List<int> board) {
    final c = Int8List(64);
    for (var i = 0; i < 64; i++) {
      c[i] = board[_cellSq[i]];
    }
    return c;
  }

  /// Học từ ảnh [img] khi bàn cờ đang ở thế [board] (64 quân, a1 = 0), lưới [g], xoay [rot].
  static SquareClassifier? calibrate(RgbImage img, BoardGrid g, int rot, List<int> board) {
    final geo = _Geometry(g, img.width, img.height);
    if (geo.rays.length < 200) return null;
    final cells = Int8List(64);
    for (var i = 0; i < 64; i++) {
      cells[i] = board[squareOfCell(i % 8, i ~/ 8, rot)];
    }
    final planeSamples = List.generate(64, (_) => <List<int>>[]);
    final pieceSamples = [<List<int>>[], <List<int>>[]];
    for (final r in geo.rays) {
      final lab = geo.label(r, cells);
      final px = _pixel(img, r);
      if (lab == 0) {
        if (r.plane >= 0) planeSamples[r.plane].add(px);
      } else if (r.core && geo.lastHit == r.cell) {
        pieceSamples[lab - 1].add(px);
      }
    }
    if (pieceSamples[0].length < 4 || pieceSamples[1].length < 4) return null;
    // Màu mặt từng ô: trung vị các tia chạm mặt ô đó. Ô không có tia nào (đang bị che kín) thì lấy theo các ô cùng
    // màu gần nhất.
    final ref = List<List<double>>.filled(64, const []);
    for (var i = 0; i < 64; i++) {
      if (planeSamples[i].length >= 3) ref[i] = _medianColor(planeSamples[i]);
    }
    for (var i = 0; i < 64; i++) {
      if (ref[i].isNotEmpty) continue;
      final c = i % 8, r = i ~/ 8;
      final near = <(double, List<double>)>[];
      for (var j = 0; j < 64; j++) {
        final cj = j % 8, rj = j ~/ 8;
        if ((cj + rj) % 2 != (c + r) % 2 || planeSamples[j].length < 3) continue;
        near.add((((cj - c) * (cj - c) + (rj - r) * (rj - r)).toDouble(), ref[j]));
      }
      if (near.isEmpty) return null;
      near.sort((a, b) => a.$1.compareTo(b.$1));
      var wsum = 0.0;
      final acc = [0.0, 0.0, 0.0];
      for (final (d2, col) in near.take(4)) {
        final w = 1 / d2;
        wsum += w;
        for (var ch = 0; ch < 3; ch++) {
          acc[ch] += col[ch] * w;
        }
      }
      ref[i] = [for (final a in acc) a / wsum];
    }
    final refSd = <List<double>>[];
    for (final par in const [0, 1]) {
      final res = [<double>[], <double>[], <double>[]];
      for (var i = 0; i < 64; i++) {
        if ((i % 8 + i ~/ 8) % 2 != par) continue;
        for (final p in planeSamples[i]) {
          for (var ch = 0; ch < 3; ch++) {
            res[ch].add((p[ch] - ref[i][ch]).abs());
          }
        }
      }
      // Độ lệch điển hình từng kênh (bỏ phần đuôi do bóng đổ, tia lạc): phân vị 68% của sai số tuyệt đối ≈ 1 σ.
      refSd.add([
        for (final r in res)
          () {
            if (r.isEmpty) return 10.0;
            r.sort();
            return math.max(5.0, r[(r.length * 0.68).floor()]);
          }(),
      ]);
    }
    final models = [for (final s in pieceSamples) _mixture(s, 2)];
    return SquareClassifier._(geo, rot, ref, refSd, models);
  }

  /// Đổi sang lưới [g] (ảnh chụp lại từ chỗ hơi khác), giữ màu đã học.
  void regrid(BoardGrid g, int width, int height) => _geo = _Geometry(g, width, height);

  /// Quan sát một khung hình.
  FrameObs observe(RgbImage img) {
    if (img.width != _geo.width || img.height != _geo.height) regrid(_geo.grid, img.width, img.height);
    final n = _geo.rays.length;
    final costs = Float32List(n * 3);
    final nll = [0.0, 0.0, 0.0];
    for (var i = 0; i < n; i++) {
      final r = _geo.rays[i];
      final px = _pixel(img, r);
      // Độ "bất ngờ" (âm log khả năng) của màu điểm ảnh dưới ba cách hiểu. Phân bố rộng (màu quân) phải trả giá cho
      // độ rộng của nó, nếu không cách hiểu "có quân" lúc nào cũng dễ khớp hơn "ô trống".
      if (r.plane < 0) {
        nll[0] = double.nan;
      } else {
        final sd = _refSd[(r.plane % 8 + r.plane ~/ 8) % 2], m = _ref[r.plane];
        var v = 0.0;
        for (var ch = 0; ch < 3; ch++) {
          final z = (px[ch] - m[ch]) / sd[ch];
          v += 0.5 * z * z + math.log(sd[ch]);
        }
        nll[0] = v;
      }
      for (var k = 0; k < 2; k++) {
        var best = double.infinity;
        for (final g in _models[k]) {
          final v = g.nll(px);
          if (v < best) best = v;
        }
        nll[1 + k] = best;
      }
      var lo = math.min(nll[1], nll[2]);
      if (!nll[0].isNaN && nll[0] < lo) lo = nll[0];
      // Tia thấy nền ngoài bàn (viền gỗ, mặt bàn): không biết màu, coi như khớp vừa phải.
      costs[i * 3] = nll[0].isNaN ? _unknown : math.min(_cap, nll[0] - lo);
      costs[i * 3 + 1] = math.min(_cap, nll[1] - lo);
      costs[i * 3 + 2] = math.min(_cap, nll[2] - lo);
    }
    return FrameObs._(this, costs);
  }

  /// Học dần màu mặt ô từ những tia đang thấy mặt bàn theo thế [board] và trông đúng là mặt bàn (ô vừa được dọn
  /// quân, ánh sáng đổi chậm). Gọi khi bàn đứng yên, khớp thế cờ.
  void adapt(RgbImage img, List<int> board, {double rate = 0.3}) {
    if (img.width != _geo.width || img.height != _geo.height) return;
    final cells = _cells(board);
    final samples = List.generate(64, (_) => <List<int>>[]);
    for (final r in _geo.rays) {
      if (r.plane < 0 || _geo.label(r, cells) != 0) continue;
      samples[r.plane].add(_pixel(img, r));
    }
    for (var i = 0; i < 64; i++) {
      if (samples[i].length < 4) continue;
      final m = _medianColor(samples[i]);
      // Lệch quá xa màu đã học thì không phải mặt ô (tay, quân đặt lệch): bỏ qua.
      final sd = _refSd[(i % 8 + i ~/ 8) % 2];
      if (_dist(m, _ref[i]) > 3.5 * (sd[0] + sd[1] + sd[2])) continue;
      for (var ch = 0; ch < 3; ch++) {
        _ref[i][ch] += (m[ch] - _ref[i][ch]) * rate;
      }
    }
  }
}

/// Một khung hình đã đo sẵn: mỗi tia khớp tới đâu với "mặt bàn", "quân trắng", "quân đen". Từ đó chấm điểm bất kỳ
/// thế cờ giả định nào (điểm càng thấp càng khớp).
class FrameObs {
  FrameObs._(this._cl, this._costs) : _rayCost = Float32List(_cl._geo.rays.length);
  final SquareClassifier _cl;
  final Float32List _costs;
  final Float32List _rayCost;
  Int8List _base = Int8List(64);
  double _baseTotal = 0;

  double _eval(int i, Int8List cells) {
    final geo = _cl._geo;
    return _costs[i * 3 + geo.label(geo.rays[i], cells)];
  }

  /// Chấm thế cờ [board] và lấy nó làm mốc cho [costOf] và [odd].
  double setBase(List<int> board) {
    _base = _cl._cells(board);
    var t = 0.0;
    for (var i = 0; i < _rayCost.length; i++) {
      final c = _eval(i, _base);
      _rayCost[i] = c;
      t += c;
    }
    return _baseTotal = t / _norm;
  }

  double get baseTotal => _baseTotal;

  /// Điểm của thế cờ [board], tính nhanh từ mốc: chỉ xét lại các tia liên quan tới những ô khác mốc.
  double costOf(List<int> board) {
    final cells = _cl._cells(board);
    final seen = <int>{};
    var delta = 0.0;
    for (var c = 0; c < 64; c++) {
      if (cells[c] == _base[c]) continue;
      for (final i in _cl._geo.byCell[c]) {
        if (!seen.add(i)) continue;
        delta += _eval(i, cells) - _rayCost[i];
      }
    }
    return _baseTotal + delta / _norm;
  }

  /// Ô lưới [cell]: đổi riêng ô đó sang lớp khác thì khớp hơn mốc bao nhiêu đơn vị, và lớp khớp nhất.
  (double, int) _alt(int cell) {
    final cur = _base[cell];
    final cells = Int8List.fromList(_base);
    final t = typeOf(cur) == 0 ? knight : typeOf(cur);
    var best = 0.0, cls = clsOf(cur);
    for (final alt in [0, piece(white, t), piece(black, t)]) {
      if (clsOf(alt) == clsOf(cur)) continue;
      cells[cell] = alt;
      var delta = 0.0;
      for (final i in _cl._geo.byCell[cell]) {
        delta += _eval(i, cells) - _rayCost[i];
      }
      if (-delta / _norm > best) {
        best = -delta / _norm;
        cls = clsOf(alt);
      }
    }
    return (best, cls);
  }

  /// Các ô (a1 = 0) mà ảnh cho thấy khác hẳn thế cờ mốc: đổi riêng ô đó sang trống / quân trắng / quân đen thì khớp
  /// hơn ít nhất [margin] đơn vị. Ô bị che kín không bao giờ lọt vào đây.
  Set<int> odd({double margin = 1.5}) => {
        for (var c = 0; c < 64; c++)
          if (_alt(c).$1 > margin) _cl._cellSq[c],
      };

  /// Lớp khớp nhất của ô [square] khi các ô khác giữ như mốc.
  int clsAt(int square) => _alt(_cl._cellSq.indexOf(square)).$2;
}

List<int> _pixel(RgbImage img, _Ray r) {
  final i = (r.py * img.width + r.px) * 3;
  return [img.data[i], img.data[i + 1], img.data[i + 2]];
}

double _lumOf(List<num> c) => (c[0] * 77 + c[1] * 150 + c[2] * 29) / 256;

List<double> _medianColor(List<List<int>> px) => [for (var ch = 0; ch < 3; ch++) _median([for (final p in px) p[ch].toDouble()])];

double _dist(List<num> a, List<num> b) {
  final dr = a[0] - b[0], dg = a[1] - b[1], db = a[2] - b[2];
  return math.sqrt(dr * dr + dg * dg + db * db);
}

double _median(List<double> v) {
  v.sort();
  return v[v.length ~/ 2];
}

/// Một cụm màu: phân bố chuẩn theo từng kênh, kèm trọng số trong hỗn hợp.
class _Gauss {
  _Gauss(this.mean, this.sd, this.weight) : _const = math.log(sd[0]) + math.log(sd[1]) + math.log(sd[2]) - math.log(weight);
  final List<double> mean, sd;
  final double weight, _const;

  double nll(List<int> px) {
    var v = _const;
    for (var ch = 0; ch < 3; ch++) {
      final z = (px[ch] - mean[ch]) / sd[ch];
      v += 0.5 * z * z;
    }
    return v;
  }
}

List<double> _mixMean(List<_Gauss> m) => [for (var ch = 0; ch < 3; ch++) m.map((g) => g.mean[ch] * g.weight).reduce((a, b) => a + b)];

/// Gom màu [px] thành [k] cụm (k-means, khởi đầu theo độ sáng), mỗi cụm thành một phân bố chuẩn.
List<_Gauss> _mixture(List<List<int>> px, int k) {
  final sorted = [...px]..sort((a, b) => _lumOf(a).compareTo(_lumOf(b)));
  var centers = [
    for (var i = 0; i < k; i++) [for (final v in sorted[((i + 0.5) * sorted.length / k).floor()]) v.toDouble()],
  ];
  var assign = List.filled(px.length, 0);
  for (var it = 0; it < 8; it++) {
    final sum = List.generate(k, (_) => [0.0, 0.0, 0.0]);
    final n = List.filled(k, 0);
    assign = [
      for (final p in px)
        () {
          var b = 0;
          for (var j = 1; j < k; j++) {
            if (_dist(p, centers[j]) < _dist(p, centers[b])) b = j;
          }
          return b;
        }(),
    ];
    for (var i = 0; i < px.length; i++) {
      n[assign[i]]++;
      for (var ch = 0; ch < 3; ch++) {
        sum[assign[i]][ch] += px[i][ch];
      }
    }
    centers = [
      for (var j = 0; j < k; j++) n[j] == 0 ? centers[j] : [for (final s in sum[j]) s / n[j]],
    ];
  }
  final out = <_Gauss>[];
  for (var j = 0; j < k; j++) {
    final mine = [for (var i = 0; i < px.length; i++) if (assign[i] == j) px[i]];
    if (mine.length < 2) continue;
    out.add(_Gauss(centers[j], [
      for (var ch = 0; ch < 3; ch++)
        math.max(7.0, math.sqrt(mine.map((p) => (p[ch] - centers[j][ch]) * (p[ch] - centers[j][ch])).reduce((a, b) => a + b) / mine.length)),
    ], mine.length / px.length));
  }
  if (out.isEmpty) out.add(_Gauss(_medianColor(px), [20, 20, 20], 1));
  return out;
}

/// Thế cờ [board] khớp ảnh tới đâu với lưới [g] xoay [rot] (càng thấp càng khớp); vô cực nếu không học được màu.
/// Xoay hay đặt lưới sai thì màu học được lẫn lộn (điểm tổng có khi vẫn thấp) nhưng nhiều ô tự mâu thuẫn, nên số ô
/// lệch được xét trước. Xoay 180° cũng tự khớp (lớp "trắng" học từ quân đen): chỉ nhận khi quân trắng sáng hơn.
double _fit(RgbImage img, BoardGrid g, int rot, List<int> board) {
  final cl = SquareClassifier.calibrate(img, g, rot, board);
  if (cl == null) return double.infinity;
  final obs = cl.observe(img);
  // Lưới thò ra ngoài ảnh thì có ít tia hơn: tính theo trung bình mỗi tia, và phạt phần không nhìn thấy.
  final seen = cl._geo.rays.length / 1152;
  var cost = obs.setBase(board) / seen + 300 * (1 - seen);
  cost += 100.0 * obs.odd().length;
  if (cl.whiteBrighter < 0) cost += 1e5;
  return cost;
}

/// Đoán hướng bàn cờ từ một thế đã biết (thường là thế khởi đầu): xoay nào cho ảnh khớp thế cờ nhất.
int guessRotation(RgbImage img, BoardGrid g, List<int> board) {
  var best = 0, bestCost = double.infinity;
  for (var rot = 0; rot < 4; rot++) {
    final cost = _fit(img, g, rot, board);
    if (cost < bestCost) {
      bestCost = cost;
      best = rot;
    }
  }
  return best;
}
