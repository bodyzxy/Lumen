import SwiftUI

// MARK: - 基础调整

struct BasicPanel: View {
    @EnvironmentObject var doc: EditDocument
    @Binding var basic: BasicSettings
    @State private var tab = 0

    var body: some View {
        Pager([L("光影", "Light"), L("色彩", "Color"), L("质感", "Texture"), L("效果", "Effects"), L("校准", "Calibrate")], selection: $tab) { page in
            switch page {
            case 0:
                Group0 {
                    ScrubRow(L("曝光", "Exposure"), value: $basic.exposure, range: -5...5, help: "basic.exposure",
                             hint: Hint.tone, decimals: 2)
                    ScrubRow(L("对比度", "Contrast"), value: $basic.contrast, range: -100...100, help: "basic.contrast")
                    ScrubRow(L("高光", "Highlights"), value: $basic.highlights, range: -100...100, help: "basic.highlights")
                    ScrubRow(L("阴影", "Shadows"), value: $basic.shadows, range: -100...100, help: "basic.shadows")
                    ScrubRow(L("白色", "Whites"), value: $basic.whites, range: -100...100, help: "basic.whites")
                    ScrubRow(L("黑色", "Blacks"), value: $basic.blacks, range: -100...100, help: "basic.blacks")
                }
            case 1:
                Group0 {
                    HStack {
                        MicroLabel("White balance")
                        Button {
                            doc.eyedropper = doc.eyedropper == .whiteBalance ? nil : .whiteBalance
                        } label: {
                            Image(systemName: "eyedropper")
                        }
                        .buttonStyle(BareIconStyle(size: 24, active: doc.eyedropper == .whiteBalance))
                        .help(L("白平衡吸管：点击照片中本该是白色或灰色的地方", "White balance picker: click something that should be white or gray"))
                        HelpBadge(key: "wb.eyedropper")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    ScrubRow(L("色温", "Temp"), value: $basic.temperature, range: -100...100,
                             help: "basic.temperature", hint: Hint.temperature)
                    ScrubRow(L("色调", "Tint"), value: $basic.tint, range: -100...100,
                             help: "basic.tint", hint: Hint.tint)
                    MicroLabel("Presence").padding(.horizontal, 18).padding(.top, 12)
                    ScrubRow(L("自然饱和度", "Vibrance"), value: $basic.vibrance, range: -100...100, help: "basic.vibrance")
                    ScrubRow(L("饱和度", "Saturation"), value: $basic.saturation, range: -100...100, help: "basic.saturation")
                }
            case 2:
                Group0 {
                    ScrubRow(L("纹理", "Texture"), value: $basic.texture, range: -100...100, help: "basic.texture")
                    ScrubRow(L("清晰度", "Clarity"), value: $basic.clarity, range: -100...100, help: "basic.clarity")
                    ScrubRow(L("去朦胧", "Dehaze"), value: $basic.dehaze, range: -100...100, help: "basic.dehaze")
                    MicroLabel("Detail").padding(.horizontal, 18).padding(.top, 12)
                    ScrubRow(L("锐化", "Sharpening"), value: $basic.sharpen, range: 0...100, help: "basic.sharpen")
                    ScrubRow(L("降噪", "Noise Reduction"), value: $basic.noiseReduction, range: 0...100, help: "basic.noise")
                }
            case 3:
                Group0 {
                    ScrubRow(L("暗角", "Vignette"), value: $basic.vignette, range: -100...100, help: "basic.vignette",
                             hint: [Color(white: 0.96), Color(white: 0.6), Color(white: 0.15)])
                    ScrubRow(L("颗粒", "Grain"), value: $basic.grain, range: 0...100, help: "basic.grain")
                    ScrubRow(L("颗粒大小", "Grain Size"), value: $basic.grainSize, range: 0...100, defaultValue: 25,
                             help: "basic.grainSize")
                }
            default:
                Group0 {
                    ScrubRow(L("阴影色调", "Shadow Tint"), value: $basic.shadowTint, range: -100...100,
                             help: "calib.shadowTint", hint: Hint.tint)
                    MicroLabel("Red primary").padding(.horizontal, 18).padding(.top, 12)
                    ScrubRow(L("色相", "Hue"), value: $basic.redHue, range: -100...100, help: "calib.hue",
                             hint: Hint.spectrum(from: -30, to: 30, steps: 4))
                    ScrubRow(L("饱和度", "Saturation"), value: $basic.redSaturation, range: -100...100, help: "calib.saturation",
                             hint: [Color(white: 0.8), Color(muted: 0, s: 0.6)])
                    MicroLabel("Green primary").padding(.horizontal, 18).padding(.top, 12)
                    ScrubRow(L("色相", "Hue"), value: $basic.greenHue, range: -100...100, help: "calib.hue",
                             hint: Hint.spectrum(from: 90, to: 150, steps: 4))
                    ScrubRow(L("饱和度", "Saturation"), value: $basic.greenSaturation, range: -100...100, help: "calib.saturation",
                             hint: [Color(white: 0.8), Color(muted: 120, s: 0.6)])
                    MicroLabel("Blue primary").padding(.horizontal, 18).padding(.top, 12)
                    ScrubRow(L("色相", "Hue"), value: $basic.blueHue, range: -100...100, help: "calib.hue",
                             hint: Hint.spectrum(from: 210, to: 270, steps: 4))
                    ScrubRow(L("饱和度", "Saturation"), value: $basic.blueSaturation, range: -100...100, help: "calib.saturation",
                             hint: [Color(white: 0.8), Color(muted: 240, s: 0.6)])
                }
            }
        }
    }
}

// MARK: - 曲线

struct CurvesPanel: View {
    @EnvironmentObject var doc: EditDocument
    @Binding var params: CurvesParams
    @State private var channel = 0

