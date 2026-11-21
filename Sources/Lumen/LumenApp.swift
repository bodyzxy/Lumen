import SwiftUI
import AppKit

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var doc = EditDocument()

    var body: some Scene {
        Window("Lumen", id: "main") {
            RootView()
                .environmentObject(doc)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1440, height: 900)
        .commands { LumenCommands(doc: doc) }

        Settings {
            SettingsView()
        }
    }
}

/// 根视图：负责切换语言时的过渡（先轻微失焦，换好文字后再对焦回来）
struct RootView: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var shown = LanguageSettings.current
    @State private var veil = false

    var body: some View {
        ContentView()
            .id(shown)
            .blur(radius: veil ? 12 : 0)
            .opacity(veil ? 0.55 : 1)
            .onChange(of: lang.language) { _, newValue in
                withAnimation(.easeIn(duration: 0.18)) { veil = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    shown = newValue
                    withAnimation(.timingCurve(0.16, 0.8, 0.24, 1, duration: 0.6)) { veil = false }
                }
            }
    }
}

/// 偏好设置（⌘,）
struct SettingsView: View {
    @ObservedObject private var lang = LanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("语言", "Language"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.text)
            InkSegment(AppLanguage.allCases.map { ($0, $0.displayName) }, selection: $lang.language)
                .frame(width: 220)
            Text(L("切换后界面文字和参数说明会立即更新。", "Interface text and help update immediately."))
                .font(.system(size: 11.5))
                .foregroundStyle(Ink.text3)
        }
        .padding(24)
        .frame(width: 360)
        .id(lang.language)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 用 swift run 直接运行时也能正常显示在程序坞、获得焦点
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.appearance = NSAppearance(named: .aqua)
        // 程序坞图标：打包后的 App 用 Resources 里的 AppIcon.icns，开发运行时用资源包里的 PNG
        if Bundle.main.url(forResource: "AppIcon", withExtension: "icns") == nil,
           let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct LumenCommands: Commands {
    @ObservedObject var doc: EditDocument
    @ObservedObject var lang = LanguageSettings.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("打开照片…", "Open Photos…")) { doc.presentOpenPanel() }
                .keyboardShortcut("o")
            Button(L("关闭当前照片", "Close Photo")) { if let id = doc.activeID { doc.closeSession(id) } }
                .disabled(doc.activeID == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button(L("拷贝调整", "Copy Adjustments")) { doc.copyAdjustments() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!doc.hasImage)
            Button(L("粘贴调整", "Paste Adjustments")) { doc.pasteAdjustments() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(doc.clipboard == nil || !doc.hasImage)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(L("撤销", "Undo")) { doc.undo() }
                .keyboardShortcut("z")
                .disabled(!doc.canUndo)
            Button(L("重做", "Redo")) { doc.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!doc.canRedo)
        }
        CommandGroup(replacing: .saveItem) {
            Button(L("导出照片…", "Export Photo…")) { doc.showExportSheet = true }
                .keyboardShortcut("e")
                .disabled(doc.previewImage == nil)
            Button(L("导出 LUT…", "Export LUT…")) { doc.exportLUT() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button(L("保存预设…", "Save Preset…")) { doc.savePreset() }
                .keyboardShortcut("s")
            Button(L("载入预设…", "Load Preset…")) { doc.loadPreset() }
                .keyboardShortcut("l")
        }
        CommandMenu(L("图层", "Layers")) {
            ForEach(LayerKind.groups.indices, id: \.self) { gi in
                Section(LayerKind.groups[gi].0) {
                    ForEach(LayerKind.groups[gi].1) { kind in
                        Button(L("添加\(kind.title)", "Add \(kind.title)")) { doc.addLayer(kind) }
                    }
                }
            }
            Divider()
            Button(L("删除当前图层", "Delete Layer")) {
                if let id = doc.selectedLayerID { doc.deleteLayer(id) }
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(doc.selectedLayerID == nil)
            Button(L("全部重置", "Reset All")) { doc.resetAll() }
        }
        CommandMenu(L("视图", "View")) {
            Button(doc.compareMode == .split ? L("关闭左右对比", "Hide Split View") : L("左右对比", "Split View")) {
                doc.compareMode = doc.compareMode == .split ? .off : .split
            }
            .keyboardShortcut("\\", modifiers: [])
            Picker(L("语言", "Language"), selection: $lang.language) {
                ForEach(AppLanguage.allCases) { l in
                    Text(l.displayName).tag(l)
                }
            }
            Divider()
            Button(L("适应窗口", "Fit to Window")) { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { doc.zoomToFit() } }
                .keyboardShortcut("0")
            Button(L("100% 原始像素", "Actual Pixels (100%)")) { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { doc.toggleActualSize() } }
                .keyboardShortcut("1")
            Button(L("放大", "Zoom In")) { withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { doc.setZoom(doc.zoom * 1.5) } }
                .keyboardShortcut("=")
            Button(L("缩小", "Zoom Out")) { withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { doc.setZoom(doc.zoom / 1.5) } }
                .keyboardShortcut("-")
        }
    }
}
