/// Tab "Chơi": ván mới với camera / tiếp tục / đánh với máy / xếp thế cờ, bản Pro và mẹo dùng camera.
library;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../core/chess/position.dart';
import '../core/coach.dart';
import '../core/i18n.dart';
import '../data/store.dart';
import '../shared/board_view.dart';
import '../shared/ios.dart';
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
    await iosPush<void>(context, PlayPage(store: store, game: g));
  }

  Future<void> _newGame(BuildContext context) async {
    if (await _askCoach(context) && context.mounted) await _play(context, Game());
  }

  /// Hỏi trước khi vào ván camera: gợi ý cho bên nào, engine nghĩ nhanh hay kỹ. Trả về false nếu người dùng đóng lại.
  Future<bool> _askCoach(BuildContext context) async {
    final ok = await iosSheet<bool>(
      context,
      (c) => ListenableBuilder(
        listenable: store,
        builder: (c, _) {
          final record = store.side == Side.none;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('Ván mới với camera'.tr, style: tTitle2)),
                IosSection(
                  top: 16,
                  header: 'Gợi ý cho'.tr,
                  footer: record ? 'Chỉ ghi: app chỉ ghi lại nước đi của hai bên, không gợi ý và không chấm nước.'.tr : 'Bên được gợi ý cũng là bên được chấm từng nước đi.'.tr,
                  children: [
                    IosBlock(
                      child: IosSegmented<Side>(items: {for (final s in Side.values) s: sideLabel(s)}, value: store.side, onChanged: store.setSide),
                    ),
                  ],
                ),
                IosSection(
                  header: 'Engine nghĩ'.tr,
                  footer: 'Nghĩ càng kỹ gợi ý càng chuẩn nhưng phải chờ lâu hơn. Đổi lại được trong Cài đặt.'.tr,
                  children: [
                    IosBlock(
                      child: IosSegmented<Level>(
                        items: {for (final l in Level.values) l: l.label},
                        value: store.level,
                        onChanged: record ? null : store.setLevel,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: IosButton(label: 'Bắt đầu'.tr, icon: CupertinoIcons.camera_fill, onPressed: () => Navigator.pop(c, true)),
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
    final fen = await iosPush<String>(context, const EditorPage());
    if (fen == null || !context.mounted) return;
    if (await _askCoach(context) && context.mounted) await _play(context, Game(startFen: fen));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final g = store.game;
        final live = g != null && g.moves.isNotEmpty;
        return IosPage(
          large: true,
          title: 'Kibitz',
          children: [
            if (live)
              IosSection(top: 6, children: [
                IosTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(width: 76, child: IgnorePointer(child: BoardView(board: List<int>.of(g.position().board)))),
                  ),
                  title: 'Tiếp tục ván đang dở'.tr,
                  bold: true,
                  subtitle: '{0} nước · lượt {1}'.trArgs([g.moves.length, g.position().side == white ? 'Trắng'.tr : 'Đen'.tr]),
                  onTap: () => _play(context, g),
                ),
              ]),
            Padding(
              padding: EdgeInsets.fromLTRB(16, live ? 16 : 6, 16, 0),
              child: IosButton(label: 'Ván mới với camera'.tr, icon: CupertinoIcons.camera_fill, onPressed: () => _newGame(context)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 9, 32, 0),
              child: Text(
                'Đặt điện thoại phía trên bàn cờ thật. App nhận ra từng nước bạn và đối thủ đi, rồi chỉ nước hay tiếp theo ngay trên hình camera.'.tr,
                style: tFootnote.copyWith(color: iosLabel2(context)),
              ),
            ),
            IosSection(dividerIndent: 57, children: [
              IosTile(
                icon: CupertinoIcons.gamecontroller_fill,
                iconColor: const Color(0xFF5856D6),
                title: store.vsGame == null ? 'Đánh với máy (không cần camera)'.tr : 'Tiếp tục ván với máy'.tr,
                onTap: () => iosPush<void>(context, VsPage(store: store, billing: billing)),
              ),
              IosTile(
                icon: CupertinoIcons.square_grid_2x2_fill,
                iconColor: const Color(0xFFFF9500),
                title: 'Xếp thế cờ đang dở'.tr,
                onTap: () => _setup(context),
              ),
              if (live)
                IosTile(
                  icon: CupertinoIcons.list_bullet,
                  iconColor: const Color(0xFF34C759),
                  title: 'Biên bản ván đang chơi'.tr,
                  subtitle: 'Xem lại từng nước, xuất tệp PGN.'.tr,
                  onTap: () => iosPush<void>(context, RecordPage(game: g, save: () => store.saveGame(g), flipped: store.side == Side.black)),
                ),
            ]),
            // Bản Pro chỉ mở Stockfish, mà Stockfish không có trên Mac: ở đó không mời nâng cấp.
            if (Store.stockfishSupported)
              IosSection(dividerIndent: 57, children: [
                IosTile(
                  icon: CupertinoIcons.star_fill,
                  iconColor: const Color(0xFFFFCC00),
                  title: store.pro ? 'Bạn đang dùng bản Pro'.tr : 'Nâng cấp bản Pro'.tr,
                  subtitle: store.pro ? 'Gợi ý bằng Stockfish'.tr : 'Gợi ý bằng Stockfish — engine cờ mạnh nhất hiện nay.'.tr,
                  onTap: () => iosPush<void>(context, ProPage(store: store, billing: billing)),
                ),
              ]),
            IosSection(header: 'Mẹo để nhận nước đi chuẩn'.tr, dividerIndent: 48, children: [
              for (final t in [
                'Giữ điện thoại cố định (giá đỡ, kẹp) — chỉ căn bàn một lần.'.tr,
                'Camera càng nhìn thẳng từ trên xuống càng tốt; quân cao dễ che ô phía sau.'.tr,
                'Đủ sáng, tránh bóng tay hay bóng đèn đổ lên bàn.'.tr,
                'Đi xong rút tay ra khỏi bàn; app chờ bàn đứng yên rồi mới nhận nước.'.tr,
                'Phong cấp ngoài hậu, hay camera nhận sai: dùng "Nhập tay".'.tr,
              ])
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 1), child: Icon(CupertinoIcons.checkmark_circle_fill, size: 20, color: iosTint(context))),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t, style: tSubhead)),
                  ]),
                ),
            ]),
          ],
        );
      },
    );
  }
}
