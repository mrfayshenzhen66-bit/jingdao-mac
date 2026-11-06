//  DonationWindow.swift — 景到 20.9：自愿打赏。
//
//  景到免费分发（GPL-3.0-or-later 允许分发、修改，也允许接受自愿赞助）。这个窗口只放
//  mrfay 本人的赞赏码和收款码，说明打赏自愿、不解锁任何功能，并写明收款人与上游作者
//  无关，同时给出上游项目主页。入口：关于页底部、帮助菜单。不弹窗，不在编辑界面出现。

import SwiftUI

struct DonationWindow: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("☕️").font(.system(size: 30))
            Text(L("Buy the Author a Coffee", zh: "请作者喝杯咖啡"))
                .font(.system(size: 17, weight: .semibold))
            Text(L("Jingdao is free. If it helped you, a tip is welcome and keeps the work going.",
                   zh: "景到免费使用。如果它帮到了你，欢迎随意打赏，支持我继续改进。"))
                .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 18) {
                code(DonationCodes.wechat, L("WeChat Appreciation", zh: "微信 · 赞赏码"))
                code(DonationCodes.alipay, L("Alipay", zh: "支付宝 · 扫一扫"))
            }
            .padding(.top, 4)
            VStack(spacing: 4) {
                Text(L("Tipping is entirely voluntary and unlocks nothing.",
                       zh: "打赏完全自愿，不解锁任何功能。"))
                Text(L("Tips go to mrfay for this modification, not to the SpektraLab authors.",
                       zh: "打赏给的是 mrfay 的修改工作，与 SpektraLab 原作者无关。"))
                HStack(spacing: 4) {
                    Text(L("To support the original project:", zh: "想支持原作者，请访问"))
                    Link("github.com/JamesQiu2005/SpektraLab",
                         destination: URL(string: "https://github.com/JamesQiu2005/SpektraLab")!)
                }
            }
            .font(Theme.Font.small).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 440)
        .background(Theme.card)
    }

    private func code(_ image: NSImage?, _ caption: String) -> some View {
        VStack(spacing: 8) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(1, contentMode: .fit)
                } else {
                    Color.gray
                }
            }
            .frame(width: 168, height: 168)
            // 白底加留白：二维码四周要有静区，深色背景上才扫得出。
            .padding(10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(caption).font(Theme.Font.small).foregroundStyle(.secondary)
        }
    }
}
