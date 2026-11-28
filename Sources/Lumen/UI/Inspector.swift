import SwiftUI

/// 右侧调整面板：直角、发丝线分隔，像一台精密仪器。
/// 上面是直方图，中间是当前图层的信息，下面按页展示参数（不再无限下滑）。
struct Inspector: View {
    @EnvironmentObject var doc: EditDocument

    var body: some View {
        VStack(spacing: 0) {
            HistogramPanel(histogram: doc.histogram)
            hairline

            ZStack(alignment: .top) {
                if let id = doc.selectedLayerID, doc.selectedLayer != nil {
                    LayerInspector(layer: doc.layerBinding(id))
                        .id(id)
                        .transition(.focusPull)
                } else {
                    BasicInspector(basic: $doc.state.basic)
                        .transition(.focusPull)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.45, dampingFraction: 0.88), value: doc.selectedLayerID)
        }
        .background(Ink.surface)
    }

    private var hairline: some View {
        Rectangle().fill(Ink.line).frame(height: 0.5)
    }
}

/// 面板标题区
struct InspectorHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    let english: String
    let trailing: Trailing

    init(symbol: String, title: String, english: String, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.english = english
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Ink.text)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                Text(english)
                    .font(.micro)
                    .tracking(1.8)
                    .foregroundStyle(Ink.text3)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

struct BasicInspector: View {
    @EnvironmentObject var doc: EditDocument
    @Binding var basic: BasicSettings

    var body: some View {
        VStack(spacing: 0) {
            InspectorHeader(symbol: "slider.horizontal.3", title: L("基础调整", "Basic"), english: "BASIC") {
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { doc.resetBasic() }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(BareIconStyle())
                .help(L("恢复全部基础调整", "Reset all basic adjustments"))
            }
            ScrollView(.vertical, showsIndicators: false) {
                BasicPanel(basic: $basic)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct LayerInspector: View {
    @EnvironmentObject var doc: EditDocument
    @Binding var layer: AdjustmentLayer

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: layer.kind.symbol)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Ink.text)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    TextField(L("图层名称", "Layer name"), text: $layer.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Ink.text)
                    HStack(spacing: 6) {
                        Text(layer.kind.english).font(.micro).tracking(1.8).foregroundStyle(Ink.text3)
                        HelpBadge(key: "layer.\(layer.kind.rawValue)")
                    }
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { layer.visible.toggle() }
                } label: {
                    Image(systemName: layer.visible ? "eye" : "eye.slash")
                }
                .buttonStyle(BareIconStyle())
                .help(layer.visible ? L("隐藏图层", "Hide layer") : L("显示图层", "Show layer"))

                Menu {
                    Button(L("重置参数", "Reset Settings")) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { layer.resetParams() }
                    }
                    Button(L("复制图层", "Duplicate Layer")) { doc.duplicateLayer(layer.id) }
                    Divider()
                    Button(L("上移一层", "Move Up")) { doc.moveLayer(layer.id, up: true) }
                    Button(L("下移一层", "Move Down")) { doc.moveLayer(layer.id, up: false) }
                    Divider()
                    Button(L("删除图层", "Delete Layer"), role: .destructive) { doc.deleteLayer(layer.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.text)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 4)

            HStack(spacing: 10) {
                Text(L("混合", "Blend"))
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.text2)
                Spacer()
                Picker("", selection: $layer.blendMode) {
                    ForEach(LayerBlendMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: 150, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 2)

            ScrubRow(L("不透明度", "Opacity"), value: $layer.opacity, range: 0...100, defaultValue: 100,
                     help: "opacity", suffix: "%")

            Rectangle().fill(Ink.line).frame(height: 0.5)

            ScrollView(.vertical, showsIndicators: false) {
                panel
                    .opacity(layer.visible ? 1 : 0.45)
                    .animation(.easeOut(duration: 0.2), value: layer.visible)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder private var panel: some View {
        switch layer.kind {
        case .curves: CurvesPanel(params: $layer.params.curves)
        case .levels: LevelsPanel(params: $layer.params.levels)
        case .brightnessContrast: BrightnessContrastPanel(params: $layer.params.brightnessContrast)
        case .exposure: ExposurePanel(params: $layer.params.exposure)
        case .vibrance: VibrancePanel(params: $layer.params.vibrance)
        case .hueSaturation: HueSatPanel(params: $layer.params.hueSaturation)
        case .hsl: HSLPanel(params: $layer.params.hsl)
        case .colorBalance: ColorBalancePanel(params: $layer.params.colorBalance)
        case .selectiveColor: SelectiveColorPanel(params: $layer.params.selectiveColor)
        case .channelMixer: ChannelMixerPanel(params: $layer.params.channelMixer)
        case .blackWhite: BlackWhitePanel(params: $layer.params.blackWhite)
        case .photoFilter: PhotoFilterPanel(params: $layer.params.photoFilter)
        case .gradientMap: GradientMapPanel(params: $layer.params.gradientMap)
        case .colorGrading: ColorGradingPanel(params: $layer.params.colorGrading)
        case .posterize: PosterizePanel(params: $layer.params.posterize)
        case .threshold: ThresholdPanel(params: $layer.params.threshold)
        case .invert: SimpleNotePanel(text: L("反相没有参数。用上面的不透明度控制程度；50% 时画面会变成一片灰，这是正常的。", "Invert has no settings. Use Opacity above to control the strength; at 50% the image turns flat gray, which is expected."))
        case .desaturate: SimpleNotePanel(text: L("去色会把照片直接变成灰度（按 PS 的方式取每个像素最亮和最暗通道的平均）。想精细控制每种颜色的明暗，请用「黑白」。", "Desaturate turns the photo grayscale directly (averaging each pixel's brightest and darkest channels, like Photoshop). For control over how each color renders, use Black & White."))
        case .lut: LUTPanel(layerID: layer.id, params: $layer.params.lut)
        case .shadowsHighlights: ShadowsHighlightsPanel(params: $layer.params.shadowsHighlights)
        case .hdrToning: HDRToningPanel(params: $layer.params.hdrToning)
        case .matchColor: MatchColorPanel(layerID: layer.id, params: $layer.params.matchColor)
        case .replaceColor: ReplaceColorPanel(layerID: layer.id, params: $layer.params.replaceColor)
        case .equalize: EqualizePanel(layerID: layer.id, params: $layer.params.equalize)
        }
    }
}

struct SimpleNotePanel: View {
    let text: String
    var body: some View {
        NoteText(text).padding(.top, 8)
    }
}
