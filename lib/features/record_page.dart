/// Biên bản ván cờ: xem lại từng nước, ghi tên người chơi, xuất PGN; và danh sách các ván đã ghi.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../core/chess/position.dart';
import '../core/coach.dart';
import '../core/i18n.dart';
import '../data/store.dart';
import '../shared/board_view.dart';
import '../shared/ios.dart';

String _two(int v) => v.toString().padLeft(2, '0');

/// "23/11/2026 14:05"; ván lưu từ bản cũ không có ngày.
String gameDate(Game g) {
  final d = g.startedAt;
  if (d.millisecondsSinceEpoch == 0) return '';
  return '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

String gameTitle(Game g) {
  final w = g.whiteName.trim(), b = g.blackName.trim();
  if (w.isEmpty && b.isEmpty) return gameDate(g).isEmpty ? 'Ván cờ'.tr : gameDate(g);
  return '${w.isEmpty ? 'Trắng'.tr : w} – ${b.isEmpty ? 'Đen'.tr : b}';
}

String resultText(Game g) => switch (g.result) {
      '1-0' => 'Trắng thắng'.tr,
      '0-1' => 'Đen thắng'.tr,
      '1/2-1/2' => 'Hoà'.tr,
      _ => 'Chưa xong'.tr,
    };

Color? qualityColor(int? q) => switch (q) {
      2 => const Color(0xFFB7791F),
      3 => const Color(0xFFDD6B20),
      4 => const Color(0xFFC53030),
      _ => null,
    };

class RecordPage extends StatefulWidget {
  const RecordPage({super.key, required this.game, required this.save, this.flipped = false});
  final Game game;

  /// Lưu lại sau khi sửa tên người chơi.
  final Future<void> Function() save;
  final bool flipped;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  Game get game => widget.game;
  late final _sans = game.sans();
  late int _ply = _sans.length;
  late final _white = TextEditingController(text: game.whiteName);
  late final _black = TextEditingController(text: game.blackName);
  final _shareKey = GlobalKey();

  /// Đang tự phát lại ván cờ: mỗi nhịp đi thêm một nước.
  Timer? _player;
  bool get _playing => _player != null;

  void _stop() {
    _player?.cancel();
    _player = null;
  }

  /// Phát / tạm dừng. Đang ở cuối ván thì phát lại từ đầu.
  void _togglePlay() {
    if (_playing) {
      setState(_stop);
      return;
    }
    setState(() {
      if (_ply >= _sans.length) _ply = 0;
      _player = Timer.periodic(const Duration(milliseconds: 1100), (_) {
        if (!mounted) return;
        setState(() {
          if (_ply < _sans.length) _ply++;
          if (_ply >= _sans.length) _stop();
        });
      });
    });
  }

  /// Người dùng tự chọn nước: dừng phát.
  void _go(int ply) => setState(() {
        _stop();
        _ply = ply;
      });

  @override
  void dispose() {
    _player?.cancel();
    _white.dispose();
    _black.dispose();
    super.dispose();
  }

  void _names() {
    game.whiteName = _white.text;
    game.blackName = _black.text;
    widget.save();
  }

  String get _fileName {
    final d = game.startedAt;
    final stamp = d.millisecondsSinceEpoch == 0 ? '' : '-${d.year}${_two(d.month)}${_two(d.day)}-${_two(d.hour)}${_two(d.minute)}';
    return 'van-co$stamp.pgn';
  }

  Future<void> _share() async {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(utf8.encode(game.pgn()), name: _fileName, mimeType: 'application/x-chess-pgn')],
        fileNameOverrides: [_fileName],
        sharePositionOrigin: origin,
      ));
    } catch (_) {
      if (mounted) _snack('Không mở được bảng chia sẻ.'.tr);
    }
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _snack(done);
  }

  void _snack(String s) => iosToast(context, s);

  Future<void> _export() async {
    final v = await iosActionSheet<int>(context, title: 'Xuất biên bản'.tr, cancel: 'Huỷ'.tr, actions: {
      0: 'Chia sẻ tệp PGN'.tr,
      1: 'Sao chép PGN'.tr,
      2: 'Sao chép các nước đi'.tr,
    });
    switch (v) {
      case 0:
        await _share();
      case 1:
        await _copy(game.pgn(), 'Đã sao chép PGN.'.tr);
      case 2:
        await _copy(game.moveTokens().join(' '), 'Đã sao chép các nước đi.'.tr);
    }
  }

  Widget _nameField(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          SizedBox(width: 64, child: Text(label, style: tBody)),
          Expanded(
            child: CupertinoTextField(
              controller: c,
              onChanged: (_) => _names(),
              placeholder: 'Tên người chơi'.tr,
              decoration: null,
              padding: const EdgeInsets.symmetric(vertical: 12),
              style: tBody.copyWith(color: iosLabel(context)),
              clearButtonMode: OverlayVisibilityMode.editing,
              textInputAction: TextInputAction.done,
            ),
          ),
        ]),
      );

  Widget _step(IconData icon, String tip, VoidCallback? onPressed, {double size = 24}) => Semantics(
        label: tip,
        button: true,
        child: CupertinoButton(padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(44, 44), onPressed: onPressed, child: Icon(icon, size: size)),
      );

  @override
  Widget build(BuildContext context) {
    final grey = iosLabel2(context);
    final pos = game.position(_ply);
    (int, int)? last;
    if (_ply > 0) {
      final u = game.moves[_ply - 1];
      last = (parseSq(u.substring(0, 2)), parseSq(u.substring(2, 4)));
    }
    final empty = _sans.isEmpty;
    final date = gameDate(game);
    return IosPage(
      title: 'Biên bản ván cờ'.tr,
      board: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: IgnorePointer(child: BoardView(board: List<int>.of(pos.board), flipped: widget.flipped, lastMove: last)),
      ),
      boardAfter: 2,
      boardMaxWidth: 360,
      trailing: KeyedSubtree(key: _shareKey, child: IosNavButton(icon: CupertinoIcons.share, onPressed: empty ? null : _export)),
      children: [
        IosSection(
          top: 0,
          dividerIndent: 80,
          footer: [if (date.isNotEmpty) date, '{0} nước'.trArgs([_sans.length]), resultText(game)].join(' · '),
          children: [_nameField(_white, 'Trắng'.tr), _nameField(_black, 'Đen'.tr)],
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 10),
        Text(
          _ply == 0 ? 'Thế ban đầu'.tr : '${game.moveTokens().isEmpty ? '' : _label(_ply - 1)}   ($_ply / ${_sans.length})',
          textAlign: TextAlign.center,
          style: tHeadline,
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _step(CupertinoIcons.backward_end_fill, 'Về đầu ván'.tr, _ply == 0 ? null : () => _go(0)),
          _step(CupertinoIcons.chevron_left, 'Nước trước'.tr, _ply == 0 ? null : () => _go(_ply - 1)),
          _step(_playing ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill, _playing ? 'Tạm dừng'.tr : 'Phát lại ván cờ'.tr, empty ? null : _togglePlay, size: 44),
          _step(CupertinoIcons.chevron_right, 'Nước sau'.tr, _ply == _sans.length ? null : () => _go(_ply + 1)),
          _step(CupertinoIcons.forward_end_fill, 'Tới cuối ván'.tr, _ply == _sans.length ? null : () => _go(_sans.length)),
        ]),
        if (empty)
          Padding(padding: const EdgeInsets.all(16), child: Text('Chưa có nước nào.'.tr, textAlign: TextAlign.center, style: tSubhead.copyWith(color: grey)))
        else
          IosSection(
            top: 8,
            dividerIndent: 52,
            footer: game.marks.values.any((q) => q >= 2) ? 'Màu cam, đỏ: nước engine chấm là chưa chính xác hoặc sai lầm.'.tr : null,
            children: _rows(),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
          child: IosButton(label: 'Chia sẻ tệp PGN'.tr, icon: CupertinoIcons.share, onPressed: empty ? null : _share),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 9, 32, 0),
          child: Text('Tệp PGN mở được bằng Lichess, Chess.com và các phần mềm cờ vua khác.'.tr, textAlign: TextAlign.center, style: tFootnote.copyWith(color: grey)),
        ),
      ],
    );
  }

  /// "3. Nf3" hoặc "3… d6" cho nước thứ [i].
  String _label(int i) {
    final (no, side) = game.moveNo(i);
    return '$no${side == white ? '.' : '…'} ${_sans[i]}';
  }

  /// Mỗi dòng một nước đủ: số thứ tự, nước trắng, nước đen.
  List<Widget> _rows() {
    final tint = iosTint(context);
    Widget cell(int? i) {
      if (i == null || i < 0 || i >= _sans.length) return const Expanded(child: SizedBox());
      final on = _ply == i + 1;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _go(i + 1),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: on ? tint.withValues(alpha: 0.15) : null, borderRadius: BorderRadius.circular(8)),
            child: Text(_sans[i], style: tBody.copyWith(fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: qualityColor(game.marks[i]) ?? (on ? tint : iosLabel(context)))),
          ),
        ),
      );
    }

    final rows = <Widget>[];
    // Ván xếp sẵn có thể bắt đầu từ lượt đen: dòng đầu để trống ô trắng.
    final offset = game.moveNo(0).$2 == black ? 1 : 0;
    for (var h = 0; h < _sans.length + offset; h += 2) {
      final w = h - offset, b = h + 1 - offset;
      rows.add(Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(children: [
          SizedBox(width: 36, child: Text('${game.moveNo(b < _sans.length ? b : w).$1}.', style: tSubhead.copyWith(color: iosLabel2(context)))),
          cell(w < 0 ? null : w),
          const SizedBox(width: 6),
          cell(b),
        ]),
      ));
    }
    return rows;
  }
}

