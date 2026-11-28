import Foundation

typealias RGB = (Double, Double, Double)

/// 基础面板里能合进 LUT 的部分（色调、色彩、校准）
struct BasicToneParams: Equatable {
    var contrast: Double, highlights: Double, whites: Double, blacks: Double
    var dehaze: Double, vibrance: Double, saturation: Double
    var shadowTint: Double
    var redHue: Double, redSat: Double, greenHue: Double, greenSat: Double, blueHue: Double, blueSat: Double

    init(_ b: BasicSettings) {
        contrast = b.contrast; highlights = b.highlights; whites = b.whites; blacks = b.blacks
        dehaze = b.dehaze; vibrance = b.vibrance; saturation = b.saturation
        shadowTint = b.shadowTint
        redHue = b.redHue; redSat = b.redSaturation
        greenHue = b.greenHue; greenSat = b.greenSaturation
        blueHue = b.blueHue; blueSat = b.blueSaturation
    }

    var isIdle: Bool {
        contrast == 0 && highlights <= 0 && whites == 0 && blacks == 0 && dehaze == 0
            && vibrance == 0 && saturation == 0 && shadowTint == 0
            && redHue == 0 && redSat == 0 && greenHue == 0 && greenSat == 0 && blueHue == 0 && blueSat == 0
    }
}

/// 一段连续的“逐像素”调整，会被合成一张 3D LUT。
/// 空间类图层（阴影/高光、HDR）会把图层栈切成几段，每段一张 LUT。
struct LUTInputs: Equatable {
    var tone: BasicToneParams?
    var layers: [AdjustmentLayer]
    var lutPaths: [String]

    init(tone: BasicToneParams?, layers: [AdjustmentLayer]) {
        self.tone = tone
        self.layers = layers.filter { $0.visible && $0.opacity > 0 && !$0.kind.isSpatial }
        self.lutPaths = self.layers.compactMap { $0.kind == .lut ? $0.params.lut.path : nil }
    }

    /// 整张图的颜色部分（导出 .cube 用，忽略空间类图层）
    init(fullColorOf state: EditState) {
        self.init(tone: BasicToneParams(state.basic), layers: state.layers)
    }

    var isIdentity: Bool { (tone?.isIdle ?? true) && layers.isEmpty }
}

/// 每个线程只写自己那一段，所以可以安全地在线程间共享这个指针
private struct SendablePointer: @unchecked Sendable {
    let p: UnsafeMutablePointer<Float>
    init(_ p: UnsafeMutablePointer<Float>) { self.p = p }
}

final class LUTBuilder {

    /// 生成 RGBA Float 数据（Core Image 的 CIColorCube 需要的格式）
    static func build(_ inputs: LUTInputs, size: Int, luts: [String: CubeLUT]) -> [Float] {
        let prepared = inputs.layers.map { PreparedLayer(layer: $0, luts: luts) }
        let basic = inputs.tone.map { BasicTone($0) }
        var out = [Float](repeating: 0, count: size * size * size * 4)
        let n = Double(size - 1)

        out.withUnsafeMutableBufferPointer { buf in
            let base = SendablePointer(buf.baseAddress!)
            DispatchQueue.concurrentPerform(iterations: size) { bi in
                let b = Double(bi) / n
                for gi in 0..<size {
                    let g = Double(gi) / n
                    for ri in 0..<size {
                        let r = Double(ri) / n
                        var c = (r, g, b)
                        if let basic = basic { c = basic.apply(c) }
                        for layer in prepared {
                            c = layer.apply(c)
                        }
                        let idx = ((bi * size + gi) * size + ri) * 4
                        base.p[idx] = Float(CM.clamp(c.0))
                        base.p[idx + 1] = Float(CM.clamp(c.1))
                        base.p[idx + 2] = Float(CM.clamp(c.2))
                        base.p[idx + 3] = 1
                    }
                }
            }
        }
        return out
    }
}

// MARK: - 基础面板中的逐像素部分

private struct BasicTone {
    let contrast: Double, highlights: Double, whites: Double, blacks: Double
    let dehaze: Double, vibrance: Double, saturation: Double
    let shadowTint: Double
    /// 校准矩阵（3×3，按行存放）
    let matrix: [Double]?
    let isIdentity: Bool

