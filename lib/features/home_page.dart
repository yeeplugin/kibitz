/// Màn hình chính: ván mới / tiếp tục / xếp thế cờ, các ván đã ghi, lối vào cài đặt.
library;

import 'package:material_ui/material_ui.dart';

import '../core/chess/position.dart';
import '../core/coach.dart';
import '../core/i18n.dart';
import '../data/store.dart';
import '../shared/board_view.dart';
import 'editor_page.dart';
import '../services/billing.dart';
import 'play/play_page.dart';
import 'pro_page.dart';
import 'record_page.dart';
import 'settings_page.dart';
import 'vs_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store, required this.billing});
  final Store store;
  final Billing billing;

  /// Mở ván [g]. Ván khác đang dở (đã có nước đi) được cất vào "Ván đã ghi" chứ không mất.
  Future<void> _play(BuildContext context, Game g) async {
    final old = store.game;
    if (old != null && old.moves.isNotEmpty && old.startedAt != g.startedAt) await store.archive(old);
    await store.saveGame(g);
    if (!context.mounted) return;
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PlayPage(store: store, game: g)));
  }

  Future<void> _newGame(BuildContext context) async {
    if (await _askCoach(context) && context.mounted) await _play(context, Game());
  }

  /// Hỏi trước khi vào ván camera: gợi ý cho bên nào, engine nghĩ nhanh hay kỹ. Trả về false nếu người dùng đóng lại.
  Future<bool> _askCoach(BuildContext context) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => ListenableBuilder(
        listenable: store,
        builder: (c, _) {
          final t = Theme.of(c).textTheme, cs = Theme.of(c).colorScheme;
          final record = store.side == Side.none;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Ván mới với camera'.tr, style: t.titleLarge),
                const SizedBox(height: 16),
                Text('Gợi ý cho'.tr, style: t.bodyLarge),
                const SizedBox(height: 8),
                SegmentedButton<Side>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [for (final s in Side.values) ButtonSegment(value: s, label: Text(sideLabel(s), maxLines: 1, softWrap: false))],
                  selected: {store.side},
                  onSelectionChanged: (v) => store.setSide(v.first),
                ),
                const SizedBox(height: 6),
                Text(
                  record ? 'Chỉ ghi: app chỉ ghi lại nước đi của hai bên, không gợi ý và không chấm nước.'.tr : 'Bên được gợi ý cũng là bên được chấm từng nước đi.'.tr,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Text('Engine nghĩ'.tr, style: t.bodyLarge),
                const SizedBox(height: 8),
                SegmentedButton<Level>(
                  showSelectedIcon: false,
                  segments: [for (final l in Level.values) ButtonSegment(value: l, label: Text(l.label))],
                  selected: {store.level},
                  onSelectionChanged: record ? null : (v) => store.setLevel(v.first),
                ),
                const SizedBox(height: 6),
                Text('Nghĩ càng kỹ gợi ý càng chuẩn nhưng phải chờ lâu hơn. Đổi lại được trong Cài đặt.'.tr, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.pop(c, true),
                  icon: const Icon(Icons.photo_camera),
                  label: Text('Bắt đầu'.tr),
                ),
              ]),
            ),
          );
        },
      ),
    );
    return ok ?? false;
  }

  Future<void> _setup(BuildContext context) async {
    final fen = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const EditorPage()));
    if (fen == null || !context.mounted) return;
    if (await _askCoach(context) && context.mounted) await _play(context, Game(startFen: fen));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final g = store.game;
        final saved = store.history.length;
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Kibitz'),
            actions: [IconButton(tooltip: 'Cài đặt'.tr, icon: const Icon(Icons.settings_outlined), onPressed: () => _open(context, SettingsPage(store: store, billing: billing)))],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          Icon(Icons.photo_camera, size: 40, color: cs.primary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Đặt điện thoại phía trên bàn cờ thật. App nhận ra từng nước bạn và đối thủ đi, rồi chỉ nước hay tiếp theo ngay trên hình camera.'.tr,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (g != null && g.moves.isNotEmpty) ...[
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _play(context, g),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(children: [
                              SizedBox(width: 84, child: IgnorePointer(child: BoardView(board: List<int>.of(g.position().board)))),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Tiếp tục ván đang dở'.tr, style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text('{0} nước · lượt {1}'.trArgs([g.moves.length, g.position().side == white ? 'Trắng'.tr : 'Đen'.tr]),
                                      style: TextStyle(color: cs.onSurfaceVariant)),
                                ]),
                              ),
                              const Icon(Icons.chevron_right),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => _newGame(context),
                      icon: const Icon(Icons.photo_camera),
                      label: Text('Ván mới với camera'.tr),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () => _open(context, VsPage(store: store, billing: billing)),
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: Text(store.vsGame == null ? 'Đánh với máy (không cần camera)'.tr : 'Tiếp tục ván với máy'.tr),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () => _setup(context),
                      icon: const Icon(Icons.grid_on),
                      label: Text('Xếp thế cờ đang dở'.tr),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        if (g != null && g.moves.isNotEmpty)
                          ListTile(
                            leading: const Icon(Icons.list_alt),
                            title: Text('Biên bản ván đang chơi'.tr),
                            subtitle: Text('Xem lại từng nước, xuất tệp PGN.'.tr),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(context, RecordPage(game: g, save: () => store.saveGame(g), flipped: store.side == Side.black)),
                          ),
                        ListTile(
                          leading: const Icon(Icons.history),
                          title: Text('Ván đã ghi'.tr),
                          subtitle: Text(saved == 0 ? 'Chưa có ván nào.'.tr : '{0} ván'.trArgs([saved])),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(context, GamesPage(store: store)),
                        ),
                        ListTile(
                          leading: Icon(Icons.workspace_premium_outlined, color: cs.primary),
                          title: Text(store.pro ? 'Bạn đang dùng bản Pro'.tr : 'Nâng cấp bản Pro'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(store.pro ? 'Gợi ý bằng Stockfish'.tr : 'Gợi ý bằng Stockfish — engine cờ mạnh nhất hiện nay.'.tr),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(context, ProPage(store: store, billing: billing)),
                        ),
                        ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: Text('Cài đặt'.tr),
                          subtitle: Text(store.side == Side.none
                              ? 'Chỉ ghi nước đi, không gợi ý'.tr
                              : 'Gợi ý cho {0} · engine nghĩ {1}'.trArgs([sideLabel(store.side).toLowerCase(), store.level.label.toLowerCase()])),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(context, SettingsPage(store: store, billing: billing)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    Text('Mẹo để nhận nước đi chuẩn'.tr, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary)),
                    const SizedBox(height: 8),
                    for (final t in [
                      'Giữ điện thoại cố định (giá đỡ, kẹp) — chỉ căn bàn một lần.'.tr,
                      'Camera càng nhìn thẳng từ trên xuống càng tốt; quân cao dễ che ô phía sau.'.tr,
                      'Đủ sáng, tránh bóng tay hay bóng đèn đổ lên bàn.'.tr,
                      'Đi xong rút tay ra khỏi bàn; app chờ bàn đứng yên rồi mới nhận nước.'.tr,
                      'Phong cấp ngoài hậu, hay camera nhận sai: dùng "Nhập tay".'.tr,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.check_circle_outline, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(t)),
                        ]),
                      ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _open(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
}
