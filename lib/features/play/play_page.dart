/// Màn chơi: căn bàn cờ trong khung hình, rồi theo dõi nước đi trên bàn thật và gợi ý nước tiếp theo.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/chess/engine.dart';
import '../../core/chess/position.dart';
import '../../core/coach.dart';
import '../../core/i18n.dart';
import '../../core/vision/board.dart';
import '../../core/vision/classifier.dart';
import '../../core/vision/image.dart';
import '../../core/vision/tracker.dart';
import '../../data/store.dart';
import '../../services/analyzer.dart';
import '../../shared/board_view.dart';
import 'frame_source.dart';
import 'manual_move.dart';
import '../record_page.dart';
import 'overlay.dart';

// Việc nặng chạy trong isolate qua hàm top-level: closure trong phương thức của State sẽ kéo theo cả State
// (không gửi sang isolate được).
Future<(List<double>, int)?> _findInIsolate(RgbImage img, List<int> board) => Isolate.run(() {
      final g = findBoard(img);
      return g == null ? null : (g.toList(), guessRotation(img, g, board));
    });

/// Lưới của ảnh chụp lại: tìm bàn trong ảnh mới, nhận nếu nó nằm gần lưới cũ [grid] (giữ nguyên thứ tự góc để hướng
/// bàn không đổi); không thì dò quanh lưới cũ.
Future<List<double>> _refineInIsolate(RgbImage img, List<double> grid) => Isolate.run(() {
      final g = BoardGrid.fromList(grid);
      final cell = math.sqrt(g.area) / 8;
      final found = findBoard(img);
      if (found != null) {
        var bestShift = 0, bestErr = double.infinity;
        for (var sh = 0; sh < 4; sh++) {
          var e = 0.0;
          for (var i = 0; i < 4; i++) {
            e = math.max(e, found.corners[(i + sh) % 4].dist(g.corners[i]));
          }
          if (e < bestErr) {
            bestErr = e;
            bestShift = sh;
          }
        }
        if (bestErr < 2.5 * cell) return BoardGrid([for (var i = 0; i < 4; i++) found.corners[(i + bestShift) % 4]]).toList();
      }
      return refineGrid(img, g, startStep: cell / 3, shifts: false).toList();
    });