    init(_ i: BasicToneParams) {
        var c = i.contrast / 100
        var bl = i.blacks / 100
        var sat = i.saturation / 100
        let d = i.dehaze / 100
        if d > 0 {
            c += d * 0.35
            sat += d * 0.25
            bl -= d * 0.3
        }
        contrast = CM.clamp(c, -1, 1.5)
        highlights = max(0, i.highlights / 100)   // 负向由 Core Image 的高光阴影滤镜处理
        whites = i.whites / 100
        blacks = bl
        dehaze = d
        vibrance = i.vibrance / 100
        saturation = sat
        shadowTint = i.shadowTint / 100

        let calib = [i.redHue, i.redSat, i.greenHue, i.greenSat, i.blueHue, i.blueSat]
        if calib.allSatisfy({ $0 == 0 }) {
            matrix = nil
        } else {
            // 每个原色先在色环上转动、再调整纯度，三个原色组成新的混合矩阵
            func primary(_ baseHue: Double, _ hue: Double, _ s: Double) -> RGB {
                CM.hslToRgb(baseHue + hue / 100 * 30, CM.clamp(1 + s / 100 * 0.6), 0.5)
            }
            let pr = primary(0, i.redHue, i.redSat)
            let pg = primary(120, i.greenHue, i.greenSat)
            let pb = primary(240, i.blueHue, i.blueSat)
            var m = [pr.0, pg.0, pb.0,
                     pr.1, pg.1, pb.1,
                     pr.2, pg.2, pb.2]
            for row in 0..<3 {
                let s = m[row * 3] + m[row * 3 + 1] + m[row * 3 + 2]
                if s > 1e-6 { for k in 0..<3 { m[row * 3 + k] /= s } }
            }
            matrix = m
        }
        isIdentity = contrast == 0 && highlights == 0 && whites == 0 && blacks == 0
            && d == 0 && vibrance == 0 && saturation == 0 && shadowTint == 0 && matrix == nil
    }

    func apply(_ cIn: RGB) -> RGB {
        if isIdentity { return cIn }
        var (r, g, b) = cIn

        if let m = matrix {
            let nr = m[0] * r + m[1] * g + m[2] * b
            let ng = m[3] * r + m[4] * g + m[5] * b
            let nb = m[6] * r + m[7] * g + m[8] * b
            r = nr; g = ng; b = nb
        }

        if shadowTint != 0 {
            let l = CM.luma(r, g, b)
            let w = (1 - l) * (1 - l)
            let d = shadowTint * 0.08 * w
            r += d * 0.5; b += d * 0.5; g -= d
        }

        if whites != 0 || blacks != 0 || highlights != 0 {
            let l = CM.luma(r, g, b)
            var nl = l
            if whites != 0 { nl += whites * 0.35 * l * l * l }
            if blacks != 0 { let k = 1 - l; nl += blacks * 0.3 * k * k * k }
            if highlights > 0 {
                let bump = CM.smoothstep(0.35, 0.75, l) * (1 - CM.smoothstep(0.85, 1.0, l) * 0.5)
                nl += highlights * 0.22 * bump
            }
            let dl = nl - l
            r += dl; g += dl; b += dl
        }

        if contrast != 0 {
            r = CM.contrastCurve(r, contrast)
            g = CM.contrastCurve(g, contrast)
            b = CM.contrastCurve(b, contrast)
        }

        if dehaze < 0 {
            let t = -dehaze * 0.5
            r = CM.mix(r, 0.78, t); g = CM.mix(g, 0.80, t); b = CM.mix(b, 0.84, t)
        }

        var c = CM.vibrance((r, g, b), vibrance)
        c = CM.saturate(c, saturation)
        return (CM.clamp(c.0), CM.clamp(c.1), CM.clamp(c.2))
    }
}

// MARK: - 调整图层

private struct PreparedLayer {
    let layer: AdjustmentLayer
    let opacity: Double

    var curveRGB: MonotoneCurve?
    var curveR: MonotoneCurve?
    var curveG: MonotoneCurve?
    var curveB: MonotoneCurve?
    var cube: CubeLUT?
    var gradientStops: [GradientStop] = []

    init(layer: AdjustmentLayer, luts: [String: CubeLUT]) {
        self.layer = layer
        self.opacity = CM.clamp(layer.opacity / 100)
        switch layer.kind {
        case .curves:
            let p = layer.params.curves
            if !MonotoneCurve.isIdentity(p.rgb) { curveRGB = MonotoneCurve(points: p.rgb) }
            if !MonotoneCurve.isIdentity(p.red) { curveR = MonotoneCurve(points: p.red) }
            if !MonotoneCurve.isIdentity(p.green) { curveG = MonotoneCurve(points: p.green) }
            if !MonotoneCurve.isIdentity(p.blue) { curveB = MonotoneCurve(points: p.blue) }
        case .lut:
            if let path = layer.params.lut.path { cube = luts[path] }
        case .gradientMap:
            gradientStops = layer.params.gradientMap.stops.sorted { $0.position < $1.position }
        default:
            break
        }
    }

