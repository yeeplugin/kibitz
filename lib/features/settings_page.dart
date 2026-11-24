/// Trang cài đặt: gợi ý cho bên nào, engine nghĩ bao lâu, hiển thị, ngôn ngữ.
library;

import 'package:material_ui/material_ui.dart';

import '../core/coach.dart';
import '../core/i18n.dart';
import '../data/store.dart';
import '../services/billing.dart';
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final record = store.side == Side.none;
        Widget title(String s) => Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
              child: Text(s, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary)),
            );
        Widget card(List<Widget> children) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: children)));
        return Scaffold(
          appBar: AppBar(title: Text('Cài đặt'.tr)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    title('Gợi ý nước đi'.tr),
                    card([
                      _row(
                        context,
                        'Gợi ý cho'.tr,
                        SegmentedButton<Side>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: [for (final s in Side.values) ButtonSegment(value: s, label: Text(sideLabel(s), maxLines: 1, softWrap: false))],
                          selected: {store.side},
                          onSelectionChanged: (v) => store.setSide(v.first),
                        ),
                        note: record
                            ? 'Chỉ ghi: app chỉ ghi lại nước đi của hai bên, không gợi ý và không chấm nước.'.tr
                            : 'Chọn "Chỉ ghi" để app chỉ ghi biên bản ván đấu, không gợi ý.'.tr,
                      ),
                      _row(
                        context,
                        'Engine cờ'.tr,
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(value: false, label: Text('Có sẵn'.tr)),
                            ButtonSegment(value: true, label: Text('Stockfish'), icon: Icon(store.pro ? Icons.workspace_premium : Icons.lock_outline, size: 18)),
                          ],
                          selected: {store.useStockfish},
                          onSelectionChanged: record
                              ? null
                              : (v) {
                                  if (v.first && !store.pro) {
                                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ProPage(store: store, billing: billing)));
                                  } else {
                                    store.setWantStockfish(v.first);
                                  }
                                },
                        ),
                        note: store.pro
                            ? 'Stockfish mạnh hơn hẳn engine có sẵn, nhưng tốn pin hơn.'.tr
                            : 'Stockfish có ở bản Pro. Engine có sẵn đủ để bắt lỗi mất quân và đòn chiến thuật ngắn.'.tr,
                      ),
                      _row(
                        context,
                        'Engine nghĩ'.tr,
                        SegmentedButton<Level>(
                          showSelectedIcon: false,
                          segments: [for (final l in Level.values) ButtonSegment(value: l, label: Text(l.label))],
                          selected: {store.level},
                          onSelectionChanged: record ? null : (v) => store.setLevel(v.first),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        title: Text('Tự hiện gợi ý khi tới lượt'.tr),
                        subtitle: Text('Tắt để tự nghĩ trước, bấm "Gợi ý" khi cần.'.tr),
                        value: store.autoHint,
                        onChanged: record ? null : store.setAutoHint,
                      ),
                    ]),
                    title('Hiển thị'.tr),
                    card([
                      SwitchListTile.adaptive(
                        title: Text('Bàn cờ vẽ làm màn hình chính'.tr),
                        subtitle: Text('Khi theo dõi ván: hiện bàn cờ app tự vẽ, hình camera thu nhỏ. Tắt để ngược lại.'.tr),
                        value: store.drawnBoard,
                        onChanged: store.setDrawnBoard,
                      ),
                      ListTile(
                        title: Text('Ngôn ngữ'.tr),
                        trailing: DropdownButton<String>(
                          value: store.lang,
                          underline: const SizedBox(),
                          items: [for (final e in I18n.languages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                          onChanged: (v) => v == null ? null : store.setLang(v),
                        ),
                      ),
                    ]),
                    title('Thử nghiệm'.tr),
                    card([
                      SwitchListTile.adaptive(
                        title: Text('Bàn cờ mô phỏng'.tr),
                        subtitle: Text('Dùng bàn cờ vẽ sẵn thay camera — để thử app trên máy không có camera.'.tr),
                        value: store.simulate,
                        onChanged: store.setSimulate,
                      ),
                    ]),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, String label, Widget child, {String? note}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: child),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ]),
      );
}
