import SwiftUI

// MARK: - 渐变映射：直接在渐变条上点击添加、拖动、拖离删除色标

struct GradientMapPanel: View {
    @Binding var params: GradientMapParams
    @State private var selectedID: UUID?

    private let presets: [(String, [(Double, UInt32)])] = [
        (L("黑白", "Black & White"), [(0, 0x000000), (1, 0xFFFFFF)]),
        (L("棕褐", "Sepia"), [(0, 0x1E120A), (0.55, 0x8C6A45), (1, 0xF5E6C8)]),
        (L("青橙", "Teal/Orange"), [(0, 0x0B2733), (0.5, 0x5E7C7A), (1, 0xFFC27A)]),
        (L("紫粉", "Violet/Pink"), [(0, 0x1A0B3D), (0.5, 0xC2378F), (1, 0xFFD3E6)]),
        (L("冷夜", "Cold Night"), [(0, 0x050B1C), (0.6, 0x3A5A8C), (1, 0xDDE8FF)]),
        (L("暖金", "Warm Gold"), [(0, 0x2B1600), (0.5, 0xB5762A), (1, 0xFFF2CC)]),
        (L("墨绿", "Deep Green"), [(0, 0x08140F), (0.5, 0x4E6B55), (1, 0xEEF2E2)]),
        (L("铜版", "Copper"), [(0, 0x120A08), (0.5, 0x7A4E3C), (1, 0xF6E2D3)])
    ]