    func apply(_ c: RGB) -> RGB {
        let processed = process(c)
        let blended = layer.blendMode == .normal ? processed : CM.blend(c, processed, mode: layer.blendMode)
        if opacity >= 0.999 { return blended }
        return (CM.mix(c.0, blended.0, opacity), CM.mix(c.1, blended.1, opacity), CM.mix(c.2, blended.2, opacity))
    }

    private func process(_ c: RGB) -> RGB {
        let p = layer.params
        switch layer.kind {
        case .curves: return curves(c)
        case .levels: return levels(c, p.levels)
        case .brightnessContrast: return brightnessContrast(c, p.brightnessContrast)
        case .exposure: return exposure(c, p.exposure)
        case .vibrance:
            let v = CM.saturate(CM.vibrance(c, p.vibrance.vibrance / 100), p.vibrance.saturation / 100)
            return (CM.clamp(v.0), CM.clamp(v.1), CM.clamp(v.2))
        case .hueSaturation: return hueSat(c, p.hueSaturation)
        case .hsl: return hsl(c, p.hsl)
        case .colorBalance: return colorBalance(c, p.colorBalance)
        case .selectiveColor: return selectiveColor(c, p.selectiveColor)
        case .channelMixer: return channelMixer(c, p.channelMixer)
        case .blackWhite: return blackWhite(c, p.blackWhite)
        case .photoFilter: return photoFilter(c, p.photoFilter)
        case .gradientMap: return gradientMap(c, p.gradientMap)
        case .colorGrading: return colorGrading(c, p.colorGrading)
        case .posterize: return posterize(c, p.posterize)
        case .threshold: return threshold(c, p.threshold)
        case .invert: return (1 - c.0, 1 - c.1, 1 - c.2)
        case .lut: return lut(c, p.lut)
        case .desaturate:
            let l = (max(c.0, c.1, c.2) + min(c.0, c.1, c.2)) / 2
            return (l, l, l)
        case .matchColor: return matchColor(c, p.matchColor)
        case .replaceColor: return replaceColor(c, p.replaceColor)
        case .equalize: return equalize(c, p.equalize)
        case .shadowsHighlights, .hdrToning: return c   // 空间类，在 Core Image 中处理
        }
    }

    private func curves(_ c: RGB) -> RGB {
        var (r, g, b) = c
        if let m = curveRGB { r = m.value(r); g = m.value(g); b = m.value(b) }
        if let cr = curveR { r = cr.value(r) }
        if let cg = curveG { g = cg.value(g) }
        if let cb = curveB { b = cb.value(b) }
        return (r, g, b)
    }

    private func levelsChannel(_ v: Double, _ ch: LevelsChannel) -> Double {
        if ch.isIdentity { return v }
        let inB = ch.inBlack / 255, inW = max(ch.inWhite / 255, inB + 0.004)
        var x = CM.clamp((v - inB) / (inW - inB))
        x = pow(x, 1 / max(ch.gamma, 0.01))
        return ch.outBlack / 255 + x * (ch.outWhite - ch.outBlack) / 255
    }

    private func levels(_ c: RGB, _ p: LevelsParams) -> RGB {
        var r = levelsChannel(c.0, p.red)
        var g = levelsChannel(c.1, p.green)
        var b = levelsChannel(c.2, p.blue)
        r = levelsChannel(r, p.master)
        g = levelsChannel(g, p.master)
        b = levelsChannel(b, p.master)
        return (r, g, b)
    }

    private func brightnessContrast(_ c: RGB, _ p: BrightnessContrastParams) -> RGB {
        var (r, g, b) = c
        if p.brightness != 0 {
            // 和 PS 新版算法类似：中间调变化多，最亮和最暗基本不动
            let e = pow(2, -p.brightness / 150 * 0.9)
            r = pow(CM.clamp(r), e); g = pow(CM.clamp(g), e); b = pow(CM.clamp(b), e)
        }
        if p.contrast != 0 {
            let a = p.contrast / 100
            r = CM.contrastCurve(r, a); g = CM.contrastCurve(g, a); b = CM.contrastCurve(b, a)
        }
        return (r, g, b)
    }