    private func points(_ ch: Int) -> Binding<[CurvePoint]> {
        switch ch {
        case 1: return $params.red
        case 2: return $params.green
        case 3: return $params.blue
        default: return $params.rgb
        }
    }

    private func color(_ ch: Int) -> Color {
        switch ch {
        case 1: return Color(red: 0.8, green: 0.3, blue: 0.28)
        case 2: return Color(red: 0.26, green: 0.6, blue: 0.36)
        case 3: return Color(red: 0.28, green: 0.42, blue: 0.8)
        default: return Ink.text
        }
    }

    private func hist(_ ch: Int) -> [Double]? {
        guard let h = doc.histogram else { return nil }
        switch ch {
        case 1: return h.red
        case 2: return h.green
        case 3: return h.blue
        default: return h.luma
        }
    }

    var body: some View {
        Pager(["RGB", L("红", "Red"), L("绿", "Green"), L("蓝", "Blue")], selection: $channel) { ch in
            VStack(alignment: .leading, spacing: 12) {
                CurveEditor(points: points(ch), color: color(ch), histogram: hist(ch))
                    .aspectRatio(1, contentMode: .fit)

                HStack(spacing: 6) {
                    Text(L("点击添加控制点 · 拖动调整 · 拖出框外删除", "Click to add a point · drag to adjust · drag out to delete"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ink.text3)
                    HelpBadge(key: "curves.editor")
                }

                MicroLabel("Shapes")
                HStack(spacing: 14) {
                    shape(L("加对比", "More contrast"), [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.2),
                                  CurvePoint(x: 0.75, y: 0.8), CurvePoint(x: 1, y: 1)], ch)
                    shape(L("降对比", "Less contrast"), [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.3),
                                  CurvePoint(x: 0.75, y: 0.7), CurvePoint(x: 1, y: 1)], ch)
                    shape(L("褪黑", "Fade"), [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 0.3, y: 0.3),
                                 CurvePoint(x: 1, y: 0.97)], ch)
                    shape(L("提亮暗部", "Lift shadows"), [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.3, y: 0.4),
                                   CurvePoint(x: 1, y: 1)], ch)
                    Spacer()
                    shape(L("重置", "Reset"), CurvesParams.identity, ch)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private func shape(_ title: String, _ pts: [CurvePoint], _ ch: Int) -> some View {
        Button(title) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { points(ch).wrappedValue = pts }
        }
        .buttonStyle(TextLinkStyle())
    }
}

struct CurveEditor: View {
    @Binding var points: [CurvePoint]
    let color: Color
    let histogram: [Double]?
    @State private var dragIndex: Int?
    @State private var removedThisDrag = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Rectangle().fill(Color.white)
                if let h = histogram {
                    HistogramShape(data: AnimatableVector(values: h), filled: true)
                        .fill(Ink.text.opacity(0.06))
                        .animation(.easeOut(duration: 0.3), value: h)
                }
                Canvas { ctx, sz in
                    for i in 1..<4 {
                        let f = CGFloat(i) / 4
                        var p = Path()
                        p.move(to: CGPoint(x: sz.width * f, y: 0)); p.addLine(to: CGPoint(x: sz.width * f, y: sz.height))
                        p.move(to: CGPoint(x: 0, y: sz.height * f)); p.addLine(to: CGPoint(x: sz.width, y: sz.height * f))
                        ctx.stroke(p, with: .color(Color.black.opacity(0.06)), lineWidth: 0.5)
                    }
                    var diag = Path()
                    diag.move(to: CGPoint(x: 0, y: sz.height)); diag.addLine(to: CGPoint(x: sz.width, y: 0))
                    ctx.stroke(diag, with: .color(Color.black.opacity(0.1)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

                    let curve = MonotoneCurve(points: points)
                    var cp = Path()
                    let steps = 180
                    for i in 0...steps {
                        let x = Double(i) / Double(steps)
                        let pt = CGPoint(x: CGFloat(x) * sz.width, y: (1 - CGFloat(curve.value(x))) * sz.height)
                        if i == 0 { cp.move(to: pt) } else { cp.addLine(to: pt) }
                    }
                    ctx.stroke(cp, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                    for (i, p) in points.enumerated() {
                        let c = CGPoint(x: CGFloat(p.x) * sz.width, y: (1 - CGFloat(p.y)) * sz.height)
                        let r: CGFloat = (i == dragIndex) ? 5.5 : 4
                        let dot = Path(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                        ctx.fill(dot, with: .color(i == dragIndex ? color : Color.white))
                        ctx.stroke(dot, with: .color(color), lineWidth: 1.2)
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(Ink.lineStrong, lineWidth: 0.5))
            .overlay(alignment: .topLeading) {
                if let i = dragIndex, i < points.count {
                    Text("\(Int(points[i].x * 255)) → \(Int(points[i].y * 255))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 7).frame(height: 18)
                        .background(GlassBackground(shape: Capsule()))
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in handleDrag(g.location, size) }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.15)) { dragIndex = nil }
                        removedThisDrag = false
                    }
            )
        }
    }

    private func handleDrag(_ loc: CGPoint, _ size: CGSize) {
        guard size.width > 0, size.height > 0, !removedThisDrag else { return }
        let px = Double(loc.x / size.width)
        let py = Double(1 - loc.y / size.height)

        if dragIndex == nil {
            var best: Int?
            var bestD = CGFloat.infinity
            for (i, p) in points.enumerated() {
                let d = hypot(CGFloat(p.x - px) * size.width, CGFloat(p.y - py) * size.height)
                if d < bestD { bestD = d; best = i }
            }
            if let b = best, bestD < 12 {
                dragIndex = b
            } else {
                let x = CM.clamp(px), y = CM.clamp(py)
                if points.contains(where: { abs($0.x - x) < 0.02 }) { return }
                var pts = points
                let idx = pts.firstIndex(where: { $0.x > x }) ?? pts.count
                pts.insert(CurvePoint(x: x, y: y), at: idx)
                points = pts
                dragIndex = idx
                return
            }
        }

        guard let i = dragIndex, i < points.count else { return }
        let outside = py < -0.1 || py > 1.1 || px < -0.1 || px > 1.1
        if outside && i != 0 && i != points.count - 1 && points.count > 2 {
            points.remove(at: i)
            dragIndex = nil
            removedThisDrag = true
            return
        }
        let lo = i > 0 ? points[i - 1].x + 0.01 : 0
        let hi = i < points.count - 1 ? points[i + 1].x - 0.01 : 1
        points[i] = CurvePoint(x: min(max(CM.clamp(px), lo), hi), y: CM.clamp(py))
    }
}

// MARK: - 色阶（直接拖动直方图下面的三个滑块，和 PS 一样）

struct LevelsPanel: View {
    @EnvironmentObject var doc: EditDocument
    @Binding var params: LevelsParams
    @State private var channel = 0

