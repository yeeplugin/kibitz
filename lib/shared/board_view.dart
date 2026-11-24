/// Bàn cờ 2D: vẽ quân, tô nước vừa đi, mũi tên gợi ý, ô lệch; chạm để chọn ô.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/chess/position.dart';

const lightSq = Color(0xFFEEDAB6);
const darkSq = Color(0xFFB58863);

/// Màu chủ đạo của app (icon, nút, mũi tên gợi ý).
const brandBlue = Color(0xFF007AFF);
const _glyph = ['', '♟', '♞', '♝', '♜', '♛', '♚'];

class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.board,
    this.flipped = false,
    this.lastMove,
    this.arrow,
    this.selected,
    this.targets = const {},
    this.marked = const {},
    this.onTap,
  });

  /// 64 quân, a1 = 0.
  final List<int> board;
  final bool flipped;
  final (int, int)? lastMove;
  final (int, int)? arrow;
  final int? selected;
  final Set<int> targets;

  /// Ô cần chú ý (bàn thật không khớp).
  final Set<int> marked;
  final void Function(int square)? onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final size = c.maxWidth;
        return GestureDetector(
          onTapDown: onTap == null
              ? null
              : (d) {
                  final f = (d.localPosition.dx / size * 8).floor().clamp(0, 7);
                  final r = (d.localPosition.dy / size * 8).floor().clamp(0, 7);
                  onTap!(flipped ? sqOf(7 - f, r) : sqOf(f, 7 - r));
                },
          child: CustomPaint(
            size: Size.square(size),
            painter: _BoardPainter(this),
          ),
        );
      }),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.v);
  final BoardView v;

  Rect _rect(int s, double cell) {
    final f = v.flipped ? 7 - fileOf(s) : fileOf(s);
    final r = v.flipped ? rankOf(s) : 7 - rankOf(s);
    return Rect.fromLTWH(f * cell, r * cell, cell, cell);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    for (var s = 0; s < 64; s++) {
      final light = (fileOf(s) + rankOf(s)).isOdd;
      canvas.drawRect(_rect(s, cell), Paint()..color = light ? lightSq : darkSq);
    }
    final lm = v.lastMove;
    if (lm != null) {
      for (final s in [lm.$1, lm.$2]) {
        canvas.drawRect(_rect(s, cell), Paint()..color = const Color(0x66F6E05E));
      }
    }
    if (v.selected != null) canvas.drawRect(_rect(v.selected!, cell), Paint()..color = const Color(0x77007AFF));
    for (final s in v.marked) {
      canvas.drawRect(_rect(s, cell).deflate(1.5), Paint()
        ..color = const Color(0xFFE53E3E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3);
    }
    // Toạ độ ở mép.
    for (var i = 0; i < 8; i++) {
      final fileLbl = 'abcdefgh'[v.flipped ? 7 - i : i];
      final rankLbl = '${v.flipped ? i + 1 : 8 - i}';
      _text(canvas, fileLbl, Offset(i * cell + cell - cell * 0.18, size.height - cell * 0.24), cell * 0.17, i.isEven ? lightSq : darkSq);
      _text(canvas, rankLbl, Offset(cell * 0.05, i * cell + cell * 0.03), cell * 0.17, i.isOdd ? lightSq : darkSq);
    }
    for (var s = 0; s < 64; s++) {
      if (v.board[s] != 0) paintPiece(canvas, _rect(s, cell), v.board[s]);
    }
    for (final s in v.targets) {
      final r = _rect(s, cell);
      canvas.drawCircle(r.center, cell * (v.board[s] == 0 ? 0.14 : 0.42), Paint()
        ..color = const Color(0x55007AFF)
        ..style = v.board[s] == 0 ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = cell * 0.08);
    }
    final a = v.arrow;
    if (a != null) drawArrow(canvas, _rect(a.$1, cell).center, _rect(a.$2, cell).center, cell * 0.16, const Color(0xCC007AFF));
  }

  void _text(Canvas canvas, String s, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}

/// Vẽ quân [p] giữa ô [r]: ký tự cờ Unicode, thân trắng viền tối hoặc thân đen viền sáng để nổi trên mọi ô.
void paintPiece(Canvas canvas, Rect r, int p) {
  final w = colorOf(p) == white;
  TextPainter glyph(Paint paint) => TextPainter(
        text: TextSpan(
          text: '${_glyph[typeOf(p)]}\uFE0E',
          style: TextStyle(
            fontSize: r.height * 0.8,
            height: 1,
            fontFamilyFallback: const ['Apple Symbols', 'Noto Sans Symbols 2', 'DejaVu Sans'],
            foreground: paint,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
  final fill = glyph(Paint()..color = w ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A1A));
  final outline = glyph(Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r.height * 0.045
    ..color = w ? const Color(0xFF222222) : const Color(0xFFDDDDDD));
  final off = r.center - Offset(fill.width / 2, fill.height / 2);
  outline.paint(canvas, off);
  fill.paint(canvas, off);
}

/// Một quân cờ đứng riêng (bảng chọn quân).
class PieceIcon extends StatelessWidget {
  const PieceIcon(this.piece, {super.key, this.size = 36});
  final int piece;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _PiecePainter(piece));
}

class _PiecePainter extends CustomPainter {
  _PiecePainter(this.p);
  final int p;
  @override
  void paint(Canvas canvas, Size size) => paintPiece(canvas, Offset.zero & size, p);
  @override
  bool shouldRepaint(_PiecePainter old) => old.p != p;
}

/// Mũi tên từ [a] tới [b], thân rộng [w].
void drawArrow(Canvas canvas, Offset a, Offset b, double w, Color color) {
  final d = b - a;
  final len = d.distance;
  if (len < 1) return;
  final u = d / len;
  final n = Offset(-u.dy, u.dx);
  final head = math.min(len * 0.45, w * 2.6);
  final base = b - u * head;
  final path = Path()
    ..moveTo(a.dx + n.dx * w / 2, a.dy + n.dy * w / 2)
    ..lineTo(base.dx + n.dx * w / 2, base.dy + n.dy * w / 2)
    ..lineTo(base.dx + n.dx * w * 1.4, base.dy + n.dy * w * 1.4)
    ..lineTo(b.dx, b.dy)
    ..lineTo(base.dx - n.dx * w * 1.4, base.dy - n.dy * w * 1.4)
    ..lineTo(base.dx - n.dx * w / 2, base.dy - n.dy * w / 2)
    ..lineTo(a.dx - n.dx * w / 2, a.dy - n.dy * w / 2)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
}
