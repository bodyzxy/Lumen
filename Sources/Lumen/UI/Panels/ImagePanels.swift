import SwiftUI

// MARK: - 阴影/高光

struct ShadowsHighlightsPanel: View {
    @Binding var params: ShadowsHighlightsParams
    @State private var tab = 0

    var body: some View {
        Pager([L("阴影", "Shadows"), L("高光", "Highlights"), L("调整", "Adjust")], selection: $tab) { t in
            switch t {
            case 0:
                Group0 {
                    ScrubRow(L("数量", "Amount"), value: $params.shadowsAmount, range: 0...100, defaultValue: 35,
                             help: "sh.shadowsAmount", suffix: "%")
                    ScrubRow(L("半径", "Radius"), value: $params.shadowsRadius, range: 1...100, defaultValue: 30,
                             help: "sh.radius", suffix: " px")
                }
            case 1:
                Group0 {
                    ScrubRow(L("数量", "Amount"), value: $params.highlightsAmount, range: 0...100,
                             help: "sh.highlightsAmount", suffix: "%")
                    ScrubRow(L("半径", "Radius"), value: $params.highlightsRadius, range: 1...100, defaultValue: 30,
                             help: "sh.radius", suffix: " px")
                }
            default:
                Group0 {
                    ScrubRow(L("颜色校正", "Color correction"), value: $params.colorCorrection, range: -100...100, defaultValue: 20,
                             help: "sh.colorCorrection")
                    ScrubRow(L("中间调对比度", "Midtone contrast"), value: $params.midtoneContrast, range: -100...100,
                             help: "sh.midtoneContrast")
                }
            }
        }
    }
}

// MARK: - HDR 色调

struct HDRToningPanel: View {
    @Binding var params: HDRToningParams
    @State private var tab = 0

    var body: some View {
        Pager([L("边缘光", "Edge Glow"), L("色调与细节", "Tone & Detail"), L("颜色", "Colors")], selection: $tab) { t in
            switch t {
            case 0:
                Group0 {
                    ScrubRow(L("半径", "Radius"), value: $params.radius, range: 1...100, defaultValue: 30, help: "hdr.radius", suffix: " px")
                    ScrubRow(L("强度", "Strength"), value: $params.strength, range: 0...100, defaultValue: 50, help: "hdr.strength", suffix: "%")
                }
            case 1:
                Group0 {
                    ScrubRow(L("灰度系数", "Gamma"), value: $params.gamma, range: 0.2...2.5, defaultValue: 1, help: "hdr.gamma", decimals: 2)
                    ScrubRow(L("曝光度", "Exposure"), value: $params.exposure, range: -3...3, help: "hdr.exposure", hint: Hint.tone, decimals: 2)
                    ScrubRow(L("细节", "Detail"), value: $params.detail, range: -100...200, defaultValue: 30, help: "hdr.detail", suffix: "%")
                }
            default:
                Group0 {
                    ScrubRow(L("自然饱和度", "Vibrance"), value: $params.vibrance, range: -100...100, help: "basic.vibrance")
                    ScrubRow(L("饱和度", "Saturation"), value: $params.saturation, range: -100...100, defaultValue: 20, help: "basic.saturation")
                }
            }
        }
    }
}

// MARK: - 匹配颜色