    private var selectedBinding: Binding<GradientStop>? {
        guard let id = selectedID, params.stops.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { params.stops.first(where: { $0.id == id }) ?? GradientStop(position: 0, color: .black) },
            set: { nv in if let i = params.stops.firstIndex(where: { $0.id == id }) { params.stops[i] = nv } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                MicroLabel("Gradient")
                HelpBadge(key: "gm.stops")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            GradientEditorBar(params: $params, selectedID: $selectedID)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            HStack {
                Text(L("暗部", "Shadows")).font(.system(size: 10)).foregroundStyle(Ink.text3)
                Spacer()
                Text(L("亮部", "Highlights")).font(.system(size: 10)).foregroundStyle(Ink.text3)
            }
            .padding(.horizontal, 18)

            ZStack(alignment: .top) {
                if let stop = selectedBinding {
                    HStack(alignment: .center, spacing: 0) {
                        ColorPicker("", selection: colorBinding(stop.color), supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 36)
                            .padding(.leading, 18)
                        ScrubRow(L("位置", "Position"), value: Binding(get: { stop.wrappedValue.position * 100 },
                                                      set: { stop.wrappedValue.position = $0 / 100 }),
                                 range: 0...100, defaultValue: stop.wrappedValue.position * 100,
                                 help: "gm.position", hint: Hint.tone, suffix: "%")
                    }
                    .id(selectedID)
                    .transition(.focusPull)
                } else {
                    NoteText(L("点渐变条添加色标，点色标可改颜色，把色标往下拖离即可删除。", "Click the bar to add a stop, click a stop to change its color, drag a stop down and away to delete it."))
                        .transition(.focusPull)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedID)
            .padding(.vertical, 4)

            MicroLabel("Presets").padding(.horizontal, 18).padding(.top, 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(presets.indices, id: \.self) { i in
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            params.stops = presets[i].1.map { GradientStop(position: $0.0, color: RGBColor(hex: $0.1)) }
                            selectedID = nil
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            LinearGradient(colors: presets[i].1.map { Color(rgb: RGBColor(hex: $0.1)) },
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(height: 14)
                                .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 0.5))
                            Text(presets[i].0).font(.system(size: 10)).foregroundStyle(Ink.text2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            InkToggleRow(title: L("反向", "Reverse"), isOn: $params.reverse, help: "gm.reverse")
        }
    }
}

struct GradientEditorBar: View {
    @Binding var params: GradientMapParams
    @Binding var selectedID: UUID?
    @State private var removing: UUID?

    private var sorted: [GradientStop] { params.stops.sorted { $0.position < $1.position } }

    private func colorAt(_ t: Double) -> RGBColor {
        let s = sorted
        guard let first = s.first, let last = s.last else { return .black }
        if t <= first.position { return first.color }
        if t >= last.position { return last.color }
        for i in 0..<(s.count - 1) where t >= s[i].position && t <= s[i + 1].position {
            let k = (t - s[i].position) / max(s[i + 1].position - s[i].position, 1e-6)
            let a = s[i].color, b = s[i + 1].color
            return RGBColor(r: CM.mix(a.r, b.r, k), g: CM.mix(a.g, b.g, k), b: CM.mix(a.b, b.b, k))
        }
        return last.color
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                LinearGradient(stops: sorted.map { Gradient.Stop(color: Color(rgb: $0.color), location: $0.position) },
                               startPoint: params.reverse ? .trailing : .leading,
                               endPoint: params.reverse ? .leading : .trailing)
                    .frame(width: w, height: 26)
                    .overlay(Rectangle().strokeBorder(Ink.lineStrong, lineWidth: 0.5))
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { t in
                            guard params.stops.count < 8 else { return }
                            let pos = CM.clamp(Double(t.location.x / w))
                            let stop = GradientStop(position: pos, color: colorAt(pos))
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                params.stops.append(stop)
                                selectedID = stop.id
                            }
                        }
                    )

                ForEach(params.stops) { stop in
                    let selected = stop.id == selectedID
                    VStack(spacing: 0) {
                        Rectangle().fill(Ink.text.opacity(0.5)).frame(width: 0.5, height: 6)
                        Rectangle()
                            .fill(Color(rgb: stop.color))
                            .frame(width: 13, height: 13)
                            .overlay(Rectangle().strokeBorder(Ink.text, lineWidth: selected ? 1.6 : 0.8))
                            .overlay(Rectangle().strokeBorder(Color.white, lineWidth: 0.6).padding(selected ? 1.6 : 0.8))
                    }
                    .scaleEffect(selected ? 1.15 : 1)
                    .opacity(removing == stop.id ? 0.25 : 1)
                    .position(x: CGFloat(stop.position) * w, y: 26 + 12)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("gbar"))
                            .onChanged { d in
                                selectedID = stop.id
                                if let i = params.stops.firstIndex(where: { $0.id == stop.id }) {
                                    params.stops[i].position = CM.clamp(Double(d.location.x / w))
                                }
                                let away = d.location.y > 70 && params.stops.count > 2
                                if away != (removing == stop.id) {
                                    withAnimation(.easeOut(duration: 0.15)) { removing = away ? stop.id : nil }
                                }
                            }
                            .onEnded { _ in
                                if removing == stop.id {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        params.stops.removeAll { $0.id == stop.id }
                                        selectedID = nil
                                        removing = nil
                                    }
                                }
                            }
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
                }
            }
            .coordinateSpace(name: "gbar")
        }
        .frame(height: 50)
    }
}

// MARK: - 颜色分级

struct ColorGradingPanel: View {
    @Binding var params: ColorGradingParams
    @State private var tab = 1

    private func wheel(_ t: Int) -> Binding<ToneWheel> {
        switch t {
        case 0: return $params.shadows
        case 2: return $params.highlights
        case 3: return $params.global
        default: return $params.midtones
        }
    }

