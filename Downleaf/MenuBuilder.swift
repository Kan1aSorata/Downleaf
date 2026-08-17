import AppKit

@MainActor
enum MenuBuilder {
    static func build(delegate: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        appMenu.addItem(item("关于 Downleaf", action: #selector(AppDelegate.showAbout(_:)), target: delegate))
        appMenu.addItem(.separator())
        appMenu.addItem(item("设置…", action: #selector(AppDelegate.showSettings(_:)), key: ",", target: delegate))
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "服务")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())
        appMenu.addItem(item("隐藏 Downleaf", action: #selector(NSApplication.hide(_:)), key: "h"))
        appMenu.addItem(item("隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        appMenu.addItem(item("全部显示", action: #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("退出 Downleaf", action: #selector(AppDelegate.requestQuit(_:)), key: "q", target: delegate))

        let fileMenu = NSMenu(title: "文件")
        addMenu(fileMenu, title: "文件", to: mainMenu)
        fileMenu.addItem(item("新建文稿", action: #selector(NSDocumentController.newDocument(_:)), key: "n"))
        fileMenu.addItem(item("打开…", action: #selector(NSDocumentController.openDocument(_:)), key: "o"))

        let recentItem = NSMenuItem(title: "打开最近使用", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "打开最近使用")
        recentItem.submenu = recentMenu
        recentMenu.addItem(item("清除菜单", action: #selector(NSDocumentController.clearRecentDocuments(_:))))
        fileMenu.addItem(recentItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(item("关闭", action: #selector(NSWindow.performClose(_:)), key: "w"))
        fileMenu.addItem(item("保存", action: #selector(NSDocument.save(_:)), key: "s"))
        fileMenu.addItem(item("另存为…", action: #selector(NSDocument.saveAs(_:)), key: "s", modifiers: [.command, .shift]))
        fileMenu.addItem(item("恢复到已保存版本…", action: #selector(NSDocument.revertToSaved(_:))))

        let editMenu = NSMenu(title: "编辑")
        addMenu(editMenu, title: "编辑", to: mainMenu)
        editMenu.addItem(item("撤销", action: Selector(("undo:")), key: "z"))
        editMenu.addItem(item("重做", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item("剪切", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(item("复制", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(item("粘贴", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(item("全选", action: #selector(NSText.selectAll(_:)), key: "a"))
        editMenu.addItem(.separator())

        let findItem = NSMenuItem(title: "查找", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "查找")
        findItem.submenu = findMenu
        findMenu.addItem(findPanelItem("查找…", action: .showFindPanel, key: "f"))
        findMenu.addItem(findPanelItem("查找下一个", action: .next, key: "g"))
        findMenu.addItem(findPanelItem("查找上一个", action: .previous, key: "g", modifiers: [.command, .shift]))
        editMenu.addItem(findItem)

        let formatMenu = NSMenu(title: "格式")
        addMenu(formatMenu, title: "格式", to: mainMenu)
        formatMenu.addItem(item("粗体", action: #selector(MarkdownTextView.toggleMarkdownBold(_:)), key: "b"))
        formatMenu.addItem(item("斜体", action: #selector(MarkdownTextView.toggleMarkdownItalic(_:)), key: "i"))
        formatMenu.addItem(item("行内代码", action: #selector(MarkdownTextView.toggleMarkdownCode(_:)), key: "`"))
        formatMenu.addItem(.separator())
        formatMenu.addItem(item("切换任务状态", action: #selector(MarkdownTextView.toggleTaskState(_:)), key: "\r"))

        let viewMenu = NSMenu(title: "视图")
        addMenu(viewMenu, title: "视图", to: mainMenu)
        viewMenu.addItem(item("切换编辑 / 阅读", action: #selector(AppDelegate.toggleReadingMode(_:)), key: "e", target: delegate))
        viewMenu.addItem(item("分栏预览", action: #selector(AppDelegate.showSplitMode(_:)), key: "e", modifiers: [.command, .option], target: delegate))
        viewMenu.addItem(item("源码编辑", action: #selector(AppDelegate.showEditorMode(_:)), target: delegate))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("显示 / 隐藏大纲", action: #selector(AppDelegate.toggleOutline(_:)), key: "o", modifiers: [.command, .option], target: delegate))
        viewMenu.addItem(item("跳转标题…", action: #selector(AppDelegate.focusOutline(_:)), key: "j", target: delegate))
        viewMenu.addItem(item("命令面板…", action: #selector(AppDelegate.showCommandPalette(_:)), key: "k", target: delegate))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("进入全屏幕", action: #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control]))

        let windowMenu = NSMenu(title: "窗口")
        addMenu(windowMenu, title: "窗口", to: mainMenu)
        windowMenu.addItem(item("最小化", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowMenu.addItem(item("缩放", action: #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "帮助")
        addMenu(helpMenu, title: "帮助", to: mainMenu)
        helpMenu.addItem(item("Downleaf 使用提示", action: #selector(AppDelegate.showAbout(_:)), target: delegate))
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    private static func addMenu(_ menu: NSMenu, title: String, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.addItem(item)
    }

    private static func item(
        _ title: String,
        action: Selector?,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = target
        return item
    }

    private static func findPanelItem(
        _ title: String,
        action: NSFindPanelAction,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = self.item(title, action: #selector(NSTextView.performFindPanelAction(_:)), key: key, modifiers: modifiers)
        item.tag = Int(action.rawValue)
        return item
    }
}