    private func exposure(_ c: RGB, _ p: ExposureParams) -> RGB {
        let k = pow(2, p.exposure)
        let gInv = 1 / max(p.gamma, 0.01)
        func f(_ v: Double) -> Double {
            let lin = max(0, CM.toLinear(v) * k + p.offset)
            return CM.clamp(CM.toGamma(pow(lin, gInv)))
        }
        return (f(c.0), f(c.1), f(c.2))
    }

    private func applyLightness(_ c: RGB, _ L: Double) -> RGB {
        if L == 0 { return c }
        if L > 0 {
            return (c.0 + (1 - c.0) * L, c.1 + (1 - c.1) * L, c.2 + (1 - c.2) * L)
        }
        let k = 1 + L
        return (c.0 * k, c.1 * k, c.2 * k)
    }

    private func hueSat(_ c: RGB, _ p: HueSatParams) -> RGB {
        if p.colorize {
            let l = CM.luma(c.0, c.1, c.2)
            let col = CM.hslToRgb(p.colorizeHue, p.colorizeSaturation / 100, l)
            return applyLightness(col, p.lightness / 100)
        }
        var (r, g, b) = c
        if p.hue != 0 {
            let hsl = CM.rgbToHsl(r, g, b)
            (r, g, b) = CM.hslToRgb(hsl.h + p.hue, hsl.s, hsl.l)
        }
        if p.saturation != 0 {
            let s = p.saturation / 100
            let f = s > 0 ? 1 + s * 1.4 : 1 + s
            let l = CM.luma(r, g, b)
            r = l + (r - l) * f; g = l + (g - l) * f; b = l + (b - l) * f
        }
        return applyLightness((CM.clamp(r), CM.clamp(g), CM.clamp(b)), p.lightness / 100)
    }

    private func hsl(_ c: RGB, _ p: HSLParams) -> RGB {
        let hsl = CM.rgbToHsl(c.0, c.1, c.2)
        if hsl.s < 1e-4 { return c }
        let centers = HSLParams.centers
        var dh = 0.0, ds = 0.0, dl = 0.0
        for i in 0..<8 {
            let ctr = centers[i]
            let d = CM.angleDiff(hsl.h, ctr)
            let span = d >= 0 ? abs(CM.angleDiff(centers[(i + 1) % 8], ctr)) : abs(CM.angleDiff(ctr, centers[(i + 7) % 8]))
            let w = 1 - abs(d) / span
            if w <= 0 { continue }
            dh += w * p.hue[i] / 100 * 30
            ds += w * p.saturation[i] / 100
            dl += w * p.luminance[i] / 100
        }
        let s = CM.clamp(hsl.s * (1 + ds))
        let l = CM.clamp(hsl.l + dl * 0.35 * hsl.s)
        return CM.hslToRgb(hsl.h + dh, s, l)
    }

    private func colorBalance(_ c: RGB, _ p: ColorBalanceParams) -> RGB {
        let l = CM.rgbToHsl(c.0, c.1, c.2).l
        let a = 0.25, bb = 0.333, scale = 0.7
        let sw = CM.clamp((l - bb) / -a + 0.5) * scale
        let mw = CM.clamp((l - bb) / a + 0.5) * CM.clamp((l + bb - 1) / -a + 0.5) * scale
        let hw = CM.clamp((l + bb - 1) / a + 0.5) * scale

        var r = c.0 + (p.shadows[0] * sw + p.midtones[0] * mw + p.highlights[0] * hw) / 100
        var g = c.1 + (p.shadows[1] * sw + p.midtones[1] * mw + p.highlights[1] * hw) / 100
        var b = c.2 + (p.shadows[2] * sw + p.midtones[2] * mw + p.highlights[2] * hw) / 100
        r = CM.clamp(r); g = CM.clamp(g); b = CM.clamp(b)

        if p.preserveLuminosity {
            let h = CM.rgbToHsl(r, g, b)
            return CM.hslToRgb(h.h, h.s, l)
        }
        return (r, g, b)
    }