    var body: some View {
        Pager([L("阴影", "Shadows"), L("中间调", "Midtones"), L("高光", "Highlights"), L("全局", "Global"), L("混合", "Blend")], selection: $tab) { t in
            if t == 4 {
                Group0 {
                    ScrubRow(L("混合", "Blend"), value: $params.blending, range: 0...100, defaultValue: 50, help: "cg.blending")
                    ScrubRow(L("平衡", "Balance"), value: $params.balance, range: -100...100, help: "cg.balance", hint: Hint.tone)
                    overview
                }
            } else {
                let w = wheel(t)
                Group0 {
                    HStack {
                        Spacer()
                        ZStack(alignment: .topTrailing) {
                            ColorWheel(hue: w.hue, saturation: w.saturation)
                                .frame(width: 176, height: 176)
                            HelpBadge(key: "cg.wheel").offset(x: 14, y: -2)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    ScrubRow(L("色相", "Hue"), value: w.hue, range: 0...360, help: "cg.hue", hint: Hint.spectrum(), suffix: "°")
                    ScrubRow(L("强度", "Strength"), value: w.saturation, range: 0...100, help: "cg.saturation")
                    ScrubRow(L("明亮度", "Luminance"), value: w.luminance, range: -100...100, help: "cg.luminance", hint: Hint.tone)
                }
            }
        }
    }

    /// 三个色调的颜色一览
    private var overview: some View {
        HStack(spacing: 0) {
            ForEach(Array([(L("阴影", "Shadows"), params.shadows), (L("中间调", "Midtones"), params.midtones), (L("高光", "Highlights"), params.highlights), (L("全局", "Global"), params.global)].enumerated()), id: \.offset) { _, item in
                VStack(spacing: 6) {
                    Circle()
                        .fill(item.1.saturation < 1 ? Color(white: 0.9) : Color(muted: item.1.hue, s: max(0.15, item.1.saturation / 100 * 0.7), b: 0.88))
                        .overlay(Circle().strokeBorder(Ink.line, lineWidth: 0.5))
                        .frame(width: 26, height: 26)
                    Text(item.0).font(.system(size: 10)).foregroundStyle(Ink.text3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

// MARK: - 色调分离 / 阈值 / LUT

struct PosterizePanel: View {
    @Binding var params: PosterizeParams
    var body: some View {
        Group0 {
            ScrubRow(L("色阶数", "Levels"), value: $params.levels, range: 2...32, defaultValue: 6, help: "poster.levels")
        }
        .padding(.vertical, 6)
    }
}

struct ThresholdPanel: View {
    @Binding var params: ThresholdParams
    var body: some View {
        Group0 {
            ScrubRow(L("阈值色阶", "Threshold level"), value: $params.level, range: 1...255, defaultValue: 128,
                     help: "threshold.level", hint: Hint.tone)
            NoteText(L("把这个图层的不透明度降到 20% 左右，可以给照片一种版画般的力量感。", "Drop this layer's opacity to around 20% for a bold, printmaking-like punch."))
        }
        .padding(.vertical, 6)
    }
}

struct LUTPanel: View {
    @EnvironmentObject var doc: EditDocument
    let layerID: UUID
    @Binding var params: LUTParams

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FileRow(title: params.path == nil ? L("未选择 LUT", "No LUT selected") : params.displayName,
                    subtitle: status, buttonTitle: params.path == nil ? L("选择…", "Choose…") : L("更换…", "Change…")) {
                doc.chooseLUT(for: layerID)
            }
            ScrubRow(L("强度", "Strength"), value: $params.intensity, range: 0...100, defaultValue: 100,
                     help: "lut.intensity", suffix: "%")
        }
        .padding(.vertical, 6)
    }

    private var status: String {
        guard let path = params.path else { return L("3D .cube 格式，达芬奇、PR、PS 通用", "3D .cube — works in Resolve, Premiere and Photoshop") }
        if let lut = doc.lutCache[path] { return L("\(lut.size)³ · 已载入", "\(lut.size)³ · loaded") }
        return L("文件找不到了，请重新选择", "File not found — please choose again")
    }
}

/// 文件 / 参考图一行
struct FileRow: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Ink.text).lineLimit(1)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Ink.text3).lineLimit(2)
            }
            Spacer()
            Button(buttonTitle, action: action).buttonStyle(GlassButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
