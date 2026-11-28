import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var doc: EditDocument
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            LayerSidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 300)
        } detail: {
            CanvasView()
                .inspector(isPresented: $doc.showInspector) {
                    Inspector()
                        .inspectorColumnWidth(min: 320, ideal: 336, max: 420)
                }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $doc.showExportSheet) {
            ExportSheet().environmentObject(doc)
        }
        .tint(Color(red: 0.36, green: 0.36, blue: 0.38))
        .preferredColorScheme(.light)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(doc.hasImage ? doc.fileName : "Lumen")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                Text(doc.hasImage ? "\(Int(doc.imageSize.width)) × \(Int(doc.imageSize.height)) · Display P3" : L("光调", "Light & Tone"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Ink.text3)
            }
            .frame(minWidth: 200)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { doc.presentOpenPanel() } label: {
                Label(L("打开", "Open"), systemImage: "photo.on.rectangle")
            }
            .help(L("打开照片 ⌘O", "Open photos ⌘O"))

            Menu {
                Button(L("拷贝调整", "Copy Adjustments")) { doc.copyAdjustments() }
                    .disabled(!doc.hasImage)
                Button(L("粘贴调整", "Paste Adjustments")) { doc.pasteAdjustments() }
                    .disabled(doc.clipboard == nil || !doc.hasImage)
                Button(L("同步当前调整到全部照片", "Sync Current Adjustments to All Photos")) { doc.applyCurrentToAll() }
                    .disabled(doc.filmstrip.count < 2)
                Divider()
                Button(L("保存当前为预设…", "Save as Preset…")) { doc.savePreset() }
                Button(L("载入预设…", "Load Preset…")) { doc.loadPreset() }
                Divider()
                Button(L("导出 LUT（.cube）…", "Export LUT (.cube)…")) { doc.exportLUT() }
                Divider()
                Picker(L("语言", "Language"), selection: $lang.language) {
                    ForEach(AppLanguage.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }
                Divider()
                Button(L("全部重置", "Reset All")) { doc.resetAll() }
            } label: {
                Label(L("更多", "More"), systemImage: "ellipsis.circle")
            }
            .help(L("预设与 LUT", "Presets and LUTs"))

            Button { doc.showExportSheet = true } label: {
                Text(L("导出", "Export"))
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
            .disabled(!doc.hasImage)
            .opacity(doc.hasImage ? 1 : 0.45)
            .help(L("导出照片 ⌘E", "Export photo ⌘E"))

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { doc.showInspector.toggle() }
            } label: {
                Label(L("调整面板", "Adjustments"), systemImage: "sidebar.trailing")
            }
            .help(L("显示或隐藏调整面板", "Show or hide the adjustments panel"))
        }
    }
}

// MARK: - 导出

struct ExportSheet: View {
    @EnvironmentObject var doc: EditDocument
    @Environment(\.dismiss) private var dismiss
    @State private var format: RenderEngine.ExportFormat = .jpeg
    @State private var quality: Double = 92
    @State private var sizeOption: Int = 0
    @State private var batchAll: Bool = false

    private let sizes: [(String, CGFloat?)] = [(L("原尺寸", "Original"), nil), ("3840", 3840), ("2048", 2048), ("1080", 1080)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("导出", "Export")).font(.system(size: 20, weight: .semibold)).foregroundStyle(Ink.text)
                Text(L("按原图分辨率重新计算全部调整", "All adjustments are recalculated at full resolution"))
                    .font(.system(size: 11.5)).foregroundStyle(Ink.text3)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Rectangle().fill(Ink.line).frame(height: 0.5)

            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("Format")
                InkSegment(RenderEngine.ExportFormat.allCases.map { ($0, $0.rawValue) }, selection: $format)
                Text(formatHint).font(.system(size: 11)).foregroundStyle(Ink.text3)
                    .animation(nil, value: format)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            if format == .jpeg || format == .heic {
                ScrubRow(L("画质", "Quality"), value: $quality, range: 50...100, defaultValue: 92, help: "export.quality")
                    .padding(.horizontal, 4)
                    .transition(.focusPull)
            }

            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("Long edge", trailing: "PX")
                InkSegment(sizes.indices.map { ($0, sizes[$0].0) }, selection: $sizeOption)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            if doc.filmstrip.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    MicroLabel("Scope")
                    InkSegment([
                        (false, L("当前照片", "Current Photo")),
                        (true, L("全部 \(doc.filmstrip.count) 张照片", "All \(doc.filmstrip.count) Photos"))
                    ], selection: $batchAll)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }

            Rectangle().fill(Ink.line).frame(height: 0.5)

            HStack {
                Button(L("取消", "Cancel")) { dismiss() }
                    .buttonStyle(GlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(batchAll ? L("选择文件夹并批量导出", "Choose Folder & Batch Export") : L("选择位置并导出", "Choose Location & Export")) {
                    if batchAll && doc.filmstrip.count > 1 {
                        doc.exportAll(format: format, quality: quality / 100, maxSide: sizes[sizeOption].1)
                    } else {
                        doc.export(format: format, quality: quality / 100, maxSide: sizes[sizeOption].1)
                    }
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 400)
        .background(Ink.surface)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: format)
    }

    private var formatHint: String {
        switch format {
        case .jpeg: return L("最通用，分享、发给别人都用它", "The most compatible — for sharing and sending")
        case .heic: return L("画质和 JPEG 相同，体积更小，苹果设备都能看", "Same quality as JPEG, smaller files, opens on all Apple devices")
        case .png: return L("无损，文件较大，适合带文字的图", "Lossless with larger files — good for images with text")
        case .tiff: return L("16 位无损，适合之后继续修图或印刷", "16-bit lossless — for further retouching or print")
        }
    }
}
