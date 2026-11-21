import SwiftUI

// MARK: - 色相/饱和度

struct HueSatPanel: View {
    @Binding var params: HueSatParams

    var body: some View {
        Group0 {
            InkToggleRow(title: L("着色（变成单一色调）", "Colorize (single tone)"), isOn: $params.colorize, help: "hs.colorize")
            ZStack(alignment: .top) {
                if params.colorize {
                    Group0 {
                        ScrubRow(L("着色色相", "Colorize hue"), value: $params.colorizeHue, range: 0...360, defaultValue: 30,
                                 help: "hs.colorizeHue", hint: Hint.spectrum(), suffix: "°")
                        ScrubRow(L("着色饱和度", "Colorize saturation"), value: $params.colorizeSaturation, range: 0...100, defaultValue: 25,
                                 help: "hs.colorizeSat")
                    }
                    .transition(.focusPull)
                } else {
                    Group0 {
                        ScrubRow(L("色相", "Hue"), value: $params.hue, range: -180...180, help: "hs.hue",
                                 hint: Hint.spectrum(from: 180, to: 540), suffix: "°")
                        ScrubRow(L("饱和度", "Saturation"), value: $params.saturation, range: -100...100, help: "hs.saturation")
                    }
                    .transition(.focusPull)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: params.colorize)
            ScrubRow(L("明度", "Lightness"), value: $params.lightness, range: -100...100, help: "hs.lightness", hint: Hint.tone)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - HSL 混色器

struct HSLPanel: View {
    @Binding var params: HSLParams
    @State private var tab = 0

    var body: some View {
        Pager([L("色相", "Hue"), L("饱和度", "Saturation"), L("明亮度", "Luminance")], selection: $tab) { t in
            Group0 {
                ForEach(0..<8, id: \.self) { i in
                    ScrubRow(HSLParams.names[i], value: bindIndex(array(t), i), range: -100...100,
                             help: helpKey(t), hint: hint(t, i), dot: Color(muted: HSLParams.centers[i], s: 0.6, b: 0.85))
                }
            }
        }
    }

    private func array(_ t: Int) -> Binding<[Double]> {
        switch t {
        case 0: return $params.hue
        case 1: return $params.saturation
        default: return $params.luminance
        }
    }

    private func helpKey(_ t: Int) -> String {
        ["hsl.hue", "hsl.saturation", "hsl.luminance"][min(t, 2)]
    }

    private func hint(_ t: Int, _ i: Int) -> [Color] {
        let h = HSLParams.centers[i]
        switch t {
        case 0: return [Color(muted: h - 30), Color(muted: h), Color(muted: h + 30)]
        case 1: return [Color(muted: h, s: 0.05), Color(muted: h, s: 0.6)]
        default: return [Color(muted: h, s: 0.5, b: 0.35), Color(muted: h), Color(muted: h, s: 0.15, b: 1)]
        }
    }
}

// MARK: - 色彩平衡

struct ColorBalancePanel: View {
    @Binding var params: ColorBalanceParams
    @State private var tone = 1

    private func tones(_ t: Int) -> Binding<[Double]> {
        switch t {
        case 0: return $params.shadows
        case 2: return $params.highlights
        default: return $params.midtones
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Pager([L("阴影", "Shadows"), L("中间调", "Midtones"), L("高光", "Highlights")], selection: $tone) { t in
                Group0 {
                    ScrubRow(L("青色 ↔ 红色", "Cyan ↔ Red"), value: bindIndex(tones(t), 0), range: -100...100,
                             help: "cb.cyanRed", hint: Hint.cyanRed)
                    ScrubRow(L("洋红 ↔ 绿色", "Magenta ↔ Green"), value: bindIndex(tones(t), 1), range: -100...100,
                             help: "cb.magentaGreen", hint: Hint.magentaGreen)
                    ScrubRow(L("黄色 ↔ 蓝色", "Yellow ↔ Blue"), value: bindIndex(tones(t), 2), range: -100...100,
                             help: "cb.yellowBlue", hint: Hint.yellowBlue)
                }
            }
            Rectangle().fill(Ink.line).frame(height: 0.5)
            InkToggleRow(title: L("保持明度", "Preserve luminosity"), isOn: $params.preserveLuminosity, help: "cb.preserve")
        }
    }
}

// MARK: - 可选颜色

struct SelectiveColorPanel: View {
    @Binding var params: SelectiveColorParams
    @State private var group = 0

    private let chips: [Color] = [
        Color(red: 0.86, green: 0.3, blue: 0.28), Color(red: 0.92, green: 0.82, blue: 0.3),
        Color(red: 0.3, green: 0.68, blue: 0.38), Color(red: 0.3, green: 0.72, blue: 0.78),
        Color(red: 0.3, green: 0.42, blue: 0.82), Color(red: 0.78, green: 0.34, blue: 0.72),
        Color(white: 0.98), Color(white: 0.6), Color(white: 0.1)
    ]

    private var groupBinding: Binding<[Double]> {
        Binding(get: { params.groups[group] }, set: { params.groups[group] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                MicroLabel("Colors", trailing: SelectiveColorParams.names[group])
                HelpBadge(key: "sc.group")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { i in
                    ColorChip(color: chips[i], selected: group == i, modified: params.groups[i] != [0, 0, 0, 0]) {
                        group = i
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            ZStack(alignment: .top) {
                Group0 {
                    ScrubRow(L("青色", "Cyan"), value: bindIndex(groupBinding, 0), range: -100...100, help: "sc.cyan",
                             hint: Array(Hint.cyanRed.reversed()), suffix: "%")
                    ScrubRow(L("洋红", "Magenta"), value: bindIndex(groupBinding, 1), range: -100...100, help: "sc.magenta",
                             hint: Array(Hint.magentaGreen.reversed()), suffix: "%")
                    ScrubRow(L("黄色", "Yellow"), value: bindIndex(groupBinding, 2), range: -100...100, help: "sc.yellow",
                             hint: Array(Hint.yellowBlue.reversed()), suffix: "%")
                    ScrubRow(L("黑色", "Black"), value: bindIndex(groupBinding, 3), range: -100...100, help: "sc.black",
                             hint: [Color(white: 0.95), Color(white: 0.12)], suffix: "%")
                }
                .id(group)
                .transition(.focusPull)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: group)

            HStack(spacing: 10) {
                Text(L("计算方式", "Method")).font(.system(size: 12.5)).foregroundStyle(Ink.text2)
                HelpBadge(key: "sc.mode")
                Spacer()
                InkSegment([(true, L("相对", "Relative")), (false, L("绝对", "Absolute"))], selection: $params.relative)
                    .frame(width: 120)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - 通道混合器

struct ChannelMixerPanel: View {
    @Binding var params: ChannelMixerParams
    @State private var output = 0

    private func row(_ o: Int) -> Binding<[Double]> {
        if params.monochrome { return $params.gray }
        switch o {
        case 1: return $params.green
        case 2: return $params.blue
        default: return $params.red
        }
    }

    private func defaults(_ o: Int) -> [Double] {
        if params.monochrome { return [40, 40, 20, 0] }
        switch o {
        case 1: return [0, 100, 0, 0]
        case 2: return [0, 0, 100, 0]
        default: return [100, 0, 0, 0]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            InkToggleRow(title: L("单色（输出黑白）", "Monochrome (black & white output)"), isOn: $params.monochrome, help: "cm.mono")
            Rectangle().fill(Ink.line).frame(height: 0.5)
            Pager(params.monochrome ? [L("灰色", "Gray")] : [L("输出 红", "Red out"), L("输出 绿", "Green out"), L("输出 蓝", "Blue out")], selection: $output) { o in
                let r = row(o)
                let d = defaults(o)
                Group0 {
                    ScrubRow(L("红色", "Red"), value: bindIndex(r, 0), range: -200...200, defaultValue: d[0], help: "cm.red",
                             suffix: "%", dot: Color(red: 0.86, green: 0.3, blue: 0.28))
                    ScrubRow(L("绿色", "Green"), value: bindIndex(r, 1), range: -200...200, defaultValue: d[1], help: "cm.green",
                             suffix: "%", dot: Color(red: 0.3, green: 0.68, blue: 0.38))
                    ScrubRow(L("蓝色", "Blue"), value: bindIndex(r, 2), range: -200...200, defaultValue: d[2], help: "cm.blue",
                             suffix: "%", dot: Color(red: 0.3, green: 0.42, blue: 0.82))
                    ScrubRow(L("常数", "Constant"), value: bindIndex(r, 3), range: -200...200, help: "cm.constant", suffix: "%")
                    total(r.wrappedValue)
                }
            }
        }
        .onChange(of: params.monochrome) { _, _ in output = 0 }
    }

    private func total(_ r: [Double]) -> some View {
        let t = Int((r[0] + r[1] + r[2]).rounded())
        let ok = abs(t - 100) <= 5
        return HStack(spacing: 8) {
            Text(L("合计", "Total")).font(.system(size: 11.5)).foregroundStyle(Ink.text2)
            Text("\(t)%")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Ink.text)
                .contentTransition(.numericText(value: Double(t)))
            Spacer()
            Text(ok ? L("亮度与原图接近", "Brightness matches the original") : (t > 100 ? L("会比原图亮", "Brighter than the original") : L("会比原图暗", "Darker than the original")))
                .font(.system(size: 11)).foregroundStyle(ok ? Ink.text3 : Ink.text)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .animation(.snappy, value: t)
    }
}

// MARK: - 黑白

struct BlackWhitePanel: View {
    @Binding var params: BlackWhiteParams
    @State private var tab = 0

    private let keys = ["bw.red", "bw.yellow", "bw.green", "bw.cyan", "bw.blue", "bw.magenta"]
    private let hues: [Double] = [0, 60, 120, 180, 240, 300]
    private let defaults: [Double] = [40, 60, 40, 60, 20, 80]
    private let presets: [(String, [Double])] = [
        (L("默认", "Default"), [40, 60, 40, 60, 20, 80]),
        (L("红滤镜", "Red"), [120, 110, -10, -50, -50, 120]),
        (L("黄滤镜", "Yellow"), [120, 110, 40, -30, -40, 70]),
        (L("绿滤镜", "Green"), [-40, 120, 120, -50, -50, -40]),
        (L("蓝滤镜", "Blue"), [-50, -50, -30, 110, 130, 110]),
        (L("红外", "Infrared"), [-40, 235, 144, -68, -3, -107])
    ]

    var body: some View {
        Pager([L("颜色", "Colors"), L("色调", "Tone")], selection: $tab) { t in
            if t == 0 {
                Group0 {
                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Filters")
                        HStack(spacing: 12) {
                            ForEach(presets.indices, id: \.self) { i in
                                Button(presets[i].0) {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { params.weights = presets[i].1 }
                                }
                                .buttonStyle(TextLinkStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    ForEach(0..<6, id: \.self) { i in
                        ScrubRow(BlackWhiteParams.names[i], value: bindIndex($params.weights, i), range: -200...300,
                                 defaultValue: defaults[i], help: keys[i],
                                 hint: [Color(white: 0.1), Color(muted: hues[i], s: 0.55), Color(white: 0.98)],
                                 suffix: "%")
                    }
                }
            } else {
                Group0 {
                    InkToggleRow(title: L("给黑白染色", "Tint the black & white"), isOn: $params.tint, help: "bw.tint")
                    ScrubRow(L("色相", "Hue"), value: $params.tintHue, range: 0...360, defaultValue: 35,
                             help: "bw.tintHue", hint: Hint.spectrum(), suffix: "°")
                    ScrubRow(L("饱和度", "Saturation"), value: $params.tintSaturation, range: 0...100, defaultValue: 25,
                             help: "bw.tintSat", suffix: "%")
                }
                .opacity(1)
            }
        }
    }
}

// MARK: - 照片滤镜

struct PhotoFilterPanel: View {
    @Binding var params: PhotoFilterParams

    private let presets: [(String, UInt32)] = [
        (L("加温 85", "Warming 85"), 0xEC8A00), (L("加温 LBA", "Warming LBA"), 0xFA9600), (L("冷却 80", "Cooling 80"), 0x006DFF), (L("冷却 LBB", "Cooling LBB"), 0x005DFF),
        (L("深褐", "Sepia"), 0xAC7A33), (L("红", "Red"), 0xEA1A1A), (L("橙", "Orange"), 0xF38417), (L("黄", "Yellow"), 0xF9E31C),
        (L("绿", "Green"), 0x19C919), (L("青", "Cyan"), 0x1DCBEA), (L("蓝", "Blue"), 0x1D35EA), (L("紫", "Violet"), 0x9B1DEA)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                MicroLabel("Filter")
                HelpBadge(key: "pf.color")
                ColorPicker("", selection: colorBinding($params.color), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), spacing: 1) {
                ForEach(presets.indices, id: \.self) { i in
                    let c = RGBColor(hex: presets[i].1)
                    let selected = params.color == c
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { params.color = c }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Rectangle().fill(Color(rgb: c)).frame(height: 18)
                            Text(presets[i].0)
                                .font(.system(size: 10))
                                .foregroundStyle(selected ? Ink.text : Ink.text2)
                                .lineLimit(1)
                        }
                        .padding(6)
                        .background(selected ? Ink.washStrong : Color.white)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Ink.line)
            .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 0.5))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            ScrubRow(L("浓度", "Density"), value: $params.density, range: 0...100, defaultValue: 25, help: "pf.density",
                     hint: [Color(white: 0.9), Color(rgb: params.color).opacity(0.7)], suffix: "%")
            InkToggleRow(title: L("保持明度", "Preserve luminosity"), isOn: $params.preserveLuminosity, help: "pf.preserve")
        }
    }
}
