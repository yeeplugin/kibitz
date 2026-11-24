/// Xếp thế cờ đang có trên bàn thật (để theo dõi một ván đang dở).
library;

import 'package:material_ui/material_ui.dart';

import '../core/chess/position.dart';
import '../core/i18n.dart';
import '../shared/board_view.dart';

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

  void _tap(int s) => setState(() => _board[s] = _board[s] == _pen ? 0 : _pen);

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Navigator.pop(context, Position.fromBoard(_board, _side).fen);
  }

  Widget _penButton(int p) {
    final sel = _pen == p;
    return InkWell(
      onTap: () => setState(() => _pen = p),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: sel ? Theme.of(context).colorScheme.primaryContainer : null,
          border: Border.all(color: sel ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: p == 0
            ? const Icon(Icons.backspace_outlined)
            : Center(child: PieceIcon(p)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Xếp thế cờ'.tr), actions: [TextButton(onPressed: _done, child: Text('Xong'.tr))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: BoardView(board: _board, onTap: _tap)),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (final c in const [white, black])
            for (var t = king; t >= pawn; t--) _penButton(piece(c, t)),
          _penButton(0),
        ]),
        const SizedBox(height: 16),
        Center(
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: white, label: Text('Trắng đi'.tr)),
              ButtonSegment(value: black, label: Text('Đen đi'.tr)),
            ],
            selected: {_side},
            onSelectionChanged: (v) => setState(() => _side = v.first),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          OutlinedButton(onPressed: () => setState(() => _board = List<int>.of(Position.start().board)), child: Text('Thế khởi đầu'.tr)),
          OutlinedButton(onPressed: () => setState(() => _board = List<int>.filled(64, 0)), child: Text('Xoá hết'.tr)),
        ]),
        const SizedBox(height: 12),
        Text('Chọn quân bên dưới rồi chạm ô để đặt; chạm lại để bỏ. Quyền nhập thành được suy ra từ vị trí vua và xe.'.tr,
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
