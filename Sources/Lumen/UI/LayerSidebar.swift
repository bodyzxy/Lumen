import SwiftUI

struct LayerSidebar: View {
    @EnvironmentObject var doc: EditDocument
    @State private var showPalette = false

    private var selection: Binding<UUID?> {
        Binding(
            get: { doc.selectedLayerID ?? EditDocument.basicID },
            set: { id in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    doc.selectedLayerID = (id == nil || id == EditDocument.basicID) ? nil : id
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section {
                if doc.state.layers.isEmpty {
                    Text(L("还没有调整图层", "No adjustment layers yet"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ink.text3)
                        .padding(.vertical, 4)
                        .selectionDisabled()
                }
                ForEach(Array(doc.state.layers.reversed())) { layer in
                    LayerRow(layer: layer)
                        .tag(layer.id)
                        .transition(.focusPull)
                }
                .onMove { from, to in
                    var display = Array(doc.state.layers.reversed())
                    display.move(fromOffsets: from, toOffset: to)
                    doc.state.layers = Array(display.reversed())
                }
            } header: {
                HStack(spacing: 6) {
                    Text(L("图层", "Layers"))
                    HelpBadge(key: "layers")
                    Spacer()
                    Button {
                        showPalette = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(BareIconStyle(size: 22))
                    .disabled(!doc.hasImage)
                    .opacity(doc.hasImage ? 1 : 0.35)
                    .help(doc.hasImage ? L("添加调整图层", "Add adjustment layer") : L("先打开一张照片", "Open a photo first"))
                    .popover(isPresented: $showPalette, arrowEdge: .trailing) {
                        AdjustmentPalette { kind in
                            showPalette = false
                            doc.addLayer(kind)
                        }
                    }
                }
            }

            Section(L("基础", "Basic")) {
                BasicRow()
                    .tag(EditDocument.basicID)
            }

            // 没有照片时不显示风格（缩略图是用你的照片生成的）
            if doc.hasImage {
                Section(L("风格", "Looks")) {
                    PresetGrid()
                        .selectionDisabled()
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 10, trailing: 8))
                        .transition(.focusPull)
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: doc.hasImage)
    }
}

struct LayerRow: View {
    @EnvironmentObject var doc: EditDocument
    let layer: AdjustmentLayer
    @State private var hover = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: layer.kind.symbol)
                .font(.system(size: 12))
                .frame(width: 18)
                .foregroundStyle(layer.visible ? Ink.text2 : Ink.text3)
            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(layer.visible ? Ink.text : Ink.text3)
                    .strikethrough(!layer.visible, color: Ink.text3)
                    .lineLimit(1)
                if layer.opacity < 100 || layer.blendMode != .normal {
                    HStack(spacing: 5) {
                        if layer.blendMode != .normal {
                            Text(layer.blendMode.title)
                        }
                        if layer.opacity < 100 {
                            Text("\(Int(layer.opacity))%")
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Ink.text3)
                }
            }
            Spacer(minLength: 4)
            if hover || !layer.visible {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { doc.toggleVisible(layer.id) }
                } label: {
                    Image(systemName: layer.visible ? "eye" : "eye.slash")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(BareIconStyle(size: 20))
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .contextMenu {
            Button(L("复制图层", "Duplicate Layer")) { doc.duplicateLayer(layer.id) }
            Button(L("上移一层", "Move Up")) { doc.moveLayer(layer.id, up: true) }
            Button(L("下移一层", "Move Down")) { doc.moveLayer(layer.id, up: false) }
            Button(layer.visible ? L("隐藏", "Hide") : L("显示", "Show")) { doc.toggleVisible(layer.id) }
            Divider()
            Button(L("删除图层", "Delete Layer"), role: .destructive) { doc.deleteLayer(layer.id) }
        }
    }
}

struct BasicRow: View {
    @EnvironmentObject var doc: EditDocument
    private var modified: Bool { doc.state.basic != BasicSettings() }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .frame(width: 18)
                .foregroundStyle(Ink.text2)
            Text(L("基础调整", "Basic")).font(.system(size: 12.5)).foregroundStyle(Ink.text)
            Spacer()
            if modified {
                Circle().fill(Ink.text).frame(width: 5, height: 5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: modified)
    }
}

// MARK: - 风格缩略图：直接在当前照片上预览每种风格

struct PresetGrid: View {
    @EnvironmentObject var doc: EditDocument

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 12) {
            ForEach(BuiltInPreset.all) { preset in
                PresetTile(preset: preset, image: doc.presetThumbnails[preset.key])
            }
        }
    }
}

struct PresetTile: View {
    @EnvironmentObject var doc: EditDocument
    let preset: BuiltInPreset
    let image: CGImage?
    @State private var hover = false

    var body: some View {
        Button {
            doc.applyBuiltInPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    Rectangle().fill(Ink.washStrong)
                    if let img = image {
                        Image(decorative: img, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                .frame(height: 62)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(hover ? 0.14 : 0), radius: 8, x: 0, y: 4)
                .scaleEffect(hover ? 1.035 : 1)

                Text(preset.name)
                    .font(.system(size: 11))
                    .foregroundStyle(hover ? Ink.text : Ink.text2)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(preset.subtitle)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { hover = h } }
        .disabled(!doc.hasImage)
    }
}

// MARK: - 添加调整的面板
//
// 横向四列，和 PS「图像 › 调整」菜单同样的分组；高度固定、不滚动，不会超出窗口。
// 顶部有搜索框：直接打字筛选，回车添加第一项。

struct AdjustmentPalette: View {
    let onPick: (LayerKind) -> Void
    @State private var appeared = false
    @State private var query = ""

