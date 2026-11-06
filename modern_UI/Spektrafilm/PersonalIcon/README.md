# 景到 图标

`AppIcon.png`（1024 × 1024，sRGB，透明底）与 `AppIcon.svg` 是「景到」的应用图标：小孔成像。

《墨子·经下》：“景到，在午有端，与景长，说在端。”

- **物**（左）：橙色旗杆与三角旗。
- **端**（中）：米白圆点加橙色细环，表示小孔。所有光线都从这里交叉通过（“在午有端”）。
- **像**（右）：由“物”绕小孔中心对称得到，上下左右都倒过来（“景到”）。杆身用米白色表示投射出的光，挂旗那一段和旗一样是橙色，旗落到了像的最下面。
- **光线**：橙色光线从物的旗面经小孔射到像的旗面。米白光锥从物的底部经小孔射到像的顶部。
- 构图来自用户认可的概念稿（ChatGPT 生成，原稿存档在工程外的版本备份目录），已按几何关系用代码精确重画。图标中**不含** SpektraLab 官方名称、Logo 或其衍生图形。

重新生成：

```sh
python3 Tools/make-jingdao-icon.py PersonalIcon/AppIcon.png PersonalIcon/AppIcon.svg
```

`Tools/build-personal-icon.sh` 由 `AppIcon.png` 生成全部 10 个标准 ICNS 尺寸，`Tools/build-personal.sh` 把它作为 `Personal.icns` 加入应用资源。

旧版图标（官方 Logo 的精确反相、暗袋印章版及其所用照片）均已移出源码，存档于工程外的版本备份目录，不随源码分发。`Tools/make-personal-icon.swift` 仅为旧版历史工具，构建不使用。
