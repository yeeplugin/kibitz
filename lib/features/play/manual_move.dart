/// Nhập một nước đi bằng tay (khi camera không nhận ra, hoặc muốn phong cấp quân khác hậu).
library;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../../core/chess/position.dart';
import '../../core/coach.dart';
import '../../core/i18n.dart';
import '../../shared/board_view.dart';
import '../../shared/ios.dart';

Future<int?> showManualMove(BuildContext context, Position pos) => iosSheet<int>(context, (c) => _ManualMove(pos: pos));

class _ManualMove extends StatefulWidget {
  const _ManualMove({required this.pos});
  final Position pos;

  @override
  State<_ManualMove> createState() => _ManualMoveState();
}

class _ManualMoveState extends State<_ManualMove> {
  int? _from;
  late final _legal = widget.pos.legalMoves();

  Future<void> _tap(int s) async {
    final p = widget.pos;
    if (_from != null) {
      final cands = _legal.where((m) => mFrom(m) == _from && mTo(m) == s).toList();
      if (cands.isNotEmpty) {
        var m = cands.first;
        if (cands.length > 1) {
          final pr = await iosActionSheet<int>(context, title: 'Phong cấp thành'.tr, cancel: 'Huỷ'.tr, actions: {for (final t in const [queen, rook, bishop, knight]) t: pieceNames[t].tr});
          if (pr == null) return;
          m = cands.firstWhere((x) => mPromo(x) == pr);
        }
        if (mounted) Navigator.pop(context, m);
        return;
      }
    }
    setState(() => _from = p.board[s] != 0 && colorOf(p.board[s]) == p.side ? s : null);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pos;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Chạm quân rồi chạm ô đến'.tr, style: tHeadline),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: BoardView(
              board: List<int>.of(p.board),
              flipped: p.side == black,
              selected: _from,
              lastMove: p.lastMove == null ? null : (mFrom(p.lastMove!), mTo(p.lastMove!)),
              targets: {for (final m in _legal) if (mFrom(m) == _from) mTo(m)},
              onTap: _tap,
            ),
          ),
        ]),
      ),
    );
  }
}
