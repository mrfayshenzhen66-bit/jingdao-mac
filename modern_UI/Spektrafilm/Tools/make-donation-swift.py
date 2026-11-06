#!/usr/bin/env python3
"""把 PersonalIcon 里的微信赞赏码、支付宝收款码裁出码区，写进 Windows/DonationCodes.swift。

和 MRFAY 字标一样以 PNG 数据写进源码（build-personal.sh 只允许新增 Personal.icns 一个资源）。
裁剪框按原图像素给出；换图时先核对坐标。用法：python3 Tools/make-donation-swift.py
"""
import base64, io, pathlib
from PIL import Image
root = pathlib.Path(__file__).resolve().parent.parent
SRC = {
    # 微信赞赏码（小程序码）：白色方块，四周已有留白
    "wechat": ("PersonalIcon/Donate_WeChat.jpg", (318, 183, 834, 699)),
    # 支付宝收款码：二维码外留约 4 个模块的白边（静区），扫码需要
    "alipay": ("PersonalIcon/Donate_Alipay.jpg", (212, 698, 1122, 1608)),
}
SIZE = 400                                   # 显示约 170 pt，2× 屏足够清晰
parts = []
for name, (path, box) in SRC.items():
    im = Image.open(root / path).convert("RGB").crop(box).resize((SIZE, SIZE), Image.LANCZOS)
    buf = io.BytesIO(); im.save(buf, "PNG", optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode()
    lines = "\n".join(b64[i:i+100] for i in range(0, len(b64), 100))
    # 多行字符串字面量，不用 + 拼接：上千段拼接会让 Swift 类型检查崩溃（signal 4）。
    parts.append(f'''    static let {name}: NSImage? = {{
        let b64 = """
{lines}
"""
        return Data(base64Encoded: b64, options: .ignoreUnknownCharacters).flatMap {{ NSImage(data: $0) }}
    }}()''')
    im.save(f"/tmp/jingdao/donate_{name}.png")
out = '''//  DonationCodes.swift — 生成文件，勿手改：python3 Tools/make-donation-swift.py
//
//  mrfay 本人的微信赞赏码与支付宝收款码（源图在 PersonalIcon/Donate_*.jpg）。
//  打赏完全自愿，不解锁任何功能；收款人是 mrfay，与 SpektraLab 原作者无关。

import AppKit

enum DonationCodes {
''' + "\n".join(parts) + "\n}\n"
(root / "Spektrafilm/Windows/DonationCodes.swift").write_text(out)
print("ok")