struct MatchColorPanel: View {
    @EnvironmentObject var doc: EditDocument
    let layerID: UUID
    @Binding var params: MatchColorParams

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FileRow(title: params.reference == nil ? L("未选择参考照片", "No reference photo") : params.referenceName,
                    subtitle: params.reference == nil ? L("选一张你喜欢的照片，当前照片的色调会向它靠拢", "Pick a photo you like — this photo's tones will move toward it") : L("已分析参考照片的颜色分布", "Reference colors analyzed"),
                    buttonTitle: params.reference == nil ? L("选择…", "Choose…") : L("更换…", "Change…")) {
                doc.chooseMatchReference(for: layerID)
            }
            if let ref = params.reference {
                HStack(spacing: 0) {
                    statSwatch(L("当前", "Current"), params.source)
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Ink.text3)
                    statSwatch(L("参考", "Reference"), ref)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }
            Rectangle().fill(Ink.line).frame(height: 0.5)
            ScrubRow(L("明亮度", "Luminance"), value: $params.luminance, range: 1...200, defaultValue: 100, help: "mc.luminance")
            ScrubRow(L("颜色强度", "Color intensity"), value: $params.intensity, range: 1...200, defaultValue: 100, help: "mc.intensity")
            ScrubRow(L("渐隐", "Fade"), value: $params.fade, range: 0...100, help: "mc.fade")
            InkToggleRow(title: L("中和", "Neutralize"), isOn: $params.neutralize, help: "mc.neutralize")
        }
        .padding(.vertical, 6)
    }

    /// 用统计出的平均颜色画一个小色块
    private func statSwatch(_ title: String, _ s: ColorStats?) -> some View {
        let c: RGBColor = {
            guard let s = s else { return RGBColor(r: 0.9, g: 0.9, b: 0.9) }
            let rgb = CM.fromYCbCr(s.mean[0], s.mean[1] * 3, s.mean[2] * 3)
            return RGBColor(r: CM.clamp(rgb.0), g: CM.clamp(rgb.1), b: CM.clamp(rgb.2))
        }()
        return HStack(spacing: 8) {
            Rectangle().fill(Color(rgb: c)).frame(width: 22, height: 22)
                .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 0.5))
            Text(title).font(.system(size: 11)).foregroundStyle(Ink.text2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 替换颜色

struct ReplaceColorPanel: View {
    @EnvironmentObject var doc: EditDocument
    let layerID: UUID
    @Binding var params: ReplaceColorParams

    private var picking: Bool { doc.eyedropper == .replaceColor(layerID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color(rgb: params.target))
                    .frame(width: 34, height: 34)
                    .overlay(Rectangle().strokeBorder(Ink.lineStrong, lineWidth: 0.5))
                    .animation(.easeOut(duration: 0.3), value: params.target)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("要替换的颜色", "Color to replace")).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Ink.text)
                    Text(params.target.hexString)
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Ink.text3)
                }
                Spacer()
                ColorPicker("", selection: colorBinding($params.target), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36)
                Button {
                    doc.eyedropper = picking ? nil : .replaceColor(layerID)
                } label: {
                    Image(systemName: "eyedropper")
                }
                .buttonStyle(GlassIconStyle(size: 28, active: picking))
                .help(L("从照片上吸取颜色", "Pick a color from the photo"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            ScrubRow(L("容差", "Fuzziness"), value: $params.fuzziness, range: 0...200, defaultValue: 40, help: "rc.fuzziness")
            MicroLabel("Replacement").padding(.horizontal, 18).padding(.top, 10)
            ScrubRow(L("色相", "Hue"), value: $params.hue, range: -180...180, help: "rc.hue",
                     hint: Hint.spectrum(from: 180, to: 540), suffix: "°")
            ScrubRow(L("饱和度", "Saturation"), value: $params.saturation, range: -100...100, help: "rc.saturation")
            ScrubRow(L("明度", "Lightness"), value: $params.lightness, range: -100...100, help: "rc.lightness", hint: Hint.tone)
        }
    }
}

// MARK: - 色调均化

struct EqualizePanel: View {
    @EnvironmentObject var doc: EditDocument
    let layerID: UUID
    @Binding var params: EqualizeParams

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NoteText(L("色调均化会重新分布亮度，让每个亮度级别的像素数量尽量相同。暗淡、发灰的照片会立刻变得层次分明。", "Equalize redistributes brightness so every level holds about the same number of pixels. Dull, gray photos instantly gain separation."))
            if params.curve.count == 256 {
                CurvePreview(values: params.curve)
                    .frame(height: 120)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
            }
            HStack {
                Button(L("按当前画面重新计算", "Recalculate from Current Image")) { doc.recomputeEqualize(for: layerID) }
                    .buttonStyle(GlassButtonStyle())
                HelpBadge(key: "eq.recompute")
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }
}

/// 只读的映射曲线预览
struct CurvePreview: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, sz in
            var diag = Path()
            diag.move(to: CGPoint(x: 0, y: sz.height)); diag.addLine(to: CGPoint(x: sz.width, y: 0))
            ctx.stroke(diag, with: .color(Color.black.opacity(0.1)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            var p = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: CGFloat(i) / CGFloat(values.count - 1) * sz.width, y: (1 - CGFloat(v)) * sz.height)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(Ink.text), lineWidth: 1.2)
        }
        .background(Color.white)
        .overlay(Rectangle().strokeBorder(Ink.lineStrong, lineWidth: 0.5))
    }
}
