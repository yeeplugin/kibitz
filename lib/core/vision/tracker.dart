/// Suy ra nước vừa đi từ những ô thay đổi trên bàn thật.
///
/// Mỗi khung hình chấm được điểm khớp của bất kỳ thế cờ giả định nào ([FrameObs]). Bộ theo dõi chấm thế cờ hiện tại và
/// thế cờ sau mỗi nước hợp lệ (cả chuỗi hai nước, phòng khi bỏ lỡ nước của đối thủ); nước nào khớp quan sát hẳn hơn
/// các nước khác trong vài khung hình liền thì nhận.
library;

import '../chess/position.dart';
import 'classifier.dart';

enum TrackState {
  /// Bàn khớp thế cờ đang biết.
  stable,

  /// Có ô thay đổi nhưng chưa đủ chắc là nước nào.
  changing,

  /// Quá nhiều ô thay đổi một lúc — thường là tay đang che bàn.
  occluded,

  /// Vừa nhận một (hoặc hai) nước đi: xem [TrackUpdate.moves].
  moved,

  /// Bàn đứng yên ở thế không khớp nước hợp lệ nào: xem [TrackUpdate.mismatch].
  mismatch,
}

class TrackUpdate {
  TrackUpdate(this.state, {this.moves = const [], this.mismatch = const {}});
  final TrackState state;

  /// Nước vừa nhận (theo thứ tự đi), đã được đi trên [Tracker.pos].
  final List<int> moves;

  /// Các ô (a1 = 0) không khớp thế cờ đang biết.
  final Set<int> mismatch;
}

class Tracker {
  Tracker(this.pos, {this.stableFrames = 3, this.mismatchFrames = 12});

  /// Thế cờ đang biết; bộ theo dõi đi tiếp nước trên chính đối tượng này.
  final Position pos;
  final int stableFrames, mismatchFrames;

  String _cand = '';
  int _candCount = 0;
  int _oddFrames = 0;
  Set<int> _lastOdd = {};

  void reset() {
    _cand = '';
    _candCount = 0;
    _oddFrames = 0;
  }

  /// Các nước hợp lệ, phong cấp chỉ xét phong hậu (camera không phân biệt loại quân).
  List<int> _moves() => [
        for (final m in pos.legalMoves())
          if (mPromo(m) == 0 || mPromo(m) == queen) m,
      ];

  TrackUpdate update(FrameObs obs) {
    final c0 = obs.setBase(pos.board);
    final odd0 = obs.odd();
    if (odd0.isEmpty) {
      reset();
      return TrackUpdate(TrackState.stable);
    }
    if (odd0.length > 10) {
      _candCount = 0;
      return TrackUpdate(TrackState.occluded, mismatch: odd0);
    }
    // Một nước.
    var best = double.infinity, second = double.infinity;
    int? bestMove;
    for (final m in _moves()) {
      pos.make(m);
      final c = obs.costOf(pos.board);
      pos.unmake();
      if (c < best) {
        second = best;
        best = c;
        bestMove = m;
      } else if (c < second) {
        second = c;
      }
    }
    List<int>? cand;
    if (bestMove != null && best <= c0 - 1.5 && second - best >= 1.0) {
      // Sau nước này bàn phải khớp gần hết (còn lệch nhiều nhất một ô).
      pos.make(bestMove);
      obs.setBase(pos.board);
      final left = obs.odd().length;
      pos.unmake();
      obs.setBase(pos.board);
      if (left <= 1) cand = [bestMove];
    }
    if (cand == null && odd0.length >= 3) {
      // Hai nước liền (bỏ lỡ một nước, hoặc đối thủ đi quá nhanh).
      var b2 = double.infinity, s2 = double.infinity;
      List<int>? m2;
      for (final a in _moves()) {
        pos.make(a);
        for (final b in _moves()) {
          pos.make(b);
          final c = obs.costOf(pos.board);
          pos.unmake();
          if (c < b2) {
            s2 = b2;
            b2 = c;
            m2 = [a, b];
          } else if (c < s2) {
            s2 = c;
          }
        }
        pos.unmake();
      }
      if (m2 != null && b2 <= c0 - 3 && s2 - b2 >= 1.0) {
        pos.make(m2[0]);
        pos.make(m2[1]);
        obs.setBase(pos.board);
        final left = obs.odd().length;
        pos.unmake();
        pos.unmake();
        obs.setBase(pos.board);
        if (left <= 1) cand = m2;
      }
    }
    if (cand == null) {
      _cand = '';
      _candCount = 0;
      if (_lastOdd.length == odd0.length && _lastOdd.containsAll(odd0)) {
        _oddFrames++;
      } else {
        _oddFrames = 1;
      }
      _lastOdd = odd0;
      return TrackUpdate(_oddFrames >= mismatchFrames ? TrackState.mismatch : TrackState.changing, mismatch: odd0);
    }
    final key = cand.join(',');
    if (key == _cand) {
      _candCount++;
    } else {
      _cand = key;
      _candCount = 1;
    }
    if (_candCount < stableFrames) return TrackUpdate(TrackState.changing, mismatch: odd0);
    for (final m in cand) {
      pos.make(m);
    }
    reset();
    return TrackUpdate(TrackState.moved, moves: cand);
  }
}