    private func selectiveColor(_ c: RGB, _ p: SelectiveColorParams) -> RGB {
        let (r, g, b) = c
        let maxV = max(r, g, b), minV = min(r, g, b)
        let midV = r + g + b - maxV - minV
        var weights = [Double](repeating: 0, count: 9)
        if maxV == r { weights[0] = maxV - midV }
        if minV == b { weights[1] = midV - minV }
        if maxV == g { weights[2] = maxV - midV }
        if minV == r { weights[3] = midV - minV }
        if maxV == b { weights[4] = maxV - midV }
        if minV == g { weights[5] = midV - minV }
        weights[6] = max(0, (minV - 0.5) * 2)
        weights[7] = max(0, 1 - (abs(maxV - 0.5) + abs(minV - 0.5)))
        weights[8] = max(0, (0.5 - maxV) * 2)

        var o0 = r, o1 = g, o2 = b
        for gi in 0..<9 where weights[gi] > 0 {
            let adj = p.groups[gi]
            if adj[0] == 0 && adj[1] == 0 && adj[2] == 0 && adj[3] == 0 { continue }
            let k = adj[3] / 100
            let w = weights[gi]
            o0 += -(adj[0] / 100 + k) * (p.relative ? (1 - r) : 1) * w
            o1 += -(adj[1] / 100 + k) * (p.relative ? (1 - g) : 1) * w
            o2 += -(adj[2] / 100 + k) * (p.relative ? (1 - b) : 1) * w
        }
        return (CM.clamp(o0), CM.clamp(o1), CM.clamp(o2))
    }

    private func channelMixer(_ c: RGB, _ p: ChannelMixerParams) -> RGB {
        func mixRow(_ row: [Double]) -> Double {
            (row[0] * c.0 + row[1] * c.1 + row[2] * c.2) / 100 + row[3] / 100
        }
        if p.monochrome {
            let v = CM.clamp(mixRow(p.gray))
            return (v, v, v)
        }
        return (CM.clamp(mixRow(p.red)), CM.clamp(mixRow(p.green)), CM.clamp(mixRow(p.blue)))
    }

    private func blackWhite(_ c: RGB, _ p: BlackWhiteParams) -> RGB {
        let (r, g, b) = c
        let w = p.weights.map { $0 / 100 }
        let maxV = max(r, g, b), minV = min(r, g, b)
        let midV = r + g + b - maxV - minV
        let primary: Double, secondary: Double
        if maxV == r {
            primary = w[0]
            secondary = (minV == b) ? w[1] : w[5]
        } else if maxV == g {
            primary = w[2]
            secondary = (minV == b) ? w[1] : w[3]
        } else {
            primary = w[4]
            secondary = (minV == r) ? w[3] : w[5]
        }
        let gray = CM.clamp(minV + (midV - minV) * secondary + (maxV - midV) * primary)
        if p.tint {
            return CM.hslToRgb(p.tintHue, p.tintSaturation / 100, gray)
        }
        return (gray, gray, gray)
    }

    private func photoFilter(_ c: RGB, _ p: PhotoFilterParams) -> RGB {
        let d = p.density / 100
        let fr = CM.mix(1, p.color.r, d), fg = CM.mix(1, p.color.g, d), fb = CM.mix(1, p.color.b, d)
        var r = c.0 * fr, g = c.1 * fg, b = c.2 * fb
        if p.preserveLuminosity {
            let l0 = CM.luma(c.0, c.1, c.2)
            let l1 = CM.luma(r, g, b)
            if l1 > 1e-5 {
                let k = l0 / l1
                r *= k; g *= k; b *= k
            }
        }
        return (CM.clamp(r), CM.clamp(g), CM.clamp(b))
    }

    private func gradientMap(_ c: RGB, _ p: GradientMapParams) -> RGB {
        guard let first = gradientStops.first, let last = gradientStops.last else { return c }
        var t = CM.luma(c.0, c.1, c.2)
        if p.reverse { t = 1 - t }
        if t <= first.position { return (first.color.r, first.color.g, first.color.b) }
        if t >= last.position { return (last.color.r, last.color.g, last.color.b) }
        for i in 0..<(gradientStops.count - 1) {
            let a = gradientStops[i], b = gradientStops[i + 1]
            if t >= a.position && t <= b.position {
                let k = (t - a.position) / max(b.position - a.position, 1e-6)
                return (CM.mix(a.color.r, b.color.r, k), CM.mix(a.color.g, b.color.g, k), CM.mix(a.color.b, b.color.b, k))
            }
        }
        return c
    }