    static let columnWidth: CGFloat = 156
    private static let gap: CGFloat = 14
    private static let panelWidth: CGFloat = gap * 2 + columnWidth * 4 + gap * 3

    /// 四列的分组安排
    static var columns: [[PaletteGroup]] { [
        [PaletteGroup(title: L("明暗", "Tone"), kinds: [.brightnessContrast, .levels, .curves, .exposure]),
         PaletteGroup(title: L("影调", "Light"), kinds: [.shadowsHighlights, .hdrToning])],
        [PaletteGroup(title: L("色彩", "Color"), kinds: [.vibrance, .hueSaturation, .colorBalance, .blackWhite, .photoFilter, .channelMixer, .lut])],
        [PaletteGroup(title: L("特殊", "Special"), kinds: [.invert, .posterize, .threshold, .gradientMap, .selectiveColor])],
        [PaletteGroup(title: L("图像", "Image"), kinds: [.desaturate, .matchColor, .replaceColor, .equalize]),
         PaletteGroup(title: "Camera Raw", kinds: [.hsl, .colorGrading])]
    ] }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var results: [LayerKind] {
        let q = trimmedQuery
        if q.isEmpty { return [] }
        return LayerKind.allCases.filter { kind in
            kind.title.lowercased().contains(q) || kind.english.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaletteSearchField(query: $query) {
                if let first = results.first { onPick(first) }
            }
            Rectangle().fill(Ink.line).frame(height: 0.5)
            content
                .padding(AdjustmentPalette.gap)
                .frame(width: AdjustmentPalette.panelWidth, height: 300, alignment: .topLeading)
                .animation(.spring(response: 0.4, dampingFraction: 0.88), value: trimmedQuery.isEmpty)
        }
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            PaletteColumns(appeared: appeared, onPick: onPick)
                .transition(.focusPull)
        } else {
            PaletteResults(query: query, results: results, onPick: onPick)
                .transition(.focusPull)
        }
    }
}

struct PaletteGroup {
    let title: String
    let kinds: [LayerKind]
}

private struct PaletteSearchField: View {
    @Binding var query: String
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Ink.text3)
            TextField(L("搜索调整，例如 曲线、HSL、色阶", "Search adjustments — e.g. Curves, HSL, Levels"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(onSubmit)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.text3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }
}

private struct PaletteColumns: View {
    let appeared: Bool
    let onPick: (LayerKind) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(0..<AdjustmentPalette.columns.count, id: \.self) { ci in
                PaletteColumn(groups: AdjustmentPalette.columns[ci], columnIndex: ci,
                              appeared: appeared, onPick: onPick)
            }
        }
    }
}

private struct PaletteColumn: View {
    let groups: [PaletteGroup]
    let columnIndex: Int
    let appeared: Bool
    let onPick: (LayerKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<groups.count, id: \.self) { gi in
                PaletteGroupView(group: groups[gi], baseDelay: Double(columnIndex) * 0.045 + Double(gi) * 0.06,
                                 appeared: appeared, onPick: onPick)
            }
        }
        .frame(width: AdjustmentPalette.columnWidth, alignment: .topLeading)
    }
}

private struct PaletteGroupView: View {
    let group: PaletteGroup
    let baseDelay: Double
    let appeared: Bool
    let onPick: (LayerKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MicroLabel(group.title)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ForEach(0..<group.kinds.count, id: \.self) { i in
                StaggeredRow(kind: group.kinds[i], delay: baseDelay + Double(i) * 0.016,
                             appeared: appeared, onPick: onPick)
            }
        }
    }
}

/// 错落浮现的一行
private struct StaggeredRow: View {
    let kind: LayerKind
    let delay: Double
    let appeared: Bool
    let onPick: (LayerKind) -> Void

    var body: some View {
        let anim = Animation.spring(response: 0.45, dampingFraction: 0.82).delay(delay)
        return PaletteRow(kind: kind) { onPick(kind) }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .blur(radius: appeared ? 0 : 3)
            .animation(anim, value: appeared)
    }
}

private struct PaletteResults: View {
    let query: String
    let results: [LayerKind]
    let onPick: (LayerKind) -> Void

    private let grid: [GridItem] = Array(repeating: GridItem(.fixed(AdjustmentPalette.columnWidth), spacing: 14, alignment: .leading), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if results.isEmpty {
                Text(L("没有找到“\(query)”", "Nothing found for “\(query)”"))
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.text3)
                    .padding(8)
            } else {
                MicroLabel("Results", trailing: L("⏎ 添加第一项", "⏎ adds the first"))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                LazyVGrid(columns: grid, alignment: .leading, spacing: 2) {
                    ForEach(results) { kind in
                        PaletteRow(kind: kind, highlighted: kind == results.first) { onPick(kind) }
                    }
                }
            }
        }
    }
}

struct PaletteRow: View {
    let kind: LayerKind
    var highlighted = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 12, weight: .light))
                    .frame(width: 16)
                Text(kind.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(hover || highlighted ? Color.white : Ink.text)
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hover || highlighted ? Ink.text : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help(HelpTexts.entry("layer.\(kind.rawValue)").what)
    }
}
