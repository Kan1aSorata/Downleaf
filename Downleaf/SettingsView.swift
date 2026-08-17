import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferences.Key.autoSaveEnabled) private var autoSaveEnabled = true
    @AppStorage(AppPreferences.Key.editorFontSize) private var editorFontSize = 15.0

    var body: some View {
        Form {
            Section("保存") {
                Toggle("自动保存已有路径的文稿", isOn: $autoSaveEnabled)
                Text("未命名文稿只保存在恢复缓冲区，不会自动选择最终位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("编辑器") {
                HStack {
                    Text("字号")
                    Spacer()
                    Stepper(value: $editorFontSize, in: 12...24, step: 1) {
                        Text("\(Int(editorFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }

            Section("隐私") {
                Label("完全本地运行，不含账号、同步或遥测。", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 330)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let host = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: host)
        window.title = "Downleaf 设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
