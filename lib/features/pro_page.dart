/// Trang bản Pro: những gì Pro mở khoá, đăng ký, khôi phục giao dịch, và giấy phép (app và Stockfish đều GPLv3).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

import '../core/i18n.dart';
import '../data/store.dart';
import '../services/billing.dart';
import '../shared/ios.dart';

/// Nơi công bố mã nguồn app (bắt buộc theo GPL vì app đóng gói Stockfish). Điền địa chỉ kho mã trước khi phát hành.
const sourceUrl = 'https://github.com/yeeplugin/kibitz';

class ProPage extends StatefulWidget {
  const ProPage({super.key, required this.store, required this.billing});
  final Store store;
  final Billing billing;

  @override
  State<ProPage> createState() => _ProPageState();
}

class _ProPageState extends State<ProPage> {
  Store get store => widget.store;
  Billing get billing => widget.billing;

  @override
  void initState() {
    super.initState();
    billing.clearNotice();
    if (!store.pro) unawaited(billing.loadProducts());
  }

  String _noticeText(BillingNotice n) => switch (n) {
        BillingNotice.unlocked => 'Đã mở bản Pro. Cảm ơn bạn!'.tr,
        BillingNotice.pending => 'Giao dịch đang chờ xử lý. Bản Pro sẽ mở khi cửa hàng xác nhận.'.tr,
        BillingNotice.failed => 'Giao dịch không thành công. Vui lòng thử lại.'.tr,
        BillingNotice.restored => 'Đã khôi phục bản Pro.'.tr,
        BillingNotice.nothingToRestore => 'Không tìm thấy giao dịch nào để khôi phục'.tr,
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, billing]),
      builder: (context, _) {
        final small = tFootnote.copyWith(color: iosLabel2(context));
        final pro = store.pro;
        final notice = billing.notice;
        Widget note(String s) => Padding(padding: const EdgeInsets.fromLTRB(32, 12, 32, 0), child: Text(s, textAlign: TextAlign.center, style: small));
        return IosPage(
          title: 'Bản Pro'.tr,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5AC8FA), Color(0xFF007AFF)]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(CupertinoIcons.star_fill, size: 40, color: CupertinoColors.white),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(pro ? 'Bạn đang dùng bản Pro'.tr : 'Nâng cấp bản Pro'.tr, textAlign: TextAlign.center, style: tTitle2),
            ),
            // Chỉ ghi những gì Pro thật sự mở khoá.
            IosSection(dividerIndent: 57, footer: 'Bản miễn phí vẫn đủ mọi tính năng khác, với engine có sẵn của app.'.tr, children: [
              for (final (icon, color, text) in [
                (CupertinoIcons.bolt_fill, const Color(0xFF007AFF), 'Gợi ý và chấm nước bằng Stockfish — engine cờ mạnh nhất hiện nay.'.tr),
                (CupertinoIcons.timer, const Color(0xFF5856D6), 'Tính sâu hơn nhiều trong cùng thời gian nghĩ.'.tr),
                (CupertinoIcons.checkmark_alt, const Color(0xFF34C759), 'Huỷ bất cứ lúc nào.'.tr),
              ])
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                  child: Row(children: [
                    Container(
                      width: 29,
                      height: 29,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
                      child: Icon(icon, size: 18, color: CupertinoColors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text, style: tSubhead)),
                  ]),
                ),
            ]),
            if (pro)
              note('${'Chọn engine ở Cài đặt → Engine cờ.'.tr}\n${'Quản lý hoặc huỷ gói trong phần gói đăng ký của App Store / Google Play.'.tr}')
            else if (!billing.supported)
              note('Mua bản Pro trong app trên điện thoại (App Store hoặc Google Play).'.tr)
            else ...[
              if (billing.loading)
                Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: Column(children: [const CupertinoActivityIndicator(), const SizedBox(height: 8), Text('Đang tải gói từ cửa hàng…'.tr, style: small)]),
                )
              else if (billing.loadFailed) ...[
                note('Chưa tải được gói từ cửa hàng. Kiểm tra kết nối mạng rồi thử lại.'.tr),
                IosButton(label: 'Thử lại'.tr, kind: IosButtonKind.plain, onPressed: billing.loadProducts),
              ] else
                for (final p in billing.products)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: IosButton(
                      onPressed: billing.busy ? null : () => billing.buy(p),
                      // Giá lấy từ cửa hàng, đã theo tiền tệ và thuế của nước người dùng.
                      label: p.id == proMonthly ? 'Đăng ký {0} / tháng'.trArgs([p.price]) : '${p.title} · ${p.price}',
                    ),
                  ),
              // Điều khoản gia hạn chỉ hiện khi có gói để mua.
              if (billing.products.isNotEmpty)
                note('Gói tự gia hạn hằng tháng cho đến khi bạn huỷ. Huỷ bất cứ lúc nào trong phần quản lý gói đăng ký của App Store / Google Play.'.tr),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: IosButton(label: 'Khôi phục giao dịch'.tr, kind: IosButtonKind.plain, onPressed: billing.busy ? null : billing.restore),
              ),
            ],
            if (notice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                child: Text(
                  _noticeText(notice),
                  textAlign: TextAlign.center,
                  style: tSubhead.copyWith(fontWeight: FontWeight.w600, color: notice == BillingNotice.failed || notice == BillingNotice.nothingToRestore ? iosRed(context) : iosTint(context)),
                ),
              ),
            // Chỉ có trong bản debug: bật/tắt Pro để thử mà không cần cửa hàng.
            if (kDebugMode)
              IosSection(children: [
                IosSwitchTile(
                  title: 'Pro (debug)',
                  subtitle: 'Chỉ có trong bản debug — để thử Stockfish khi chưa có sản phẩm trên cửa hàng.',
                  value: store.debugPro,
                  onChanged: store.setDebugPro,
                ),
              ]),
            IosSection(
              header: 'Giấy phép'.tr,
              footer: sourceUrl.isEmpty ? null : 'Mã nguồn app: {0}'.trArgs([sourceUrl]),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                  child: Text(
                    'App này và Stockfish là phần mềm tự do, phát hành theo giấy phép GNU GPL phiên bản 3. Mã nguồn Stockfish: github.com/official-stockfish/Stockfish'.tr,
                    style: tFootnote.copyWith(color: iosLabel2(context)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
