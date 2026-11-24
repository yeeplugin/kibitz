/// Biên bản ván cờ: xem lại từng nước, ghi tên người chơi, xuất PGN; và danh sách các ván đã ghi.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../core/chess/position.dart';
import '../core/coach.dart';
import '../core/i18n.dart';
import '../data/store.dart';
import '../shared/board_view.dart';

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

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pos = game.position(_ply);
    (int, int)? last;
    if (_ply > 0) {
      final u = game.moves[_ply - 1];
      last = (parseSq(u.substring(0, 2)), parseSq(u.substring(2, 4)));
    }
    final empty = _sans.isEmpty;
    final date = gameDate(game);
    return Scaffold(
      appBar: AppBar(
        title: Text('Biên bản ván cờ'.tr),
        actions: [
          PopupMenuButton<int>(
            key: _shareKey,
            tooltip: 'Xuất biên bản'.tr,
            icon: const Icon(Icons.ios_share),
            enabled: !empty,
            onSelected: (v) => switch (v) {
              0 => _share(),
              1 => _copy(game.pgn(), 'Đã sao chép PGN.'.tr),
              _ => _copy(game.moveTokens().join(' '), 'Đã sao chép các nước đi.'.tr),
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 0, child: ListTile(leading: const Icon(Icons.insert_drive_file_outlined), title: Text('Chia sẻ tệp PGN'.tr))),
              PopupMenuItem(value: 1, child: ListTile(leading: const Icon(Icons.copy), title: Text('Sao chép PGN'.tr))),
              PopupMenuItem(value: 2, child: ListTile(leading: const Icon(Icons.short_text), title: Text('Sao chép các nước đi'.tr))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: TextField(controller: _white, onChanged: (_) => _names(), decoration: InputDecoration(labelText: 'Trắng'.tr, hintText: 'Tên người chơi'.tr, isDense: true, border: const OutlineInputBorder()))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _black, onChanged: (_) => _names(), decoration: InputDecoration(labelText: 'Đen'.tr, hintText: 'Tên người chơi'.tr, isDense: true, border: const OutlineInputBorder()))),
                ]),
                const SizedBox(height: 8),
                Text(
                  [if (date.isNotEmpty) date, '{0} nước'.trArgs([_sans.length]), resultText(game)].join(' · '),
                  key: const ValueKey('info'),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: IgnorePointer(child: BoardView(board: List<int>.of(pos.board), flipped: widget.flipped, lastMove: last)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _ply == 0 ? 'Thế ban đầu'.tr : '${game.moveTokens().isEmpty ? '' : _label(_ply - 1)}   ($_ply / ${_sans.length})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(tooltip: 'Về đầu ván'.tr, onPressed: _ply == 0 ? null : () => _go(0), icon: const Icon(Icons.first_page)),
                  IconButton(tooltip: 'Nước trước'.tr, onPressed: _ply == 0 ? null : () => _go(_ply - 1), icon: const Icon(Icons.chevron_left)),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: _playing ? 'Tạm dừng'.tr : 'Phát lại ván cờ'.tr,
                    onPressed: empty ? null : _togglePlay,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  ),
                  const SizedBox(width: 4),
                  IconButton(tooltip: 'Nước sau'.tr, onPressed: _ply == _sans.length ? null : () => _go(_ply + 1), icon: const Icon(Icons.chevron_right)),
                  IconButton(tooltip: 'Tới cuối ván'.tr, onPressed: _ply == _sans.length ? null : () => _go(_sans.length), icon: const Icon(Icons.last_page)),
                ]),
                const SizedBox(height: 4),
                if (empty)
                  Padding(padding: const EdgeInsets.all(16), child: Text('Chưa có nước nào.'.tr, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)))
                else
                  Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: _rows(cs)))),
                if (game.marks.values.any((q) => q >= 2)) ...[
                  const SizedBox(height: 8),
                  Text('Màu cam, đỏ: nước engine chấm là chưa chính xác hoặc sai lầm.'.tr, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: empty ? null : _share,
                  icon: const Icon(Icons.ios_share),
                  label: Text('Chia sẻ tệp PGN'.tr),
                ),
                const SizedBox(height: 6),
                Text('Tệp PGN mở được bằng Lichess, Chess.com và các phần mềm cờ vua khác.'.tr,
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// "3. Nf3" hoặc "3… d6" cho nước thứ [i].
  String _label(int i) {
    final (no, side) = game.moveNo(i);
    return '$no${side == white ? '.' : '…'} ${_sans[i]}';
  }

  /// Mỗi dòng một nước đủ: số thứ tự, nước trắng, nước đen.
  List<Widget> _rows(ColorScheme cs) {
    Widget cell(int? i) {
      if (i == null || i < 0 || i >= _sans.length) return const Expanded(child: SizedBox());
      final on = _ply == i + 1;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _go(i + 1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(color: on ? cs.primaryContainer : null, borderRadius: BorderRadius.circular(6)),
            child: Text(_sans[i], style: TextStyle(fontSize: 16, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: qualityColor(game.marks[i]) ?? (on ? cs.onPrimaryContainer : null))),
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          SizedBox(width: 40, child: Text('${game.moveNo(b < _sans.length ? b : w).$1}.', style: TextStyle(color: cs.onSurfaceVariant))),
          cell(w < 0 ? null : w),
          const SizedBox(width: 6),
          cell(b),
        ]),
      ));
    }
    return rows;
  }
}

/// Danh sách các ván đã ghi.
class GamesPage extends StatelessWidget {
  const GamesPage({super.key, required this.store});
  final Store store;

  Future<void> _delete(BuildContext context, List<Game> all, Game g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Xoá ván này?'.tr),
        content: Text('Biên bản "{0}" ({1} nước) sẽ bị xoá hẳn.'.trArgs([gameTitle(g), g.moves.length])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Huỷ'.tr)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Xoá'.tr)),
        ],
      ),
    );
    if (ok == true) await store.saveHistory([...all.where((o) => o.startedAt != g.startedAt)]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final all = store.history;
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: Text('Ván đã ghi'.tr)),
          body: all.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Chưa có ván nào. Ván đang chơi được cất vào đây khi bạn bắt đầu ván khác.'.tr, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: all.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final g = all[i];
                    final date = gameDate(g);
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                        leading: SizedBox(width: 56, height: 56, child: IgnorePointer(child: BoardView(board: List<int>.of(g.position().board)))),
                        title: Text(gameTitle(g)),
                        subtitle: Text([if (date.isNotEmpty && gameTitle(g) != date) date, '{0} nước'.trArgs([g.moves.length]), resultText(g)].join(' · ')),
                        trailing: IconButton(tooltip: 'Xoá'.tr, icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, all, g)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(builder: (_) => RecordPage(game: g, save: () => store.saveHistory(all))),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