/// Tab danh sách các ván đã ghi. Vuốt một dòng sang trái để xoá.
class GamesPage extends StatelessWidget {
  const GamesPage({super.key, required this.store});
  final Store store;

  Future<bool> _confirmDelete(BuildContext context, Game g) => iosConfirm(
        context,
        title: 'Xoá ván này?'.tr,
        message: 'Biên bản "{0}" ({1} nước) sẽ bị xoá hẳn.'.trArgs([gameTitle(g), g.moves.length]),
        ok: 'Xoá'.tr,
        cancel: 'Huỷ'.tr,
        destructive: true,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final all = store.history;
        return IosPage(
          large: true,
          title: 'Ván đã ghi'.tr,
          children: [
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 120, 40, 0),
                child: Column(children: [
                  Icon(CupertinoIcons.clock, size: 52, color: iosLabel3(context)),
                  const SizedBox(height: 14),
                  Text('Chưa có ván nào.'.tr, textAlign: TextAlign.center, style: tTitle2),
                  const SizedBox(height: 6),
                  Text('Ván đang chơi được cất vào đây khi bạn bắt đầu ván khác.'.tr, textAlign: TextAlign.center, style: tSubhead.copyWith(color: iosLabel2(context))),
                ]),
              )
            else
              IosSection(top: 6, dividerIndent: 84, footer: 'Vuốt sang trái để xoá một ván.'.tr, children: [
                for (final g in all)
                  Dismissible(
                    key: ValueKey(g.startedAt.microsecondsSinceEpoch),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _confirmDelete(context, g),
                    onDismissed: (_) => store.saveHistory([...all.where((o) => o.startedAt != g.startedAt)]),
                    background: Container(
                      color: iosRed(context),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 22),
                      child: const Icon(CupertinoIcons.trash_fill, color: CupertinoColors.white, size: 22),
                    ),
                    child: ColoredBox(
                      color: iosCellBg(context),
                      child: IosTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: SizedBox(width: 56, height: 56, child: IgnorePointer(child: BoardView(board: List<int>.of(g.position().board)))),
                        ),
                        title: gameTitle(g),
                        subtitle: [if (gameDate(g).isNotEmpty && gameTitle(g) != gameDate(g)) gameDate(g), '{0} nước'.trArgs([g.moves.length]), resultText(g)].join(' · '),
                        onTap: () => iosPush<void>(context, RecordPage(game: g, save: () => store.saveHistory(all))),
                      ),
                    ),
                  ),
              ]),
          ],
        );
      },
    );
  }
}