class PlayPage extends StatefulWidget {
  const PlayPage({super.key, required this.store, required this.game});
  final Store store;
  final Game game;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> with WidgetsBindingObserver {
  Store get store => widget.store;
  Game get game => widget.game;

  FrameSource? _src;
  StreamSubscription<RgbImage>? _sub;
  String? _camError;
  bool _camDenied = false;

  final _frame = ValueNotifier<RgbImage?>(null);
  BoardGrid? _grid;
  int _rot = 0;
  int? _drag;
  bool _finding = false;

  bool _tracking = false;
  SquareClassifier? _cl;
  Tracker? _tr;
  TrackUpdate? _upd;
  int _stableN = 0;

  Analysis? _analysis;
  int _analysisPly = -1;
  bool _thinking = false;

  /// Phân tích gần nhất do Stockfish tính (false: engine có sẵn).
  bool _byStockfish = false;
  bool _hintShown = false;
  ({Analysis before, String played, int mover})? _pendingJudge;
  String? _feedback;
  MoveQuality? _feedbackQ;
  bool _simAuto = true;
  Timer? _simTimer;

  late Position _pos = game.position();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openSource();
    _analyze();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _simTimer?.cancel();
    _sub?.cancel();
    _src?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_src is! CameraSource) return;
    if (state == AppLifecycleState.paused) {
      _sub?.cancel();
      _src?.dispose();
      _src = null;
    } else if (state == AppLifecycleState.resumed && _src == null) {
      _openSource();
    }
  }

  Future<void> _openSource() async {
    await _sub?.cancel();
    await _src?.dispose();
    final FrameSource src = store.simulate ? SimSource(_pos) : CameraSource(portrait: () => mounted && MediaQuery.of(context).orientation == Orientation.portrait);
    setState(() {
      _src = src;
      _camError = null;
      _frame.value = null;
    });
    try {
      await src.start();
    } on CameraUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _camDenied = e.denied;
        _camError = e.denied ? 'Chưa có quyền dùng camera.'.tr : 'Không mở được camera trên máy này.'.tr;
      });
      return;
    }
    final saved = store.calibration(src.id);
    if (saved != null) {
      _grid = saved.$1;
      _rot = saved.$2;
    }
    _sub = src.frames.listen(_onFrame);
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- ảnh tĩnh

  ImageSource _lastPick = ImageSource.gallery;

  /// Lấy một ảnh bàn cờ (thư viện hoặc chụp) làm nguồn hình. Đang theo dõi thì ảnh mới được coi là bàn sau nước
  /// đi tiếp theo: lưới được dò lại quanh chỗ cũ vì hai lần chụp cầm tay không trùng khít.
  Future<void> _pickPhoto(ImageSource from) async {
    _lastPick = from;
    final XFile? f;
    try {
      f = await ImagePicker().pickImage(source: from, maxWidth: 2400, imageQuality: 92);
    } catch (_) {
      if (mounted) _snack(from == ImageSource.camera ? 'Không mở được camera trên máy này.'.tr : 'Không mở được thư viện ảnh.'.tr);
      return;
    }
    if (f == null || !mounted) return;
    final ui.Image display;
    final RgbImage img;
    try {
      (display, img) = await PhotoSource.decode(await f.readAsBytes());
    } catch (_) {
      if (mounted) _snack('Không đọc được ảnh này.'.tr);
      return;
    }
    if (!mounted) return;
    var src = _src;
    if (src is! PhotoSource) {
      _simTimer?.cancel();
      await _sub?.cancel();
      await _src?.dispose();
      final ps = PhotoSource();
      await ps.start();
      src = ps;
      setState(() {
        _src = ps;
        _camError = null;
        _tracking = false;
        _cl = null;
        _tr = null;
        _grid = null;
        _frame.value = null;
      });
      _sub = ps.frames.listen(_onFrame);
    }
    final old = src.current, g = _grid;
    if (_tracking && g != null && old != null) {
      // Co giãn lưới theo cỡ ảnh mới rồi dò lại cho khớp ô.
      final kx = img.width / old.width, ky = img.height / old.height;
      final scaled = BoardGrid([for (final c in g.corners) Pt(c.x * kx, c.y * ky)]);
      setState(() => _finding = true);
      List<double>? refined;
      try {
        refined = await _refineInIsolate(img, scaled.toList());
      } catch (_) {}
      if (!mounted) return;
      final ng = refined == null ? scaled : BoardGrid.fromList(refined);
      _cl?.regrid(ng, img.width, img.height);
      setState(() {
        _finding = false;
        _grid = ng;
      });
      src.show(display, img);
    } else {
      setState(() => _grid = null);
      src.show(display, img);
      _onFrame(img);
      await _autoFind();
    }
  }

  Future<void> _backToLive() async {
    _recalibrate();
    _grid = null;
    await _openSource();
  }

  // ---------------------------------------------------------------- khung hình

  void _onFrame(RgbImage img) {
    if (!mounted) return;
    final first = _frame.value == null || _frame.value!.width != img.width || _frame.value!.height != img.height;
    _frame.value = img;
    if (first) {
      final g = _grid;
      if (g == null || g.corners.any((p) => p.x < 0 || p.y < 0 || p.x > img.width || p.y > img.height)) {
        // Khung mặc định: hình vuông giữa ảnh.
        final s = img.width * 0.8, x0 = (img.width - s) / 2, y0 = (img.height - s) / 2;
        _grid = BoardGrid([Pt(x0, y0), Pt(x0 + s, y0), Pt(x0 + s, y0 + s), Pt(x0, y0 + s)]);
      }
      setState(() {});
    }
    final cl = _cl, tr = _tr, g = _grid;
    if (!_tracking || cl == null || tr == null || g == null) return;
    final u = tr.update(cl.observe(img));
    if (u.state == TrackState.stable && ++_stableN % 12 == 0) cl.adapt(img, tr.pos.board);
    if (u.state == TrackState.moved) {
      _onMoves(u.moves);
    } else if (u.state != _upd?.state || u.mismatch.length != (_upd?.mismatch.length ?? 0)) {
      setState(() => _upd = u);
    } else {
      _upd = u;
    }
  }

  // ---------------------------------------------------------------- căn chỉnh

  Future<void> _autoFind() async {
    final img = _frame.value;
    if (img == null || _finding) return;
    setState(() => _finding = true);
    (List<double>, int)? res;
    try {
      res = await _findInIsolate(img, List<int>.of(_pos.board));
    } catch (_) {
      res = null;
    }
    if (!mounted) return;
    setState(() {
      _finding = false;
      if (res != null) {
        _grid = BoardGrid.fromList(res.$1);
        _rot = res.$2;
      }
    });
    if (res == null) _snack('Không thấy bàn cờ. Hãy đưa cả bàn vào khung hình, đủ sáng, rồi kéo 4 góc cho khớp.'.tr);
  }

  Future<void> _startTracking() async {
    final img = _frame.value, g = _grid;
    if (img == null || g == null) return;
    final cl = SquareClassifier.calibrate(img, g, _rot, _pos.board);
    if (cl == null) {
      _snack('Không đọc được các ô. Kiểm tra lại 4 góc lưới.'.tr);
      return;
    }
    final odd = (cl.observe(img)..setBase(_pos.board)).odd();
    if (odd.length > 3) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Bàn thật chưa khớp'.tr),
          content: Text('Có {0} ô trên bàn thật trông khác thế cờ trong app ({1}). Kiểm tra lưới, hướng bàn và cách xếp quân.'
              .trArgs([odd.length, odd.take(6).map(sqName).join(', ')])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Chỉnh lại'.tr)),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Vẫn bắt đầu'.tr)),
          ],
        ),
      );
      if (go != true) return;
    }
    await store.saveCalibration(_src!.id, g, _rot);
    if (cl.elevation < 30) _snack('Camera đang nhìn quá ngang (khoảng {0}°). Nâng máy cao hơn để quân không che nhau.'.trArgs([cl.elevation.round()]));
    setState(() {
      _cl = cl;
      _tr = Tracker(game.position());
      _tracking = true;
      _upd = null;
    });
    _maybeSimOpponent();
  }

  void _recalibrate() {
    _simTimer?.cancel();
    setState(() {
      _tracking = false;
      _cl = null;
      _tr = null;
    });
  }

  /// Dời cả lưới đi một ô (khi lưới khớp ô nhưng lệch mất một hàng hay một cột).
  void _nudge(int du, int dv) {
    final g = _grid;
    if (g == null) return;
    final n = BoardGrid([g.at(du + 0.0, dv + 0.0), g.at(du + 8.0, dv + 0.0), g.at(du + 8.0, dv + 8.0), g.at(du + 0.0, dv + 8.0)]);
    if (n.valid) setState(() => _grid = n);
  }

  Offset _scale(Size box) {
    final img = _frame.value!;
    return Offset(box.width / img.width, box.height / img.height);
  }

  void _panStart(Offset local, Size box) {
    final g = _grid;
    if (g == null || _tracking) return;
    final k = _scale(box);
    var best = -1;
    var bd = 48.0;
    for (var i = 0; i < 4; i++) {
      final d = (Offset(g.corners[i].x * k.dx, g.corners[i].y * k.dy) - local).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    _drag = best < 0 ? null : best;
  }

  void _panUpdate(Offset local, Size box) {
    final i = _drag, g = _grid;
    if (i == null || g == null) return;
    final k = _scale(box);
    final next = g.moved(i, Pt(local.dx / k.dx, local.dy / k.dy));
    if (next.valid) setState(() => _grid = next);
  }

  // ---------------------------------------------------------------- ván cờ

  bool get _myTurn => store.side.coaches(_pos.side);

  /// Chỉ ghi biên bản: không phân tích, không gợi ý.
  bool get _recordOnly => store.side == Side.none;

  void _onMoves(List<int> moves) {
    final before = _analysis != null && _analysisPly == game.moves.length ? _analysis : null;
    final mover = _pos.side;
    for (final m in moves) {
      game.moves.add(uci(m));
    }
    _pos = game.position();
    store.saveGame(game);
    HapticFeedback.mediumImpact();
    // Chỉ chấm nước của bên được gợi ý.
    final mine = store.side.coaches(mover);
    _pendingJudge = before != null && moves.length == 1 && mine ? (before: before, played: uci(moves.first), mover: mover) : null;
    setState(() {
      _upd = null;
      _hintShown = false;
      // Lời chấm nước của mình được giữ lại khi đối thủ đi; chỉ xoá khi tới lượt mình đi nước mới.
      if (_pendingJudge != null || moves.length > 1) {
        _feedback = null;
        _feedbackQ = null;
      }
      if (moves.length > 1) _feedback = 'Đã nhận 2 nước liền: {0}.'.trArgs([moves.map(uci).join(', ')]);
    });
    _analyze();
  }

  Future<void> _analyze() async {
    final ply = game.moves.length;
    if (_recordOnly || _pos.status() != GameStatus.ongoing) {
      setState(() {
        _analysis = null;
        _thinking = false;
      });
      return;
    }
    setState(() => _thinking = true);
    final fen = game.startFen, moves = List<String>.of(game.moves);
    final Analysis a;
    try {
      final bool by;
      (a, by) = await analyzePosition(store, fen, moves);
      _byStockfish = by;
    } catch (_) {
      if (mounted) setState(() => _thinking = false);
      return;
    }
    if (!mounted || ply != game.moves.length) return;
    final j = _pendingJudge;
    _pendingJudge = null;
    setState(() {
      _analysis = a;
      _analysisPly = ply;
      _thinking = false;
      if (j != null) {
        final (q, loss) = judge(j.before, a, j.played, j.mover);
        _feedbackQ = q;
        game.marks[ply - 1] = q.index;
        store.saveGame(game);
        final who = j.mover == white ? 'Trắng'.tr : 'Đen'.tr;
        _feedback = loss >= 30 ? '{0}: {1} (mất ~{2} tốt).'.trArgs([who, q.label, (loss / 100).toStringAsFixed(1)]) : '{0}: {1}.'.trArgs([who, q.label]);
      }
    });
    _maybeSimOpponent();
  }

  /// Chế độ mô phỏng: tự đi thay đối thủ (bên không được gợi ý) trên bàn "thật".
  void _maybeSimOpponent() {
    final src = _src;
    final a = _analysis;
    if (src is! SimSource || !_simAuto || !_tracking || _myTurn || a == null || _analysisPly != game.moves.length) return;
    _simTimer?.cancel();
    _simTimer = Timer(const Duration(milliseconds: 900), () {
      final m = src.real.parseUci(a.best);
      if (m != null && mounted && src.real.fen == _pos.fen) src.play(m);
    });
  }

  Future<void> _undo() async {
    if (game.moves.isEmpty) return;
    game.moves.removeLast();
    game.marks.removeWhere((k, _) => k >= game.moves.length);
    _pos = game.position();
    await store.saveGame(game);
    _tr = Tracker(game.position());
    final src = _src;
    if (src is SimSource) await src.setPosition(_pos);
    setState(() {
      _feedback = 'Đã lùi một nước. Đặt lại quân trên bàn thật cho giống.'.tr;
      _feedbackQ = null;
      _upd = null;
    });
    _analyze();
  }

  Future<void> _manual() async {
    final m = await showManualMove(context, _pos);
    if (m == null || !mounted) return;
    final src = _src;
    if (src is SimSource && src.real.fen == _pos.fen) {
      final pm = src.real.parseUci(uci(m));
      if (pm != null) src.real.make(pm);
      await src.setPosition(src.real);
    }
    _tr?.pos.make(m);
    _onMoves([m]);
  }

  /// Chạm bàn nhỏ ở chế độ mô phỏng = đi quân trên bàn "thật".
  int? _simSel;
  void _simTap(int s) {
    final src = _src;
    if (src is! SimSource) return;
    final real = src.real;
    if (_simSel == null) {
      if (real.board[s] != 0 && colorOf(real.board[s]) == real.side) setState(() => _simSel = s);
      return;
    }
    final m = real.findMove(_simSel!, s);
    setState(() => _simSel = null);
    if (m != null) {
      src.play(m);
    } else if (real.board[s] != 0 && colorOf(real.board[s]) == real.side) {
      setState(() => _simSel = s);
    }
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  // ---------------------------------------------------------------- giao diện

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_tracking ? 'Theo dõi'.tr : 'Căn bàn cờ'.tr),
        actions: [
          if (_tracking)
            IconButton(
              tooltip: store.drawnBoard ? 'Xem hình camera'.tr : 'Xem bàn cờ vẽ'.tr,
              icon: Icon(store.drawnBoard ? Icons.videocam_outlined : Icons.grid_on),
              onPressed: () async {
                await store.setDrawnBoard(!store.drawnBoard);
                if (mounted) setState(() {});
              },
            ),
          IconButton(
            tooltip: 'Biên bản ván cờ'.tr,
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => RecordPage(game: game, save: () => store.saveGame(game), flipped: store.side == Side.black)),
            ),
          ),
          if (_tracking) IconButton(tooltip: 'Căn lại'.tr, icon: const Icon(Icons.crop_free), onPressed: _recalibrate),
          PopupMenuButton<int>(
            tooltip: 'Ảnh bàn cờ'.tr,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onSelected: (v) => switch (v) { 0 => _pickPhoto(ImageSource.gallery), 1 => _pickPhoto(ImageSource.camera), _ => _backToLive() },
            itemBuilder: (_) => [
              PopupMenuItem(value: 0, child: ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text('Chọn ảnh bàn cờ'.tr))),
              PopupMenuItem(value: 1, child: ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text('Chụp ảnh bàn cờ'.tr))),
              if (_src is PhotoSource)
                PopupMenuItem(
                  value: 2,
                  child: ListTile(leading: const Icon(Icons.videocam_outlined), title: Text(store.simulate ? 'Về bàn cờ mô phỏng'.tr : 'Về camera trực tiếp'.tr)),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > c.maxHeight * 1.1;
          // Đang theo dõi: màn hình chính là bàn cờ app tự vẽ lại từ thế cờ đã nhận diện, hoặc hình camera.
          final view = _tracking && store.drawnBoard ? _bigBoard() : _view();
          final panel = Material(color: Theme.of(context).colorScheme.surface, child: _tracking ? _trackPanel() : _calibratePanel());
          if (wide) {
            return Row(children: [Expanded(child: view), SizedBox(width: 380, child: panel)]);
          }
          return Column(children: [Expanded(child: view), panel]);
        }),
      ),
    );
  }

  /// Bàn cờ vẽ lại theo thế cờ đang biết (ở chế độ mô phỏng: theo bàn "thật" và chạm được để đi quân).
  Widget _board() {
    final src = _src;
    final sim = src is SimSource;
    return BoardView(
      board: sim ? List<int>.of(src.real.board) : List<int>.of(_pos.board),
      flipped: store.side == Side.black,
      lastMove: _pos.lastMove == null ? null : (mFrom(_pos.lastMove!), mTo(_pos.lastMove!)),
      arrow: _arrow(),
      selected: _simSel,
      marked: _upd?.state == TrackState.mismatch ? _upd!.mismatch : const {},
      onTap: sim ? _simTap : null,
    );
  }

  Widget _bigBoard() => ColoredBox(
        color: const Color(0xFF1E1E1E),
        child: Center(child: Padding(padding: const EdgeInsets.all(10), child: _board())),
      );

  Widget _view() {
    if (_camError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography, color: Colors.white54, size: 56),
            const SizedBox(height: 12),
            Text(_camError!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (_camDenied) FilledButton(onPressed: () => AppSettings.openAppSettings(), child: Text('Mở Cài đặt'.tr)),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () async {
                await store.setSimulate(true);
                _openSource();
              },
              child: Text('Dùng bàn cờ mô phỏng'.tr),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text('Chọn ảnh bàn cờ'.tr),
            ),
          ]),
        ),
      );
    }
    return ValueListenableBuilder<RgbImage?>(
      valueListenable: _frame,
      builder: (context, img, _) {
        if (img == null || _src == null) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 12),
            Text('Đang mở camera…'.tr, style: const TextStyle(color: Colors.white70)),
          ]));
        }
        return Center(
          child: AspectRatio(
            aspectRatio: img.width / img.height,
            child: LayoutBuilder(builder: (context, c) {
              final box = Size(c.maxWidth, c.maxHeight);
              return GestureDetector(
                onPanStart: (d) => _panStart(d.localPosition, box),
                onPanUpdate: (d) => _panUpdate(d.localPosition, box),
                onPanEnd: (_) => _drag = null,
                child: Stack(fit: StackFit.expand, children: [
                  _src!.preview(),
                  if (_grid != null)
                    CustomPaint(
                      painter: BoardOverlay(
                        grid: _grid!,
                        rot: _rot,
                        imageSize: Size(img.width.toDouble(), img.height.toDouble()),
                        editing: !_tracking,
                        dragging: _drag,
                        lastMove: _tracking && _pos.lastMove != null ? (mFrom(_pos.lastMove!), mTo(_pos.lastMove!)) : null,
                        arrow: _tracking ? _arrow() : null,
                        marked: _tracking && (_upd?.state == TrackState.mismatch) ? _upd!.mismatch : const {},
                      ),
                    ),
                  if (_finding) const Center(child: CircularProgressIndicator(color: Colors.white)),
                ]),
              );
            }),
          ),
        );
      },
    );
  }

  (int, int)? _arrow() {
    final a = _analysis;
    if (a == null || _analysisPly != game.moves.length || !_myTurn || !(store.autoHint || _hintShown) || a.best.length < 4) return null;
    return (parseSq(a.best.substring(0, 2)), parseSq(a.best.substring(2, 4)));
  }

  Widget _calibratePanel() {
    final sim = _src is SimSource;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          _src is PhotoSource
              ? 'Ảnh phải chụp đúng thế cờ đang có trong app (ván mới = thế khởi đầu). Kéo 4 góc khớp 4 góc ô cờ nếu lưới chưa khớp.'.tr
              : sim
                  ? 'Bàn cờ mô phỏng (máy không có camera). Bấm "Tự tìm bàn" hoặc kéo 4 góc khớp 4 góc ô cờ.'.tr
                  : 'Đặt điện thoại cố định phía trên bàn cờ, thấy trọn 64 ô. Bấm "Tự tìm bàn" hoặc kéo 4 góc khớp 4 góc ô cờ (không tính viền).'.tr,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Text('Ô a1 (góc xanh) phải là góc trái gần bên Trắng. Sai thì bấm "Xoay hướng".'.tr, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _frame.value == null || _finding ? null : _autoFind,
              icon: const Icon(Icons.auto_fix_high),
              label: Text('Tự tìm bàn'.tr),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _rot = (_rot + 1) % 4),
              icon: const Icon(Icons.rotate_90_degrees_cw),
              label: Text('Xoay hướng'.tr),
            ),
          ),
        ]),
        Row(children: [
          Expanded(child: Text('Lưới lệch một hàng? Dời cả lưới:'.tr, style: Theme.of(context).textTheme.bodySmall)),
          for (final (icon, du, dv) in const [(Icons.arrow_back, -1, 0), (Icons.arrow_upward, 0, -1), (Icons.arrow_downward, 0, 1), (Icons.arrow_forward, 1, 0)])
            IconButton(visualDensity: VisualDensity.compact, onPressed: () => _nudge(du, dv), icon: Icon(icon, size: 20)),
        ]),
        FilledButton.icon(
          onPressed: _frame.value == null || _finding ? null : _startTracking,
          icon: const Icon(Icons.play_arrow),
          label: Text('Bắt đầu theo dõi'.tr),
        ),
      ]),
    );
  }

  String _statusLine() {
    final st = _pos.status();
    if (st != GameStatus.ongoing) return statusText(st, _pos.side);
    final u = _upd;
    if (u?.state == TrackState.occluded) return 'Tay đang che bàn…'.tr;
    if (u?.state == TrackState.mismatch) {
      return 'Bàn thật khác app ở ô {0}. Đặt lại quân, hoặc "Nhập tay" nước vừa đi.'.trArgs([u!.mismatch.take(6).map(sqName).join(', ')]);
    }
    final turn = _pos.side == white ? 'Trắng'.tr : 'Đen'.tr;
    if (_recordOnly) return 'Đang ghi biên bản — lượt {0}.'.trArgs([turn]);
    if (!_myTurn) return 'Chờ {0} đi…'.trArgs([turn]);
    final a = _analysis;
    if (_thinking || a == null || _analysisPly != game.moves.length) return '{0} đi — đang tìm nước hay…'.trArgs([turn]);
    if (!(store.autoHint || _hintShown)) return 'Lượt {0}. Bấm "Gợi ý" khi cần.'.trArgs([turn]);
    final m = _pos.parseUci(a.best);
    if (m == null) return '';
    return 'Gợi ý cho {0}: {1} ({2})'.trArgs([turn, describeMove(_pos, m), _pos.san(m)]);
  }

  Color _qColor(MoveQuality? q) => switch (q) {
        MoveQuality.best || MoveQuality.good => const Color(0xFF2F855A),
        MoveQuality.inaccuracy => const Color(0xFFB7791F),
        MoveQuality.mistake => const Color(0xFFDD6B20),
        MoveQuality.blunder => const Color(0xFFC53030),
        null => Theme.of(context).colorScheme.onSurfaceVariant,
      };

  Widget _trackPanel() {
    final sim = _src is SimSource;
    final a = _analysis != null && _analysisPly == game.moves.length ? _analysis : null;
    final sans = game.sans();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_statusLine(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        if (_feedback != null) ...[
          const SizedBox(height: 4),
          Text(_feedback!, style: TextStyle(color: _qColor(_feedbackQ), fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Ô nhỏ hiện cái còn lại: hình camera khi màn hình chính là bàn vẽ, và ngược lại.
          SizedBox(
            width: 150,
            height: 150,
            child: store.drawnBoard ? ClipRRect(borderRadius: BorderRadius.circular(6), child: ColoredBox(color: Colors.black, child: _view())) : _board(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!_recordOnly) Row(children: [
                Text(a == null ? '…' : scoreText(a), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: a == null ? 0.5 : (scoreBar(a) + 1) / 2,
                      minHeight: 10,
                      backgroundColor: const Color(0xFF2D2D2D),
                      color: const Color(0xFFF2F2F2),
                    ),
                  ),
                ),
              ]),
              if (!_recordOnly && a != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('{0} · sâu {1}'.trArgs([_byStockfish ? 'Stockfish' : 'Engine có sẵn'.tr, a.depth]), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
              if (!_recordOnly) const SizedBox(height: 6),
              SizedBox(
                height: _recordOnly ? 118 : 78,
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    sans.isEmpty
                        ? 'Chưa có nước nào.'.tr
                        : [for (var i = 0; i < sans.length; i += 2) '${i ~/ 2 + 1}. ${sans[i]}${i + 1 < sans.length ? ' ${sans[i + 1]}' : ''}'].join('   '),
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                ),
              ),
            ]),
          ),
        ]),
        if (_src is PhotoSource) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _finding ? null : () => _pickPhoto(_lastPick),
                icon: Icon(_lastPick == ImageSource.camera ? Icons.photo_camera_outlined : Icons.photo_library_outlined),
                label: Text('Ảnh sau nước đi'.tr),
              ),
            ),
          ]),
          const SizedBox(height: 2),
          Text('Đi một nước trên bàn thật, chụp lại từ gần chỗ cũ rồi đưa ảnh mới vào.'.tr, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (sim) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text('Mô phỏng: chạm bàn cờ vẽ để đi quân trên bàn "thật".'.tr, style: Theme.of(context).textTheme.bodySmall)),
            if (store.side != Side.both && !_recordOnly) ...[
              Text('Máy đi thay đối thủ'.tr, style: Theme.of(context).textTheme.bodySmall),
              Switch(
                  value: _simAuto,
                  onChanged: (v) {
                    setState(() => _simAuto = v);
                    _maybeSimOpponent();
                  }),
            ],
          ]),
        ],
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextButton.icon(onPressed: game.moves.isEmpty ? null : _undo, icon: const Icon(Icons.undo), label: Text('Lùi'.tr))),
          Expanded(child: TextButton.icon(onPressed: _pos.status() == GameStatus.ongoing ? _manual : null, icon: const Icon(Icons.touch_app), label: Text('Nhập tay'.tr))),
          if (!store.autoHint && !_recordOnly)
            Expanded(
              child: TextButton.icon(
                onPressed: _myTurn && !_hintShown ? () => setState(() => _hintShown = true) : null,
                icon: const Icon(Icons.lightbulb_outline),
                label: Text('Gợi ý'.tr),
              ),
            ),
        ]),
      ]),
    );
  }
}
