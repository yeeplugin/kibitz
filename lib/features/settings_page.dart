/// Tab cài đặt: gợi ý cho bên nào, engine nghĩ bao lâu, hiển thị, ngôn ngữ.
library;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../core/coach.dart';
import '../core/i18n.dart';
import '../data/store.dart';
import '../services/billing.dart';
import '../shared/ios.dart';
import 'pro_page.dart';

String sideLabel(Side s) => switch (s) {
      Side.white => 'Trắng'.tr,
      Side.black => 'Đen'.tr,
      Side.both => 'Cả hai'.tr,
      Side.none => 'Chỉ ghi'.tr,
    };

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store, required this.billing});
  final Store store;
  final Billing billing;

  Future<void> _pickLang(BuildContext context) async {
    final v = await iosActionSheet<String>(context, title: 'Ngôn ngữ'.tr, actions: I18n.languages, selected: store.lang, cancel: 'Huỷ'.tr);
    if (v != null) await store.setLang(v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final record = store.side == Side.none;
        return IosPage(
          large: true,
          title: 'Cài đặt'.tr,
          children: [
            if (Store.stockfishSupported)
              IosSection(top: 6, dividerIndent: 57, children: [
                IosTile(
                  icon: CupertinoIcons.star_fill,
                  iconColor: const Color(0xFFFFCC00),
                  title: store.pro ? 'Bạn đang dùng bản Pro'.tr : 'Nâng cấp bản Pro'.tr,
                  subtitle: store.pro ? 'Gợi ý bằng Stockfish'.tr : 'Gợi ý bằng Stockfish — engine cờ mạnh nhất hiện nay.'.tr,
                  onTap: () => iosPush<void>(context, ProPage(store: store, billing: billing)),
                ),
              ]),
            IosSection(
              top: Store.stockfishSupported ? 22 : 6,
              header: 'Gợi ý nước đi'.tr,
              footer: record
                  ? 'Chỉ ghi: app chỉ ghi lại nước đi của hai bên, không gợi ý và không chấm nước.'.tr
                  : 'Chọn "Chỉ ghi" để app chỉ ghi biên bản ván đấu, không gợi ý.'.tr,
              children: [
                IosBlock(
                  label: 'Gợi ý cho'.tr,
                  child: IosSegmented<Side>(items: {for (final s in Side.values) s: sideLabel(s)}, value: store.side, onChanged: store.setSide),
                ),
              ],
            ),
            IosSection(
              footer: !Store.stockfishSupported
                  ? null
                  : store.pro
                      ? 'Stockfish mạnh hơn hẳn engine có sẵn, nhưng tốn pin hơn.'.tr
                      : 'Stockfish có ở bản Pro. Engine có sẵn đủ để bắt lỗi mất quân và đòn chiến thuật ngắn.'.tr,
              children: [
                if (Store.stockfishSupported)
                  IosBlock(
                    label: 'Engine cờ'.tr,
                    child: IosSegmented<bool>(
                      items: {false: 'Có sẵn'.tr, true: 'Stockfish'},
                      icons: {true: store.pro ? CupertinoIcons.star_fill : CupertinoIcons.lock_fill},
                      value: store.useStockfish,
                      onChanged: record
                          ? null
                          : (v) {
                              if (v && !store.pro) {
                                iosPush<void>(context, ProPage(store: store, billing: billing));
                              } else {
                                store.setWantStockfish(v);
                              }
                            },
                    ),
                  ),
                IosBlock(
                  label: 'Engine nghĩ'.tr,
                  child: IosSegmented<Level>(items: {for (final l in Level.values) l: l.label}, value: store.level, onChanged: record ? null : store.setLevel),
                ),
                IosSwitchTile(
                  title: 'Tự hiện gợi ý khi tới lượt'.tr,
                  subtitle: 'Tắt để tự nghĩ trước, bấm "Gợi ý" khi cần.'.tr,
                  value: store.autoHint,
                  onChanged: record ? null : store.setAutoHint,
                ),
              ],
            ),
            IosSection(header: 'Hiển thị'.tr, children: [
              IosSwitchTile(
                title: 'Bàn cờ vẽ làm màn hình chính'.tr,
                subtitle: 'Khi theo dõi ván: hiện bàn cờ app tự vẽ, hình camera thu nhỏ. Tắt để ngược lại.'.tr,
                value: store.drawnBoard,
                onChanged: store.setDrawnBoard,
              ),
              IosTile(title: 'Ngôn ngữ'.tr, value: I18n.languages[store.lang], onTap: () => _pickLang(context)),
            ]),
            IosSection(header: 'Thử nghiệm'.tr, children: [
              IosSwitchTile(
                title: 'Bàn cờ mô phỏng'.tr,
                subtitle: 'Dùng bàn cờ vẽ sẵn thay camera — để thử app trên máy không có camera.'.tr,
                value: store.simulate,
                onChanged: store.setSimulate,
              ),
            ]),
          ],
        );
      },
    );
  }
}
