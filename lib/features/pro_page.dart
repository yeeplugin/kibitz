/// Trang bản Pro: những gì Pro mở khoá, đăng ký, khôi phục giao dịch, và giấy phép (app và Stockfish đều GPLv3).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../core/i18n.dart';
import '../data/store.dart';
import '../services/billing.dart';

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
        final cs = Theme.of(context).colorScheme;
        final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
        final pro = store.pro;
        final notice = billing.notice;
        return Scaffold(
          appBar: AppBar(title: Text('Bản Pro'.tr)),
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
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(Icons.workspace_premium, size: 36, color: cs.primary),
                            const SizedBox(width: 12),
                            Expanded(child: Text(pro ? 'Bạn đang dùng bản Pro'.tr : 'Nâng cấp bản Pro'.tr, style: Theme.of(context).textTheme.titleLarge)),
                          ]),
                          const SizedBox(height: 14),
                          // Chỉ ghi những gì Pro thật sự mở khoá.
                          for (final b in [
                            'Gợi ý và chấm nước bằng Stockfish — engine cờ mạnh nhất hiện nay.'.tr,
                            'Tính sâu hơn nhiều trong cùng thời gian nghĩ.'.tr,
                            'Huỷ bất cứ lúc nào.'.tr,
                          ])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Padding(padding: const EdgeInsets.only(top: 2, right: 8), child: Icon(Icons.check_circle, size: 18, color: cs.primary)),
                                Expanded(child: Text(b)),
                              ]),
                            ),
                          const SizedBox(height: 4),
                          Text('Bản miễn phí vẫn đủ mọi tính năng khác, với engine có sẵn của app.'.tr, style: small),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (pro)
                      Text('${'Chọn engine ở Cài đặt → Engine cờ.'.tr}\n${'Quản lý hoặc huỷ gói trong phần gói đăng ký của App Store / Google Play.'.tr}', textAlign: TextAlign.center, style: small)
                    else if (!billing.supported)
                      Text('Mua bản Pro trong app trên điện thoại (App Store hoặc Google Play).'.tr, textAlign: TextAlign.center, style: small)
                    else ...[
                      if (billing.loading)
                        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Đang tải gói từ cửa hàng…'.tr, textAlign: TextAlign.center, style: small))
                      else if (billing.loadFailed) ...[
                        Text('Chưa tải được gói từ cửa hàng. Kiểm tra kết nối mạng rồi thử lại.'.tr, textAlign: TextAlign.center, style: small),
                        TextButton(onPressed: billing.loadProducts, child: Text('Thử lại'.tr)),
                      ] else
                        for (final p in billing.products)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: FilledButton(
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                              onPressed: billing.busy ? null : () => billing.buy(p),
                              // Giá lấy từ cửa hàng, đã theo tiền tệ và thuế của nước người dùng.
                              child: Text(p.id == proMonthly ? 'Đăng ký {0} / tháng'.trArgs([p.price]) : '${p.title} · ${p.price}'),
                            ),
                          ),
                      // Điều khoản gia hạn chỉ hiện khi có gói để mua.
                      if (billing.products.isNotEmpty)
                        Text('Gói tự gia hạn hằng tháng cho đến khi bạn huỷ. Huỷ bất cứ lúc nào trong phần quản lý gói đăng ký của App Store / Google Play.'.tr,
                            textAlign: TextAlign.center, style: small),
                      TextButton(onPressed: billing.busy ? null : billing.restore, child: Text('Khôi phục giao dịch'.tr)),
                    ],
                    if (notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _noticeText(notice),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600, color: notice == BillingNotice.failed || notice == BillingNotice.nothingToRestore ? cs.error : cs.primary),
                        ),
                      ),
                    // Chỉ có trong bản debug: bật/tắt Pro để thử mà không cần cửa hàng.
                    if (kDebugMode) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: SwitchListTile.adaptive(
                          title: const Text('Pro (debug)'),
                          subtitle: const Text('Chỉ có trong bản debug — để thử Stockfish khi chưa có sản phẩm trên cửa hàng.'),
                          value: store.debugPro,
                          onChanged: store.setDebugPro,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text('Giấy phép'.tr, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary)),
                    const SizedBox(height: 6),
                    Text(
                      'App này và Stockfish là phần mềm tự do, phát hành theo giấy phép GNU GPL phiên bản 3. Mã nguồn Stockfish: github.com/official-stockfish/Stockfish'.tr,
                      style: small,
                    ),
                    if (sourceUrl.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Mã nguồn app: {0}'.trArgs([sourceUrl]), style: small)),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
