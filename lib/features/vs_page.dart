/// Đánh với máy ngay trên màn hình, không cần camera: chạm quân để đi, máy đáp lại, có gợi ý và chấm nước.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

import '../core/chess/engine.dart';
import '../core/chess/position.dart';
import '../core/coach.dart';
import '../core/i18n.dart';
import '../data/store.dart';
import '../services/analyzer.dart';
import '../services/billing.dart';
import '../shared/board_view.dart';
import '../shared/ios.dart';
import 'pro_page.dart';
import 'record_page.dart';

class VsPage extends StatefulWidget {
  const VsPage({super.key, required this.store, required this.billing});
  final Store store;
  final Billing billing;

  @override
  State<VsPage> createState() => _VsPageState();
}

class _VsPageState extends State<VsPage> {
  Store get store => widget.store;

  Game? _game;
  late int _me = store.vsColor;
  late int _stage = math.min(store.vsStage, _stages.length);

  /// Lựa chọn ở màn bắt đầu ván: 0 trắng, 1 đen, 2 ngẫu nhiên.
  int _pick = 0;

  Position _pos = Position.start();
  int? _sel;

  Analysis? _analysis;
  int _analysisPly = -1;
  bool _byStockfish = false;
  bool _hint = false;
  String? _feedback;
  MoveQuality? _feedbackQ;

