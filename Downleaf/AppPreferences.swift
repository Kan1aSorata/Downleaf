import Foundation

enum AppPreferences {
    enum Key {
        static let autoSaveEnabled = "AutoSaveEnabled"
        static let outlineVisible = "OutlineVisible"
        static let outlineWidth = "OutlineWidth"
        static let editorFontSize = "EditorFontSize"
        static let showLineNumbers = "ShowLineNumbers"
        static let previewSplitFraction = "PreviewSplitFraction"
    }

    static let defaultOutlineWidth: CGFloat = 260
    static let minimumOutlineWidth: CGFloat = 180
    static let maximumOutlineWidth: CGFloat = 480
    static let minimumEditorWidth: CGFloat = 520

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.autoSaveEnabled: true,
            Key.outlineVisible: true,
            Key.outlineWidth: Double(defaultOutlineWidth),
            Key.editorFontSize: 15.0,
            Key.showLineNumbers: false,
            Key.previewSplitFraction: 0.5
        ])
    }

    static var autoSaveEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.autoSaveEnabled)
    }

    static var outlineVisible: Bool {
        get { UserDefaults.standard.bool(forKey: Key.outlineVisible) }
        set { UserDefaults.standard.set(newValue, forKey: Key.outlineVisible) }
    }

    static var outlineWidth: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: Key.outlineWidth)
            return min(max(CGFloat(stored), minimumOutlineWidth), maximumOutlineWidth)
        }
        set {
            let clamped = min(max(newValue, minimumOutlineWidth), maximumOutlineWidth)
            UserDefaults.standard.set(Double(clamped), forKey: Key.outlineWidth)
        }
    }

    static var editorFontSize: CGFloat {
        let stored = UserDefaults.standard.double(forKey: Key.editorFontSize)
        return min(max(CGFloat(stored), 12), 24)
    }

    static var previewSplitFraction: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: Key.previewSplitFraction)
            return min(max(CGFloat(stored), 0.25), 0.75)
        }
        set {
            let clamped = min(max(newValue, 0.25), 0.75)
            UserDefaults.standard.set(Double(clamped), forKey: Key.previewSplitFraction)
        }
    }
}