    private func ch(_ i: Int) -> Binding<LevelsChannel> {
        switch i {
        case 1: return $params.red
        case 2: return $params.green
        case 3: return $params.blue
        default: return $params.master
        }
    }

    private func hist(_ i: Int) -> [Double]? {
        guard let h = doc.histogram else { return nil }
        switch i {
        case 1: return h.red
        case 2: return h.green
        case 3: return h.blue
        default: return h.luma
        }
    }

    var body: some View {
        Pager(["RGB", L("红", "Red"), L("绿", "Green"), L("蓝", "Blue")], selection: $channel) { i in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    MicroLabel("Input")
                    HelpBadge(key: "levels.handles")
                }
                LevelsInput(channel: ch(i), histogram: hist(i))
                MicroLabel("Output")
                LevelsOutput(channel: ch(i))
                HStack(spacing: 14) {
                    Button(L("自动", "Auto")) { autoLevels() }.buttonStyle(GlassButtonStyle())
                    HelpBadge(key: "levels.auto")
                    Spacer()
                    Button(L("重置此通道", "Reset channel")) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { ch(i).wrappedValue = LevelsChannel() }
                    }
                    .buttonStyle(TextLinkStyle())
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private func autoLevels() {
        guard let h = doc.histogram?.lumaCounts else { return }
        let total = h.reduce(0, +)
        guard total > 0 else { return }
        let cut = total * 0.003
        var acc = 0.0, lo = 0, hi = 255
        for i in 0..<256 { acc += h[i]; if acc > cut { lo = i; break } }
        acc = 0
        for i in stride(from: 255, through: 0, by: -1) { acc += h[i]; if acc > cut { hi = i; break } }
        if hi - lo < 10 { return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
            params.master.inBlack = Double(lo)
            params.master.inWhite = Double(hi)
            params.master.gamma = 1
            channel = 0
        }
    }
}

/// 三角形滑块
struct LevelHandle: View {
    let fill: Color
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 6, y: 0))
            p.addLine(to: CGPoint(x: 12, y: 10))
            p.addLine(to: CGPoint(x: 0, y: 10))
            p.closeSubpath()
        }
        .fill(fill)
        .overlay(
            Path { p in
                p.move(to: CGPoint(x: 6, y: 0))
                p.addLine(to: CGPoint(x: 12, y: 10))
                p.addLine(to: CGPoint(x: 0, y: 10))
                p.closeSubpath()
            }
            .stroke(Ink.text, lineWidth: 0.8)
        )
        .frame(width: 12, height: 10)
        .contentShape(Rectangle().inset(by: -8))
    }
}

