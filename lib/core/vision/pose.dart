/// Vị trí camera so với bàn cờ, suy ra từ lưới 8×8 trong ảnh.
///
/// Lưới chỉ cho biết mặt bàn nằm đâu trong ảnh. Để biết một quân cờ cao (không nằm trên mặt bàn) hiện ở đâu và che
/// những gì phía sau, cần biết camera đứng ở đâu: giả sử tâm ảnh là tâm quang học và điểm ảnh vuông thì tiêu cự và
/// hướng nhìn tính được từ phép chiếu của lưới. Toạ độ: (x, y) theo ô lưới 0…8, z là độ cao tính bằng cạnh ô.
library;

import 'dart:math' as math;

import 'board.dart';
import 'image.dart';

class BoardPose {
  BoardPose._(this.grid, this.topDown, this._f, this._cx, this._cy, this._r1, this._r2, this._r3, this._t, this.camX, this.camY, this.camZ);

  final BoardGrid grid;

  /// Camera nhìn gần như thẳng từ trên xuống (hoặc không tính được phối cảnh): coi các tia nhìn là thẳng đứng.
  final bool topDown;
  final double _f, _cx, _cy;
  final List<double> _r1, _r2, _r3, _t;

  /// Vị trí camera theo toạ độ bàn.
  final double camX, camY, camZ;

  /// Góc nâng của camera so với mặt bàn, nhìn vào tâm bàn (độ); 90 = thẳng từ trên xuống.
  double get elevation {
    if (topDown) return 90;
    final d = math.sqrt((camX - 4) * (camX - 4) + (camY - 4) * (camY - 4));
    return math.atan2(camZ, d) * 180 / math.pi;
  }

  factory BoardPose(BoardGrid grid, int width, int height) {
    final h = grid.h;
    final cx = width / 2, cy = height / 2;
    // Dời gốc toạ độ ảnh về tâm ảnh.
    final h1 = [h[0] - cx * h[6], h[3] - cy * h[6], h[6]];
    final h2 = [h[1] - cx * h[7], h[4] - cy * h[7], h[7]];
    final h3 = [h[2] - cx * h[8], h[5] - cy * h[8], h[8]];
    // Hai cạnh lưới vuông góc và dài bằng nhau trong không gian → hai công thức cho bình phương tiêu cự.
    final da = h1[2] * h2[2], db = h2[2] * h2[2] - h1[2] * h1[2];
    final na = -(h1[0] * h2[0] + h1[1] * h2[1]), nb = h1[0] * h1[0] + h1[1] * h1[1] - h2[0] * h2[0] - h2[1] * h2[1];
    final size = math.max(width, height).toDouble();
    final scale = (h1[0] * h1[0] + h1[1] * h1[1] + h2[0] * h2[0] + h2[1] * h2[1]) / 2;
    double? f2;
    // Mẫu số nhỏ so với cỡ lưới nghĩa là gần như không có phối cảnh.
    final ea = da.abs() * size * size / scale, eb = db.abs() * size * size / scale;
    if (math.max(ea, eb) > 0.02) f2 = ea >= eb ? na / da : nb / db;
    BoardPose flat() => BoardPose._(grid, true, 1, cx, cy, const [1, 0, 0], const [0, 1, 0], const [0, 0, 1], const [0, 0, 1], 4, 4, 1e6);
    if (f2 == null) return flat();
    var f = f2 > 0 ? math.sqrt(f2) : double.nan;
    // Ảnh bị cắt, lưới đặt chưa chuẩn: tiêu cự tính ra vô lý thì dùng tiêu cự điển hình của điện thoại.
    if (f.isNaN || f < 0.4 * size || f > 12 * size) f = 1.2 * size;
    var a = [h1[0] / f, h1[1] / f, h1[2]], b = [h2[0] / f, h2[1] / f, h2[2]], t = [h3[0] / f, h3[1] / f, h3[2]];
    final lam = 2 / (_norm(a) + _norm(b));
    final s = t[2] * lam < 0 ? -lam : lam;
    a = [for (final v in a) v * s];
    b = [for (final v in b) v * s];
    t = [for (final v in t) v * s];
    var r3 = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    // Tâm camera C = -Rᵀ t; trục z phải hướng về phía camera (lên trên mặt bàn).
    var cz = -(r3[0] * t[0] + r3[1] * t[1] + r3[2] * t[2]);
    if (cz < 0) {
      r3 = [for (final v in r3) -v];
      cz = -cz;
    }
    final camX = -(a[0] * t[0] + a[1] * t[1] + a[2] * t[2]) / (_norm(a) * _norm(a));
    final camY = -(b[0] * t[0] + b[1] * t[1] + b[2] * t[2]) / (_norm(b) * _norm(b));
    if (cz < 0.5 || cz.isNaN) return flat();
    return BoardPose._(grid, false, f, cx, cy, a, b, r3, t, camX, camY, cz);
  }

  static double _norm(List<double> v) => math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

  /// Điểm (x, y, z) của không gian bàn cờ hiện ở đâu trong ảnh.
  Pt project(double x, double y, double z) {
    if (topDown || z == 0) return grid.at(x, y);
    // Điểm trên mặt bàn mà tia nhìn qua (x, y, z) chạm tới: cùng một điểm ảnh.
    final g = ground(x, y, z, 0);
    return grid.at(g.x, g.y);
  }

  /// Tia nhìn đi qua điểm (x, y, z): vị trí (x, y) của tia ở độ cao [atZ].
  Pt ground(double x, double y, double z, double atZ) {
    if (topDown) return Pt(x, y);
    final k = (atZ - z) / (camZ - z);
    return Pt(x + (camX - x) * k, y + (camY - y) * k);
  }

  // Giữ các thành phần phép chiếu đầy đủ để kiểm tra chéo trong test.
  Pt projectFull(double x, double y, double z) {
    if (topDown) return grid.at(x, y);
    final px = _r1[0] * x + _r2[0] * y + _r3[0] * z + _t[0];
    final py = _r1[1] * x + _r2[1] * y + _r3[1] * z + _t[1];
    final pz = _r1[2] * x + _r2[2] * y + _r3[2] * z + _t[2];
    return Pt(_f * px / pz + _cx, _f * py / pz + _cy);
  }
}
