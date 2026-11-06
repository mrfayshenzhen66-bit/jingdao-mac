#!/usr/bin/env python3
"""把 PersonalIcon/MRFAY_wordmark.png（白色、透明底）编码进 Windows/PersonalWordmark.swift。

build-personal.sh 只允许应用资源比官方多一个 Personal.icns，所以字标不放进资源目录，
而是作为 PNG 数据写进源码。用法：python3 Tools/make-wordmark-swift.py
"""
import base64, io, pathlib
from PIL import Image
root = pathlib.Path(__file__).resolve().parent.parent
im = Image.open(root / "PersonalIcon/MRFAY_wordmark.png").convert("RGBA")
im = im.crop(im.getchannel("A").getbbox())
w = 720                                  # 关于页里约 110 pt 宽，2× 屏足够
im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
buf = io.BytesIO(); im.save(buf, "PNG", optimize=True)
b64 = base64.b64encode(buf.getvalue()).decode()
# 多行字符串字面量，不用 + 拼接：上千段拼接会让 Swift 类型检查崩溃（signal 4）。
body = '"""\n' + "\n".join(b64[i:i + 100] for i in range(0, len(b64), 100)) + '\n"""'
out = f'''//  PersonalWordmark.swift — 生成文件，勿手改：python3 Tools/make-wordmark-swift.py
//
//  mrfay 的 MRFAY 字标（作者本人的标识图，白色、透明底，{im.width}×{im.height}）。
//  以 PNG 数据写在源码里，因为 build-personal.sh 只允许新增 Personal.icns 一个资源。

import AppKit

enum PersonalWordmark {{
    static let size = CGSize(width: {im.width}, height: {im.height})
    static let image: NSImage? = {{
        let b64 =
{body}
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {{ return nil }}
        return NSImage(data: data)
    }}()
}}
'''
(root / "Spektrafilm/Windows/PersonalWordmark.swift").write_text(out)
print("ok", im.size, len(buf.getvalue()), "bytes")