struct LevelsInput: View {
    @Binding var channel: LevelsChannel
    let histogram: [Double]?

    private var mid: Double {
        let p = pow(0.5, channel.gamma)
        return channel.inBlack + (channel.inWhite - channel.inBlack) * p
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.white)
                    if let h = histogram {
                        HistogramShape(data: AnimatableVector(values: h), filled: true)
                            .fill(Ink.text.opacity(0.16))
                            .animation(.easeOut(duration: 0.3), value: h)
                    }
                    // 被裁掉的两端
                    Rectangle().fill(Ink.text.opacity(0.06))
                        .frame(width: CGFloat(channel.inBlack / 255) * w)
                    Rectangle().fill(Ink.text.opacity(0.06))
                        .frame(width: CGFloat(1 - channel.inWhite / 255) * w)
                        .offset(x: CGFloat(channel.inWhite / 255) * w)
                }
                .overlay(Rectangle().strokeBorder(Ink.lineStrong, lineWidth: 0.5))
            }
            .frame(height: 70)

            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 4)
                        .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 0.5))
                    handle(.black, at: channel.inBlack, w: w) { v in
                        channel.inBlack = min(v, channel.inWhite - 3)
                    }
                    handle(Color(white: 0.55), at: mid, w: w) { v in
                        let range = max(1, channel.inWhite - channel.inBlack)
                        let p = CM.clamp((v - channel.inBlack) / range, 0.13, 0.93)
                        channel.gamma = (log(p) / log(0.5) * 100).rounded() / 100
                    }
                    handle(.white, at: channel.inWhite, w: w) { v in
                        channel.inWhite = max(v, channel.inBlack + 3)
                    }
                }
                .coordinateSpace(name: "levels")
            }
            .frame(height: 18)

            HStack {
                value(Int(channel.inBlack))
                Spacer()
                Text(String(format: "%.2f", channel.gamma))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Ink.text2)
                Spacer()
                value(Int(channel.inWhite))
            }
        }
    }

    private func value(_ v: Int) -> some View {
        Text("\(v)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Ink.text2)
    }

    private func handle(_ fill: Color, at v: Double, w: CGFloat, set: @escaping (Double) -> Void) -> some View {
        LevelHandle(fill: fill)
            .offset(x: CGFloat(v / 255) * w - 6, y: 6)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("levels"))
                    .onChanged { g in
                        set((CM.clamp(Double(g.location.x / w)) * 255).rounded())
                    }
            )
    }
}

