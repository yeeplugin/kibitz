/// Ảnh màu RGB 8 bit và các phép chuyển từ khung hình camera. Dart thuần.
library;

import 'dart:math' as math;
import 'dart:typed_data';

class Pt {
  const Pt(this.x, this.y);
  final double x, y;
  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double k) => Pt(x * k, y * k);
  double dist(Pt o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));
  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

class RgbImage {
  RgbImage(this.width, this.height, [Uint8List? data]) : data = data ?? Uint8List(width * height * 3);
  final int width, height;
  final Uint8List data;

  int lum(int x, int y) {
    final i = (y * width + x) * 3;
    return (data[i] * 77 + data[i + 1] * 150 + data[i + 2] * 29) >> 8;
  }

  /// RGBA cho `decodeImageFromPixels`.
  Uint8List toRgba() {
    final out = Uint8List(width * height * 4);
    for (var i = 0, j = 0; i < width * height; i++, j += 4) {
      out[j] = data[i * 3];
      out[j + 1] = data[i * 3 + 1];
      out[j + 2] = data[i * 3 + 2];
      out[j + 3] = 255;
    }
    return out;
  }

  /// Thu nhỏ và xoay [quarterTurns] lần 90° theo chiều kim đồng hồ từ ảnh nguồn đọc qua [read].
  /// [read] (x, y, out, o) ghi RGB của điểm (x, y) nguồn vào out[o..o+2].
  static RgbImage resample(int srcW, int srcH, int maxSide, int quarterTurns, void Function(int x, int y, Uint8List out, int o) read) {
    final f = math.max(1, (math.max(srcW, srcH) / maxSide).ceil());
    final w = srcW ~/ f, h = srcH ~/ f;
    final q = quarterTurns & 3;
    final ow = q.isOdd ? h : w, oh = q.isOdd ? w : h;
    final img = RgbImage(ow, oh);
    final d = img.data;
    var o = 0;
    for (var y = 0; y < oh; y++) {
      for (var x = 0; x < ow; x++, o += 3) {
        // Điểm (x, y) của ảnh đã xoay ứng với điểm nào của ảnh nguồn đã thu nhỏ.
        final (sx, sy) = switch (q) {
          1 => (y, h - 1 - x),
          2 => (w - 1 - x, h - 1 - y),
          3 => (w - 1 - y, x),
          _ => (x, y),
        };
        read(sx * f + (f >> 1), sy * f + (f >> 1), d, o);
      }
    }
    return img;
  }

  factory RgbImage.fromBgra(Uint8List bgra, int w, int h, int bytesPerRow, {int maxSide = 480, int quarterTurns = 0}) =>
      resample(w, h, maxSide, quarterTurns, (x, y, out, o) {
        final i = y * bytesPerRow + x * 4;
        out[o] = bgra[i + 2];
        out[o + 1] = bgra[i + 1];
        out[o + 2] = bgra[i];
      });

  factory RgbImage.fromRgba(Uint8List rgba, int w, int h, {int maxSide = 480, int quarterTurns = 0}) =>
      resample(w, h, maxSide, quarterTurns, (x, y, out, o) {
        final i = (y * w + x) * 4;
        out[o] = rgba[i];
        out[o + 1] = rgba[i + 1];
        out[o + 2] = rgba[i + 2];
      });

  /// Khung YUV420 của camera Android (3 mặt phẳng Y, U, V).
  factory RgbImage.fromYuv(Uint8List yp, Uint8List up, Uint8List vp, int w, int h, int yRow, int uvRow, int uvPixel,
          {int maxSide = 480, int quarterTurns = 0}) =>
      resample(w, h, maxSide, quarterTurns, (x, y, out, o) {
        final yy = yp[y * yRow + x];
        final ui = (y >> 1) * uvRow + (x >> 1) * uvPixel;
        final u = up[ui] - 128, v = vp[ui] - 128;
        out[o] = (yy + 1.402 * v).round().clamp(0, 255);
        out[o + 1] = (yy - 0.344 * u - 0.714 * v).round().clamp(0, 255);
        out[o + 2] = (yy + 1.772 * u).round().clamp(0, 255);
      });
}

/// Giải phép chiếu H (9 phần tử) biến src[i] thành dst[i] với 4 cặp điểm.
Float64List? homography(List<Pt> src, List<Pt> dst) {
  final a = List.generate(8, (_) => Float64List(9));
  for (var i = 0; i < 4; i++) {
    final x = src[i].x, y = src[i].y, u = dst[i].x, v = dst[i].y;
    a[i * 2].setAll(0, [x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    a[i * 2 + 1].setAll(0, [0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  for (var c = 0; c < 8; c++) {
    var p = c;
    for (var r = c + 1; r < 8; r++) {
      if (a[r][c].abs() > a[p][c].abs()) p = r;
    }
    if (a[p][c].abs() < 1e-12) return null;
    final tmp = a[c];
    a[c] = a[p];
    a[p] = tmp;
    for (var r = 0; r < 8; r++) {
      if (r == c) continue;
      final f = a[r][c] / a[c][c];
      if (f != 0) {
        for (var k = c; k < 9; k++) {
          a[r][k] -= f * a[c][k];
        }
      }
    }
  }
  final h = Float64List(9);
  for (var i = 0; i < 8; i++) {
    h[i] = a[i][8] / a[i][i];
  }
  h[8] = 1;
  return h;
}

Pt project(Float64List h, double x, double y) {
  final d = h[6] * x + h[7] * y + h[8];
  return Pt((h[0] * x + h[1] * y + h[2]) / d, (h[3] * x + h[4] * y + h[5]) / d);
}
