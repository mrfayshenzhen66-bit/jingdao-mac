import AppKit
import Observation

/// SwiftUI owns the menu actions and validation. AppKit owns the standard
/// File/Edit/Window/Help labels, which do not follow the app's live language
/// preference. Translate only those labels, retaining every original item.
@MainActor
final class NativeMenuLocalization {
    private var observers: [NSObjectProtocol] = []
    private var scheduled = false
    private var applying = false
    private var active = false

    func start() {
        guard !active else { return }
        active = true
        let center = NotificationCenter.default
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification,
                     NSMenu.didBeginTrackingNotification, NSWindow.didBecomeKeyNotification,
                     NSApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestUpdate() }
            })
        }
        observeLanguage()
        requestUpdate()
    }

    func stop() {
        active = false
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    private func observeLanguage() {
        guard active else { return }
        withObservationTracking {
            _ = Localization.shared.resolved
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.active else { return }
                self.observeLanguage()
                self.requestUpdate()
            }
        }
    }

    private func requestUpdate() {
        guard active, !applying, !scheduled else { return }
        scheduled = true
        // SwiftUI may rebuild a menu in the same event that changed language.
        // Run after that update; our own title changes are ignored below.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            if self.active { self.updateMenus() }
        }
    }

    func updateMenus() {
        guard !applying, let main = NSApp.mainMenu else { return }
        applying = true
        defer { applying = false }
        let chinese = Localization.shared.resolved == .simplifiedChinese
        for (index, item) in main.items.enumerated() {
            guard let submenu = item.submenu else { continue }
            if let title = translated(item.title, in: Self.topTitles, chinese: chinese) {
                setTitle(title, on: item)
                translateItems(in: submenu, chinese: chinese)
            } else if index == 0 {
                // The product name stays a product name.
                translateItems(in: submenu, chinese: chinese)
            }
        }
        // Ordinary Window scenes remain ordinary Window scenes. Updating an
        // already-open title also covers a language switch while it is open.
        for window in NSApp.windows {
            if let title = translated(window.title, in: Self.sceneTitles, chinese: chinese),
               window.title != title { window.title = title }
        }
    }

    private func translateItems(in menu: NSMenu, chinese: Bool) {
        // Service names belong to their supplying apps, not SpektraLab.
        guard menu !== NSApp.servicesMenu else { return }
        for item in menu.items where !item.isSeparatorItem {
            let action = item.action.map(NSStringFromSelector)
            let title: String?
            switch action {
            case "hide:": title = chinese ? "隐藏 \(appName)" : "Hide \(appName)"
            case "terminate:": title = chinese ? "退出 \(appName)" : "Quit \(appName)"
            case "orderFrontStandardAboutPanel:":
                title = chinese ? "关于 \(appName)" : "About \(appName)"
            case "showHelp:": title = chinese ? "\(appName) 帮助" : "\(appName) Help"
            case "makeKeyAndOrderFront:":
                // A photograph or other arbitrary window name is user data.
                title = translated(item.title, in: Self.sceneTitles, chinese: chinese)
            default:
                // Exact titles, not a blanket action-to-title mapping: Undo
                // and Redo may acquire a native, dynamically validated name.
                title = translated(item.title, in: Self.standardTitles, chinese: chinese)
            }
            if let title { setTitle(title, on: item) }
            if let submenu = item.submenu { translateItems(in: submenu, chinese: chinese) }
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }

    private func setTitle(_ title: String, on item: NSMenuItem) {
        if item.title != title { item.title = title }
        if let menu = item.submenu, menu.title != title { menu.title = title }
    }

    private func translated(_ title: String, in pairs: [(String, String)], chinese: Bool) -> String? {
        guard let pair = pairs.first(where: { title == $0.0 || title == $0.1 }) else { return nil }
        return chinese ? pair.1 : pair.0
    }

    private static let topTitles = [
        ("File", "文件"), ("Edit", "编辑"), ("View", "视图"),
        ("Window", "窗口"), ("Help", "帮助")
    ]

    private static let sceneTitles = [
        ("Settings", "设置"), ("Export", "导出"), ("About Jingdao", "关于景到")
    ]

    private static let standardTitles = [
        ("Services", "服务"), ("Hide Others", "隐藏其他"), ("Show All", "全部显示"),
        ("Close", "关闭"), ("Close All", "全部关闭"),
        ("Save", "保存"), ("Save…", "保存…"), ("Save As…", "另存为…"),
        ("Page Setup…", "页面设置…"), ("Print…", "打印…"),
        ("Undo", "撤销"), ("Redo", "重做"),
        ("Undo Typing", "撤销输入"), ("Redo Typing", "重做输入"),
        ("Cut", "剪切"), ("Copy", "复制"), ("Paste", "粘贴"),
        ("Paste and Match Style", "粘贴并匹配样式"), ("Delete", "删除"), ("Select All", "全选"),
        ("AutoFill", "自动填充"), ("Contact…", "联系人…"),
        ("Passwords…", "密码…"), ("Credit Card…", "信用卡…"),
        ("Start Dictation…", "开始听写…"), ("Stop Dictation", "停止听写"),
        ("Emoji & Symbols", "表情与符号"),
        ("Spelling and Grammar", "拼写和语法"), ("Show Spelling and Grammar", "显示拼写和语法"),
        ("Check Document Now", "立即检查文稿"), ("Check Spelling While Typing", "键入时检查拼写"),
        ("Check Grammar With Spelling", "随拼写检查语法"), ("Correct Spelling Automatically", "自动纠正拼写"),
        ("Substitutions", "替换"), ("Show Substitutions", "显示替换"),
        ("Smart Copy/Paste", "智能复制／粘贴"), ("Smart Quotes", "智能引号"),
        ("Smart Dashes", "智能破折号"), ("Smart Links", "智能链接"),
        ("Data Detectors", "数据检测器"), ("Text Replacement", "文本替换"),
        ("Transformations", "转换"), ("Make Upper Case", "大写"),
        ("Make Lower Case", "小写"), ("Capitalize", "首字母大写"),
        ("Speech", "语音"), ("Start Speaking", "开始朗读"), ("Stop Speaking", "停止朗读"),
        ("Toggle Sidebar", "切换侧栏"), ("Show Sidebar", "显示侧栏"), ("Hide Sidebar", "隐藏侧栏"),
        ("Show Toolbar", "显示工具栏"), ("Hide Toolbar", "隐藏工具栏"),
        ("Customize Toolbar…", "自定工具栏…"),
        ("Enter Full Screen", "进入全屏"), ("Exit Full Screen", "退出全屏"),
        ("Minimize", "最小化"), ("Minimize All", "全部最小化"), ("Zoom", "缩放"),
        ("Bring All to Front", "前置全部窗口"), ("Show Tab Bar", "显示标签栏"),
        ("Hide Tab Bar", "隐藏标签栏"), ("Show All Tabs", "显示所有标签页"),
        ("Merge All Windows", "合并所有窗口"), ("Move Tab to New Window", "将标签页移到新窗口"),
        ("Select Next Tab", "选择下一个标签页"), ("Select Previous Tab", "选择上一个标签页"),
        ("Move & Resize", "移动与调整大小"), ("Fill", "填充"), ("Center", "居中"),
        ("Left", "左侧"), ("Right", "右侧"), ("Top", "顶部"), ("Bottom", "底部"),
        ("Top Left", "左上"), ("Top Right", "右上"), ("Bottom Left", "左下"), ("Bottom Right", "右下"),
        ("Return to Previous Size", "恢复之前的大小"),
        ("Tile Window to Left of Screen", "将窗口平铺到屏幕左侧"),
        ("Tile Window to Right of Screen", "将窗口平铺到屏幕右侧"),
        ("Search", "搜索"), ("Settings", "设置"), ("Export", "导出"),
        ("About Jingdao", "关于景到")
    ]
}