struct LevelsOutput: View {
    @Binding var channel: LevelsChannel

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 10)
                        .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 0.5))
                    LevelHandle(fill: .black)
                        .offset(x: CGFloat(channel.outBlack / 255) * w - 6, y: 12)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("levelsOut")).onChanged { d in
                            channel.outBlack = min((CM.clamp(Double(d.location.x / w)) * 255).rounded(), channel.outWhite)
                        })
                    LevelHandle(fill: .white)
                        .offset(x: CGFloat(channel.outWhite / 255) * w - 6, y: 12)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("levelsOut")).onChanged { d in
                            channel.outWhite = max((CM.clamp(Double(d.location.x / w)) * 255).rounded(), channel.outBlack)
                        })
                }
                .coordinateSpace(name: "levelsOut")
            }
            .frame(height: 24)
            HStack {
                Text("\(Int(channel.outBlack))").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Ink.text2)
                Spacer()
                Text("\(Int(channel.outWhite))").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Ink.text2)
            }
        }
    }
}

// MARK: - 亮度/对比度、曝光度、自然饱和度

struct BrightnessContrastPanel: View {
    @Binding var params: BrightnessContrastParams
    var body: some View {
        Group0 {
            ScrubRow(L("亮度", "Brightness"), value: $params.brightness, range: -150...150, help: "bc.brightness", hint: Hint.tone)
            ScrubRow(L("对比度", "Contrast"), value: $params.contrast, range: -50...100, help: "bc.contrast")
        }
        .padding(.vertical, 6)
    }
}

struct ExposurePanel: View {
    @Binding var params: ExposureParams
    var body: some View {
        Group0 {
            ScrubRow(L("曝光度", "Exposure"), value: $params.exposure, range: -5...5, help: "exp.exposure", hint: Hint.tone, decimals: 2)
            ScrubRow(L("位移", "Offset"), value: $params.offset, range: -0.5...0.5, help: "exp.offset", decimals: 3)
            ScrubRow(L("灰度系数", "Gamma"), value: $params.gamma, range: 0.1...3, defaultValue: 1, help: "exp.gamma", decimals: 2)
        }
        .padding(.vertical, 6)
    }
}

struct VibrancePanel: View {
    @Binding var params: VibranceParams
    var body: some View {
        Group0 {
            ScrubRow(L("自然饱和度", "Vibrance"), value: $params.vibrance, range: -100...100, help: "basic.vibrance")
            ScrubRow(L("饱和度", "Saturation"), value: $params.saturation, range: -100...100, help: "basic.saturation")
        }
        .padding(.vertical, 6)
    }
}
