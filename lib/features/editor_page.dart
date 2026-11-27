/// Xếp thế cờ đang có trên bàn thật (để theo dõi một ván đang dở).
library;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../core/chess/position.dart';
import '../core/i18n.dart';
import '../shared/board_view.dart';
import '../shared/ios.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  List<int> _board = List<int>.of(Position.start().board);
  int _side = white;

  /// Quân đang cầm để đặt; 0 = cục tẩy.
  int _pen = piece(white, pawn);

  void _tap(int s) {
    final next = List<int>.of(_board)..[s] = _board[s] == _pen ? 0 : _pen;
    final over = _overSet(next);
    if (over != null) {
      iosToast(context, over);
      return;
    }
    setState(() => _board = next);
  }

  /// Bộ cờ mỗi bên chỉ có 1 vua, 1 hậu, 2 xe, 2 tượng, 2 mã, 8 tốt. Quân vượt số đó chỉ có thể là tốt phong cấp,
  /// nên mỗi quân thừa phải ứng với một tốt đã rời bàn.
  String? _overSet(List<int> b) {
    for (final c in const [white, black]) {
      int count(int t) => b.where((p) => p == piece(c, t)).length;
      final pawns = count(pawn);
      if (count(king) > 1) return 'Mỗi bên chỉ có một vua.'.tr;
      if (pawns > 8) return 'Mỗi bên chỉ có 8 tốt.'.tr;
      var extra = 0;
      for (final (t, base) in const [(queen, 1), (rook, 2), (bishop, 2), (knight, 2)]) {
        if (count(t) > base) extra += count(t) - base;
      }
      if (extra > 8 - pawns) return 'Mỗi bên chỉ có 1 hậu, 2 xe, 2 tượng, 2 mã. Muốn thêm quân phong cấp thì phải bớt tốt.'.tr;
    }
    return null;
  }

  String? _problem() {
    for (final c in const [white, black]) {
      final n = _board.where((p) => p == piece(c, king)).length;
      if (n != 1) return c == white ? 'Cần đúng một vua trắng.'.tr : 'Cần đúng một vua đen.'.tr;
    }
    for (var f = 0; f < 8; f++) {
      if (typeOf(_board[f]) == pawn || typeOf(_board[56 + f]) == pawn) return 'Tốt không thể đứng ở hàng 1 hay hàng 8.'.tr;
    }
    final p = Position.fromBoard(_board, _side ^ 1);
    if (p.inCheck) return 'Bên không tới lượt đang bị chiếu — thế cờ không hợp lệ.'.tr;
    return null;
  }

  void _done() {
    final err = _problem();
    if (err != null) {
      iosToast(context, err);
      return;
    }
    Navigator.pop(context, Position.fromBoard(_board, _side).fen);
  }

  Widget _penButton(int p) {
    final sel = _pen == p;
    return GestureDetector(
      onTap: () => setState(() => _pen = p),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: iosFill(context),
          border: Border.all(color: sel ? iosTint(context) : const Color(0x00000000), width: 3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: p == 0 ? Icon(CupertinoIcons.delete_left, color: iosLabel(context)) : Center(child: PieceIcon(p)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IosPage(
      title: 'Xếp thế cờ'.tr,
      trailing: IosNavButton(label: 'Xong'.tr, bold: true, onPressed: _done),
      board: ClipRRect(borderRadius: BorderRadius.circular(10), child: BoardView(board: _board, onTap: _tap)),
      boardMaxWidth: 500,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          // Hàng trên quân trắng, hàng dưới quân đen và cục tẩy.
          child: Column(children: [
            Wrap(spacing: 6, alignment: WrapAlignment.center, children: [for (var t = king; t >= pawn; t--) _penButton(piece(white, t)), const SizedBox(width: 46)]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, alignment: WrapAlignment.center, children: [for (var t = king; t >= pawn; t--) _penButton(piece(black, t)), _penButton(0)]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
          child: Text('Chọn quân bên dưới rồi chạm ô để đặt; chạm lại để bỏ. Quyền nhập thành được suy ra từ vị trí vua và xe.'.tr,
              textAlign: TextAlign.center, style: tFootnote.copyWith(color: iosLabel2(context))),
        ),
        IosSection(children: [
          IosBlock(
            child: IosSegmented<int>(items: {white: 'Trắng đi'.tr, black: 'Đen đi'.tr}, value: _side, onChanged: (v) => setState(() => _side = v)),
          ),
        ]),
        IosSection(children: [
          IosTile(title: 'Thế khởi đầu'.tr, titleColor: iosTint(context), chevron: false, onTap: () => setState(() => _board = List<int>.of(Position.start().board))),
          IosTile(title: 'Xoá hết'.tr, titleColor: iosRed(context), chevron: false, onTap: () => setState(() => _board = List<int>.filled(64, 0))),
        ]),
      ],
    );
  }
}