    private func colorGrading(_ c: RGB, _ p: ColorGradingParams) -> RGB {
        let l = CM.luma(c.0, c.1, c.2)
        let pivot = 0.5 - p.balance / 100 * 0.25
        let width = 0.12 + p.blending / 100 * 0.4
        let hw = CM.smoothstep(pivot - width, pivot + width, l)
        let sw = 1 - hw
        let mw = exp(-pow((l - pivot) / (0.16 + p.blending / 100 * 0.22), 2))
        let sideScale = 1 - mw * 0.6

        var (r, g, b) = c
        func add(_ wheel: ToneWheel, _ weight: Double) {
            if weight <= 0 { return }
            if wheel.saturation > 0 {
                let hc = CM.hueColor(wheel.hue)
                let hl = CM.luma(hc.0, hc.1, hc.2)
                let k = wheel.saturation / 100 * 0.35 * weight
                r += (hc.0 - hl) * k; g += (hc.1 - hl) * k; b += (hc.2 - hl) * k
            }
            if wheel.luminance != 0 {
                let dl = wheel.luminance / 100 * 0.25 * weight
                r += dl; g += dl; b += dl
            }
        }
        add(p.shadows, sw * sideScale)
        add(p.midtones, mw)
        add(p.highlights, hw * sideScale)
        add(p.global, 0.6)
        return (CM.clamp(r), CM.clamp(g), CM.clamp(b))
    }

    private func posterize(_ c: RGB, _ p: PosterizeParams) -> RGB {
        let n = max(2, p.levels.rounded())
        func q(_ v: Double) -> Double { (v * (n - 1)).rounded() / (n - 1) }
        return (q(c.0), q(c.1), q(c.2))
    }

    private func threshold(_ c: RGB, _ p: ThresholdParams) -> RGB {
        let v: Double = CM.luma(c.0, c.1, c.2) * 255 >= p.level ? 1 : 0
        return (v, v, v)
    }

    private func lut(_ c: RGB, _ p: LUTParams) -> RGB {
        guard let cube = cube else { return c }
        let o = cube.sample(c.0, c.1, c.2)
        let k = p.intensity / 100
        return (CM.mix(c.0, o.0, k), CM.mix(c.1, o.1, k), CM.mix(c.2, o.2, k))
    }

    /// 匹配颜色：把源图的亮度、色度分布搬到参考图的分布上（Reinhard 色彩迁移）
    private func matchColor(_ c: RGB, _ p: MatchColorParams) -> RGB {
        guard let ref = p.reference, let src = p.source else { return c }
        let (y, cb, cr) = CM.toYCbCr(c.0, c.1, c.2)
        func transfer(_ v: Double, _ i: Int) -> Double {
            (v - src.mean[i]) / max(src.std[i], 1e-4) * ref.std[i] + ref.mean[i]
        }
        var ny = transfer(y, 0) * (p.luminance / 100)
        var ncb = transfer(cb, 1)
        var ncr = transfer(cr, 2)
        if p.neutralize { ncb -= ref.mean[1]; ncr -= ref.mean[2] }
        ncb *= p.intensity / 100
        ncr *= p.intensity / 100
        ny = CM.clamp(ny)
        var o = CM.fromYCbCr(ny, ncb, ncr)
        let f = p.fade / 100
        o = (CM.mix(o.0, c.0, f), CM.mix(o.1, c.1, f), CM.mix(o.2, c.2, f))
        return (CM.clamp(o.0), CM.clamp(o.1), CM.clamp(o.2))
    }

    /// 替换颜色：离目标颜色越近，受影响越大
    private func replaceColor(_ c: RGB, _ p: ReplaceColorParams) -> RGB {
        let t = p.target
        let d = sqrt(pow(c.0 - t.r, 2) * 0.9 + pow(c.1 - t.g, 2) * 1.2 + pow(c.2 - t.b, 2) * 0.9)
        let radius = max(0.01, p.fuzziness / 200 * 0.85)
        var w = CM.clamp(1 - d / radius)
        w = w * w * (3 - 2 * w)
        if w <= 0 { return c }
        let h = CM.rgbToHsl(c.0, c.1, c.2)
        let s = CM.clamp(h.s * (1 + p.saturation / 100 * w))
        var o = CM.hslToRgb(h.h + p.hue * w, s, h.l)
        o = applyLightness(o, p.lightness / 100 * w)
        return (CM.clamp(o.0), CM.clamp(o.1), CM.clamp(o.2))
    }

    private func equalize(_ c: RGB, _ p: EqualizeParams) -> RGB {
        guard p.curve.count == 256 else { return c }
        let l = CM.clamp(CM.luma(c.0, c.1, c.2))
        let f = l * 255
        let i = min(254, Int(f))
        let nl = CM.mix(p.curve[i], p.curve[i + 1], f - Double(i))
        let d = nl - l
        return (CM.clamp(c.0 + d), CM.clamp(c.1 + d), CM.clamp(c.2 + d))
    }
}
