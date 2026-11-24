/// Vẽ lên hình camera: lưới 8×8 (khi căn chỉnh có 4 núm kéo góc và nhãn a1/h1/a8/h8), nước vừa đi, ô lệch,
/// mũi tên gợi ý — tất cả chiếu theo phối cảnh của bàn thật.
library;

import 'package:material_ui/material_ui.dart';

import '../../core/chess/position.dart';
import '../../core/vision/board.dart';
import '../../shared/board_view.dart';

class BoardOverlay extends CustomPainter {
  BoardOverlay({
    required this.grid,
    required this.rot,
    required this.imageSize,
    this.editing = false,
    this.dragging,
    this.lastMove,
    this.arrow,
    this.marked = const {},
  });
  final BoardGrid grid;
  final int rot;
  final Size imageSize;
  final bool editing;
  final int? dragging;
  final (int, int)? lastMove;
  final (int, int)? arrow;
  final Set<int> marked;

  @override
  void paint(Canvas canvas, Size size) {
    final kx = size.width / imageSize.width, ky = size.height / imageSize.height;
    Offset at(double u, double v) {
      final p = grid.at(u, v);
      return Offset(p.x * kx, p.y * ky);
    }

    Path cellPath(int s) {
      final (c, r) = cellOfSquare(s, rot);
      return Path()
        ..moveTo(at(c.toDouble(), r.toDouble()).dx, at(c.toDouble(), r.toDouble()).dy)
        ..lineTo(at(c + 1.0, r.toDouble()).dx, at(c + 1.0, r.toDouble()).dy)
        ..lineTo(at(c + 1.0, r + 1.0).dx, at(c + 1.0, r + 1.0).dy)
        ..lineTo(at(c.toDouble(), r + 1.0).dx, at(c.toDouble(), r + 1.0).dy)
        ..close();
    }

    final line = Paint()
      ..color = editing ? const Color(0xCC4FD1C5) : const Color(0x664FD1C5)
      ..strokeWidth = editing ? 1.5 : 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i <= 8; i++) {
      canvas.drawLine(at(i.toDouble(), 0), at(i.toDouble(), 8), line);
      canvas.drawLine(at(0, i.toDouble()), at(8, i.toDouble()), line);
    }
    final lm = lastMove;
    if (lm != null) {
      for (final s in [lm.$1, lm.$2]) {
        canvas.drawPath(cellPath(s), Paint()..color = const Color(0x55F6E05E));
      }
    }
    for (final s in marked) {
      canvas.drawPath(cellPath(s), Paint()
        ..color = const Color(0xEEE53E3E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3);
    }
    final a = arrow;
    if (a != null) {
      final (c1, r1) = cellOfSquare(a.$1, rot);
      final (c2, r2) = cellOfSquare(a.$2, rot);
      final p1 = at(c1 + 0.5, r1 + 0.5), p2 = at(c2 + 0.5, r2 + 0.5);
      final cell = (at(c2 + 1.0, r2 + 0.5) - at(c2 + 0.0, r2 + 0.5)).distance;
      canvas.drawPath(cellPath(a.$1), Paint()..color = const Color(0x44007AFF));
      canvas.drawPath(cellPath(a.$2), Paint()..color = const Color(0x66007AFF));
      drawArrow(canvas, p1, p2, cell * 0.22, const Color(0xE638A169));
    }
    if (editing) {
      // Nhãn ô ở bốn góc để người dùng thấy hướng bàn.
      for (final s in const [0, 7, 56, 63]) {
        final (c, r) = cellOfSquare(s, rot);
        final p = at(c + 0.5, r + 0.5);
        final tp = TextPainter(
          text: TextSpan(
            text: sqName(s),
            style: TextStyle(color: s == 0 ? const Color(0xFF68D391) : Colors.white, fontSize: 13, fontWeight: FontWeight.w700, shadows: const [Shadow(blurRadius: 3)]),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
      for (var i = 0; i < 4; i++) {
        final p = Offset(grid.corners[i].x * kx, grid.corners[i].y * ky);
        final isA1 = _cornerIndexOf(0) == i;
        canvas.drawCircle(p, dragging == i ? 16 : 12, Paint()..color = (isA1 ? const Color(0xFF68D391) : Colors.white).withValues(alpha: 0.35));
        canvas.drawCircle(p, dragging == i ? 16 : 12, Paint()
          ..color = isA1 ? const Color(0xFF68D391) : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
      }
    }
  }

  /// Núm góc lưới nào nằm sát ô [s].
  int _cornerIndexOf(int s) {
    final (c, r) = cellOfSquare(s, rot);
    if (c == 0 && r == 0) return 0;
    if (c == 7 && r == 0) return 1;
    if (c == 7 && r == 7) return 2;
    return 3;
  }

  @override
  bool shouldRepaint(BoardOverlay old) => true;
}