  /// Tăng mỗi khi thế cờ đổi: kết quả engine của thế cũ về muộn thì bỏ.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    final g = store.vsGame;
    if (g != null) {
      _game = g;
      _pos = g.position();
      _pick = _me;
      _turn();
    }
  }

  @override
  void dispose() {
    _gen++;
    super.dispose();
  }

  bool get _over => _pos.status() != GameStatus.ongoing;
  bool get _myTurn => _pos.side == _me;

  /// Mình chiếu hết máy.
  bool get _won => _pos.status() == GameStatus.checkmate && _pos.side != _me;

  /// Thắng xong thì sang màn kế tiếp.
  Future<void> _nextStage() async {
    await _newGame();
    if (mounted) setState(() => _stage = math.min(_stage + 1, _stages.length));
  }

  String _stageNote(int n) => switch (n) {
        <= 3 => 'Màn {0}: máy chỉ nhìn trước một nước và hay đi bừa — cho người mới.'.trArgs([n]),
        <= 5 => 'Màn {0}: máy biết ăn quân và tránh mất quân, nhưng bỏ sót đòn hai ba nước.'.trArgs([n]),
        <= 8 => 'Màn {0}: máy nhìn trước vài nước, đánh chắc dần.'.trArgs([n]),
        9 => 'Màn {0}: engine có sẵn nghĩ kỹ từng nước.'.trArgs([n]),
        11 => 'Màn {0}: Stockfish mạnh nhất, nghĩ 10 giây mỗi nước. Cần bản Pro.'.trArgs([n]),
        _ => store.useStockfish ? 'Màn {0}: máy đánh hết sức bằng Stockfish.'.trArgs([n]) : 'Màn {0}: máy đánh hết sức. Bản Pro dùng Stockfish, mạnh hơn nhiều.'.trArgs([n]),
      };

  /// Màn Stockfish cần bản Pro: chưa có thì mở trang nâng cấp.
  /// Các màn chơi được trên máy này: màn Stockfish chỉ có ở nơi có Stockfish.
  List<Stage> get _stages => [for (final s in Stage.all) if (!s.stockfish || Store.stockfishSupported) s];

  bool get _locked => Stage.of(_stage).stockfish && !store.pro;

  Future<void> _start() async {
    if (_locked) {
      await iosPush<void>(context, ProPage(store: store, billing: widget.billing));
      if (!mounted) return;
      setState(() {});
      if (_locked) return;
    }
    final me = _pick == 2 ? math.Random().nextInt(2) : _pick;
    final bot = 'Máy (màn {0})'.trArgs([_stage]);
    final g = Game(whiteName: me == white ? '' : bot, blackName: me == black ? '' : bot);
    await store.saveVs(g, color: me, stage: _stage);
    setState(() {
      _game = g;
      _me = me;
      _pos = g.position();
      _sel = null;
      _analysis = null;
      _hint = false;
      _feedback = null;
      _feedbackQ = null;
    });
    _turn();
  }

  /// Về màn chọn ván mới; ván vừa đánh (nếu có nước đi) được cất vào "Ván đã ghi".
  Future<void> _newGame() async {
    final g = _game;
    _gen++;
    if (g != null && g.moves.isNotEmpty) await store.archive(g);
    await store.saveVs(null);
    if (mounted) setState(() => _game = null);
  }

  /// Tới lượt ai thì làm việc của lượt đó: lượt mình — tính sẵn gợi ý; lượt máy — chấm nước mình vừa đi rồi máy đi.
  Future<void> _turn({({Analysis before, String played})? judgeMove}) async {
    final g = _game!;
    final gen = ++_gen, ply = g.moves.length;
    if (_over) {
      if (_won) await store.markBeaten(_stage);
      if (mounted) setState(() {});
      return;
    }
    final fen = g.startFen, moves = List<String>.of(g.moves);
    final Analysis a;
    final bool by;
    try {
      (a, by) = await analyzePosition(store, fen, moves);
    } catch (_) {
      return;
    }
    if (!mounted || gen != _gen) return;
    setState(() {
      _analysis = a;
      _analysisPly = ply;
      _byStockfish = by;
      if (judgeMove != null) {
        final (q, loss) = judge(judgeMove.before, a, judgeMove.played, _me);
        _feedbackQ = q;
        _feedback = loss >= 30 ? '{0} (mất ~{1} tốt).'.trArgs([q.label, (loss / 100).toStringAsFixed(1)]) : '${q.label}.';
        g.marks[ply - 1] = q.index;
      }
    });
    if (_myTurn) return;
    // Máy đi theo sức của màn đang chơi; engine trục trặc thì lấy nước hay nhất vừa tính.
    var best = a.best;
    try {
      final b = await stageMove(store, fen, moves, Stage.of(_stage));
      if (b.isNotEmpty) best = b;
    } catch (_) {}
    if (!mounted || gen != _gen) return;
    final m = _pos.parseUci(best);
    if (m == null) return;
    _apply(m);
    _turn();
  }

  void _apply(int m) {
    final g = _game!;
    g.moves.add(uci(m));
    _pos = g.position();
    store.saveVs(g);
    HapticFeedback.selectionClick();
    setState(() {
      _sel = null;
      _hint = false;
    });
  }

  Future<void> _tap(int s) async {
    if (_game == null || _over || !_myTurn) return;
    final legal = _pos.legalMoves();
    final from = _sel;
    if (from != null) {
      final cands = legal.where((m) => mFrom(m) == from && mTo(m) == s).toList();
      if (cands.isNotEmpty) {
        var m = cands.first;
        if (cands.length > 1) {
          final pr = await iosActionSheet<int>(context, title: 'Phong cấp thành'.tr, cancel: 'Huỷ'.tr, actions: {for (final t in const [queen, rook, bishop, knight]) t: pieceNames[t].tr});
          if (pr == null || !mounted) return;
          m = cands.firstWhere((x) => mPromo(x) == pr);
        }
        final before = _analysis != null && _analysisPly == _game!.moves.length ? _analysis : null;
        final played = uci(m);
        setState(() {
          _feedback = null;
          _feedbackQ = null;
        });
        _apply(m);
        _turn(judgeMove: before == null ? null : (before: before, played: played));
        return;
      }
    }
    setState(() => _sel = _pos.board[s] != 0 && colorOf(_pos.board[s]) == _me ? s : null);
  }

  /// Lùi về lượt mình gần nhất: bỏ nước của máy và nước của mình trước đó.
  void _undo() {
    final g = _game!;
    var n = _myTurn ? 2 : 1;
    // Mình cầm đen: nước đầu là của máy, không lùi qua nó.
    final first = g.moveNo(0).$2 == _me ? 0 : 1;
    n = math.min(n, g.moves.length - first);
    if (n <= 0) return;
    g.moves.removeRange(g.moves.length - n, g.moves.length);
    g.marks.removeWhere((k, _) => k >= g.moves.length);
    _pos = g.position();
    store.saveVs(g);
    setState(() {
      _sel = null;
      _hint = false;
      _feedback = null;
      _feedbackQ = null;
    });
    _turn();
  }

  bool get _canUndo {
    final g = _game;
    if (g == null) return false;
    return g.moves.length > (g.moveNo(0).$2 == _me ? 0 : 1);
  }

  Analysis? get _fresh => _analysis != null && _analysisPly == _game?.moves.length ? _analysis : null;

  String _status() {
    if (_won) return 'Bạn thắng màn {0}!'.trArgs([_stage]);
    if (_over) return statusText(_pos.status(), _pos.side);
    if (!_myTurn) return 'Máy đang nghĩ…'.tr;
    if (!_hint) return _pos.inCheck ? 'Bạn đang bị chiếu — tới lượt bạn.'.tr : 'Tới lượt bạn.'.tr;
    final a = _fresh;
    final m = a == null ? null : _pos.parseUci(a.best);
    if (m == null) return 'Đang tìm nước hay…'.tr;
    return 'Gợi ý: {0} ({1})'.trArgs([describeMove(_pos, m), _pos.san(m)]);
  }

  Color _qColor(MoveQuality? q) => switch (q) {
        MoveQuality.best || MoveQuality.good => const Color(0xFF2F855A),
        MoveQuality.inaccuracy => const Color(0xFFB7791F),
        MoveQuality.mistake => const Color(0xFFDD6B20),
        MoveQuality.blunder => const Color(0xFFC53030),
        null => iosLabel2(context),
      };

  @override
  Widget build(BuildContext context) {
    final g = _game;
    return IosPage(
      title: 'Đánh với máy'.tr,
      trailing: g == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IosNavButton(
                icon: CupertinoIcons.list_bullet,
                onPressed: () => iosPush<void>(context, RecordPage(game: g, save: () => store.saveVs(g), flipped: _me == black)),
              ),
              IosNavButton(icon: CupertinoIcons.plus, onPressed: _newGame),
            ]),
      board: g == null ? null : _board(g),
      boardAfter: 1,
      children: g == null ? _setup() : _play(g),
    );
  }

  Widget _stageTile(int n) {
    final on = n == _stage, beaten = store.vsBeaten.contains(n);
    final tint = iosTint(context);
    return GestureDetector(
      onTap: () => setState(() => _stage = n),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(color: on ? tint : iosFill(context), borderRadius: BorderRadius.circular(12)),
        child: Stack(children: [
          Center(child: Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: on ? CupertinoColors.white : iosLabel(context)))),
          if (beaten) Positioned(top: 5, right: 5, child: Icon(CupertinoIcons.star_fill, size: 12, color: on ? CupertinoColors.white : const Color(0xFFFFCC00))),
          if (Stage.of(n).stockfish && !store.pro) Positioned(bottom: 5, right: 5, child: Icon(CupertinoIcons.lock_fill, size: 12, color: on ? CupertinoColors.white : iosLabel2(context))),
        ]),
      ),
    );
  }

  List<Widget> _setup() {
    return [
      IosSection(top: 4, header: 'Bạn cầm quân'.tr, children: [
        IosBlock(
          child: IosSegmented<int>(items: {0: 'Trắng'.tr, 1: 'Đen'.tr, 2: 'Ngẫu nhiên'.tr}, value: _pick, onChanged: (v) => setState(() => _pick = v)),
        ),
      ]),
      IosSection(
        header: 'Chọn màn'.tr,
        footer: '${_stageNote(_stage)}\n${'Đã thắng {0}/{1} màn.'.trArgs([store.vsBeaten.where((n) => n <= _stages.length).length, _stages.length])}',
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.05,
              children: [for (final st in _stages) _stageTile(st.no)],
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: IosButton(
          onPressed: _start,
          icon: _locked ? CupertinoIcons.star_fill : CupertinoIcons.play_fill,
          label: _locked ? 'Nâng cấp bản Pro'.tr : 'Bắt đầu'.tr,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 9, 32, 0),
        child: Text('Chạm quân rồi chạm ô đến để đi. Bấm "Gợi ý" khi cần; app chấm từng nước bạn đi.'.tr, textAlign: TextAlign.center, style: tFootnote.copyWith(color: iosLabel2(context))),
      ),
    ];
  }

  Widget _board(Game g) {
    final a = _fresh;
    final best = _hint && _myTurn && a != null && a.best.length >= 4 ? (parseSq(a.best.substring(0, 2)), parseSq(a.best.substring(2, 4))) : null;
    return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BoardView(
            board: List<int>.of(_pos.board),
            flipped: _me == black,
            selected: _sel,
            lastMove: _pos.lastMove == null ? null : (mFrom(_pos.lastMove!), mTo(_pos.lastMove!)),
            targets: {
              if (_sel != null)
                for (final m in _pos.legalMoves())
                  if (mFrom(m) == _sel) mTo(m),
            },
            arrow: best,
            onTap: _tap,
          ),
        );
  }

  List<Widget> _play(Game g) {
    final grey = iosLabel2(context);
    final a = _fresh;
    final sans = g.sans();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text('{0} · màn {1}'.trArgs([_me == white ? 'Bạn cầm trắng'.tr : 'Bạn cầm đen'.tr, _stage]),
            textAlign: TextAlign.center, style: tFootnote.copyWith(color: grey)),
      ),
      IosSection(top: 12, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (!_over && !_myTurn) const Padding(padding: EdgeInsets.only(right: 8), child: CupertinoActivityIndicator(radius: 8)),
              Expanded(child: Text(_status(), style: tHeadline)),
            ]),
            if (_feedback != null) ...[
              const SizedBox(height: 3),
              Text('{0}: {1}'.trArgs(['Nước của bạn'.tr, _feedback]), style: tSubhead.copyWith(color: _qColor(_feedbackQ), fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 10),
            Row(children: [
              SizedBox(width: 52, child: Text(a == null ? '…' : scoreText(a), style: tHeadline)),
              Expanded(child: EvalBar(value: a == null ? 0.5 : (scoreBar(a) + 1) / 2)),
            ]),
            if (a != null)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('{0} · sâu {1}'.trArgs([_byStockfish ? 'Stockfish' : 'Engine có sẵn'.tr, a.depth]), style: tFootnote.copyWith(color: grey))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Text(
            sans.isEmpty ? 'Chưa có nước nào.'.tr : g.moveTokens().join(' '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: tSubhead.copyWith(color: grey, height: 1.4),
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          Expanded(child: IosButton(kind: IosButtonKind.gray, onPressed: _canUndo ? _undo : null, icon: CupertinoIcons.arrow_uturn_left, label: 'Lùi'.tr)),
          const SizedBox(width: 10),
          Expanded(
            child: _over
                ? (_won && _stage < _stages.length
                    ? IosButton(onPressed: _nextStage, icon: CupertinoIcons.arrow_right, label: 'Màn tiếp theo'.tr)
                    : IosButton(onPressed: _newGame, icon: CupertinoIcons.plus, label: 'Ván mới'.tr))
                : IosButton(
                    kind: IosButtonKind.tinted,
                    onPressed: _myTurn && !_hint ? () => setState(() => _hint = true) : null,
                    icon: CupertinoIcons.lightbulb,
                    label: 'Gợi ý'.tr,
                  ),
          ),
        ]),
      ),
    ];
  }
}
