import Foundation
import CoreImage
import CoreGraphics
import Metal
import UniformTypeIdentifiers
import ImageIO

struct Histogram: Equatable {
    var red: [Double]
    var green: [Double]
    var blue: [Double]
    var luma: [Double]
    /// 未归一化的亮度计数（色调均化、自动色阶用）
    var lumaCounts: [Double]
    /// 纯黑 / 纯白像素占比
    var clipLow: Double
    var clipHigh: Double
}

/// Core Image 渲染管线：
/// 曝光/白平衡（线性空间）→ 高光阴影 → 纹理/清晰度/去朦胧 → 降噪/锐化
/// → [LUT 段 → 空间类图层 → LUT 段 …] → 暗角 → 颗粒
final class RenderEngine {
    let context: CIContext
    let displaySpace = CGColorSpace(name: CGColorSpace.displayP3)!
    let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!

    static let lutSize = 64

    private var lutCache: [(LUTInputs, Data)] = []
    private let lock = NSLock()

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }
    }

    // MARK: 读取图片

    static func loadImage(url: URL) -> CIImage? {
        let ext = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext), type.conforms(to: .rawImage),
           let raw = CIRAWFilter(imageURL: url), let out = raw.outputImage {
            return normalized(out)
        }
        if let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) {
            return normalized(img)
        }
        return nil
    }

    static func normalized(_ img: CIImage) -> CIImage {
        let e = img.extent
        let moved = img.transformed(by: CGAffineTransform(translationX: -e.origin.x, y: -e.origin.y))
        return moved.cropped(to: CGRect(x: 0, y: 0, width: floor(e.width), height: floor(e.height)))
    }

    static func downscale(_ img: CIImage, maxSide: CGFloat) -> CIImage {
        let e = img.extent
        let longSide = max(e.width, e.height)
        guard longSide > maxSide else { return img }
        let scaled = img.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: maxSide / longSide,
            kCIInputAspectRatioKey: 1.0
        ])
        return normalized(scaled)
    }

    /// 预览源图先“烘焙”成 16 位浮点位图，之后每次调参都不用重新解码 RAW
    func bake(_ img: CIImage) -> CIImage {
        guard let cg = context.createCGImage(img, from: img.extent, format: .RGBAh, colorSpace: linearSpace) else {
            return img
        }
        return CIImage(cgImage: cg)
    }

    // MARK: LUT（最近用过的几张缓存起来）

    func lutData(for inputs: LUTInputs, luts: [String: CubeLUT]) -> Data {
        lock.lock()
        if let hit = lutCache.firstIndex(where: { $0.0 == inputs }) {
            let data = lutCache[hit].1
            lock.unlock()
            return data
        }
        lock.unlock()
        let floats = LUTBuilder.build(inputs, size: RenderEngine.lutSize, luts: luts)
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        lock.lock()
        lutCache.insert((inputs, data), at: 0)
        if lutCache.count > 8 { lutCache.removeLast() }
        lock.unlock()
        return data
    }

    private func applyLUT(_ img: CIImage, _ inputs: LUTInputs, luts: [String: CubeLUT]) -> CIImage {
        if inputs.isIdentity { return img }
        let data = lutData(for: inputs, luts: luts)
        return img.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": RenderEngine.lutSize,
            "inputCubeData": data,
            "inputColorSpace": displaySpace
        ])
    }

    // MARK: 主管线

    /// reference：当 source 只是整张图的一部分（放大时的局部高清渲染）时，传入整张图的范围，
    /// 这样清晰度半径、暗角中心、颗粒大小等都和整张图保持一致。
    func process(_ source: CIImage, state: EditState, luts: [String: CubeLUT], reference: CGRect? = nil) -> CIImage {
        let extent = source.extent
        let refExtent = reference ?? extent
        let longSide = max(refExtent.width, refExtent.height)
        let b = state.basic
        var img = source

        // 1. 曝光（线性空间，按 EV 计算，和相机一致）
        if b.exposure != 0 {
            img = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: b.exposure])
        }

        // 2. 白平衡：在线性空间里调整 RGB 增益，并保持整体亮度不变
        if b.temperature != 0 || b.tint != 0 {
            let g = RenderEngine.whiteBalanceGains(temperature: b.temperature, tint: b.tint)
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: g.0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: g.1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: g.2, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ])
        }

        // 3. 高光（压暗部分）与阴影
        if b.highlights < 0 || b.shadows != 0 {
            let hAmount = b.highlights < 0 ? 1 + b.highlights / 100 : 1
            img = img.clampedToExtent().applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": hAmount,
                "inputShadowAmount": b.shadows / 100,
                "inputRadius": max(2, longSide * 0.004)
            ]).cropped(to: extent)
        }

        // 4. 纹理 / 清晰度 / 去朦胧
        img = localContrast(img, amount: b.texture / 100, radius: longSide * 0.0025, strength: 0.9, extent: extent)
        img = localContrast(img, amount: b.clarity / 100, radius: longSide * 0.015, strength: 0.55, extent: extent)
        if b.dehaze > 0 {
            img = localContrast(img, amount: b.dehaze / 100, radius: longSide * 0.06, strength: 0.35, extent: extent)
        }

        // 5. 降噪与锐化
        if b.noiseReduction > 0 {
            img = img.clampedToExtent().applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": b.noiseReduction / 100 * 0.08,
                "inputSharpness": 0.4
            ]).cropped(to: extent)
        }
        if b.sharpen > 0 {
            img = img.clampedToExtent().applyingFilter("CISharpenLuminance", parameters: [
                "inputSharpness": b.sharpen / 100 * 1.6
            ]).cropped(to: extent)
        }

        // 6. 图层栈：连续的逐像素图层合成一张 LUT，遇到空间类图层就先结算再处理它
        var tone: BasicToneParams? = BasicToneParams(b)
        var pending: [AdjustmentLayer] = []
        for layer in state.layers where layer.visible && layer.opacity > 0 {
            if layer.kind.isSpatial {
                img = applyLUT(img, LUTInputs(tone: tone, layers: pending), luts: luts)
                tone = nil
                pending = []
                img = applySpatial(img, layer: layer, extent: extent, longSide: longSide)
            } else {
                pending.append(layer)
            }
        }
        img = applyLUT(img, LUTInputs(tone: tone, layers: pending), luts: luts)

        // 7. 暗角
        if b.vignette != 0 {
            img = vignette(img, amount: b.vignette / 100, extent: extent, reference: refExtent)
        }

        // 8. 颗粒
        if b.grain > 0 {
            img = grain(img, amount: b.grain / 100, size: b.grainSize / 100, extent: extent, longSide: longSide)
        }

        img = img.cropped(to: extent)
        if !state.crop.isIdentity {
            img = RenderEngine.applyCropAndTransform(img, crop: state.crop)
        }
        return img
    }

    static func applyCropAndTransform(_ source: CIImage, crop: CropSettings) -> CIImage {
        if crop.isIdentity { return source }
        var img = normalized(source)
        var w = img.extent.width
        var h = img.extent.height
        guard w > 1, h > 1 else { return img }

        let turns = ((crop.quarterTurns % 4) + 4) % 4
        if turns != 0 || crop.flipH || crop.flipV {
            var t = CGAffineTransform(translationX: w / 2, y: h / 2)
            if turns != 0 {
                // Core Image Y-up: 90° CW is -pi/2
                t = t.rotated(by: -CGFloat(turns) * .pi / 2)
            }
            t = t.scaledBy(x: crop.flipH ? -1 : 1, y: crop.flipV ? -1 : 1)
            t = t.translatedBy(x: -w / 2, y: -h / 2)
            img = normalized(img.transformed(by: t))
            w = img.extent.width
            h = img.extent.height
        }

        if abs(crop.straighten) >= 1e-3 {
            let rad = -CGFloat(crop.straighten) * .pi / 180.0
            let c = abs(cos(rad)), s = abs(sin(rad))
            let scale = min(w / max(1, w * c + h * s), h / max(1, w * s + h * c))
            var t = CGAffineTransform(translationX: w / 2, y: h / 2)
            t = t.rotated(by: rad)
            t = t.translatedBy(x: -w / 2, y: -h / 2)
            img = img.transformed(by: t)
            let iw = w * scale, ih = h * scale
            let ix = (w - iw) / 2, iy = (h - ih) / 2
            img = normalized(img.cropped(to: CGRect(x: ix, y: iy, width: iw, height: ih)))
            w = img.extent.width
            h = img.extent.height
        }

        let cx = max(0, min(1, crop.x))
        let cy = max(0, min(1, crop.y))
        let cw = max(0.02, min(1 - cx, crop.width))
        let ch = max(0.02, min(1 - cy, crop.height))
        if abs(cx) > 1e-4 || abs(cy) > 1e-4 || abs(cw - 1) > 1e-4 || abs(ch - 1) > 1e-4 {
            // crop.y is top-origin (SwiftUI), CIImage is bottom-origin
            let rect = CGRect(
                x: cx * w,
                y: (1 - cy - ch) * h,
                width: max(2, cw * w),
                height: max(2, ch * h)
            )
            img = normalized(img.cropped(to: rect))
        }
        return img
    }

    static func whiteBalanceGains(temperature: Double, tint: Double) -> (Double, Double, Double) {
        let t = temperature / 100
        let m = tint / 100
        var rg = 1 + 0.32 * t + 0.08 * m
        var gg = 1.0 - 0.22 * m
        var bg = 1 - 0.32 * t + 0.08 * m
        let lum = 0.2126 * rg + 0.7152 * gg + 0.0722 * bg
        rg /= lum; gg /= lum; bg /= lum
        return (rg, gg, bg)
    }

    // MARK: 空间类图层

    private func applySpatial(_ input: CIImage, layer: AdjustmentLayer, extent: CGRect, longSide: CGFloat) -> CIImage {
        let scale = longSide / 1000
        var img = input
        switch layer.kind {
        case .shadowsHighlights:
            let p = layer.params.shadowsHighlights
            if p.shadowsAmount > 0 {
                img = img.clampedToExtent().applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 1.0,
                    "inputShadowAmount": p.shadowsAmount / 100,
                    "inputRadius": max(1, p.shadowsRadius * scale * 0.4)
                ]).cropped(to: extent)
            }
            if p.highlightsAmount > 0 {
                img = img.clampedToExtent().applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 1 - p.highlightsAmount / 100,
                    "inputShadowAmount": 0.0,
                    "inputRadius": max(1, p.highlightsRadius * scale * 0.4)
                ]).cropped(to: extent)
            }
            let correction = p.colorCorrection / 100 * max(p.shadowsAmount, p.highlightsAmount) / 100
            if correction != 0 || p.midtoneContrast != 0 {
                img = img.applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1 + correction * 0.6,
                    kCIInputContrastKey: 1 + p.midtoneContrast / 100 * 0.3,
                    kCIInputBrightnessKey: 0.0
                ])
            }
        case .hdrToning:
            let p = layer.params.hdrToning
            if p.strength > 0 {
                img = img.clampedToExtent().applyingFilter("CIUnsharpMask", parameters: [
                    kCIInputRadiusKey: max(2, p.radius * scale * 1.2),
                    kCIInputIntensityKey: p.strength / 100 * 1.2
                ]).cropped(to: extent)
            }
            if p.detail != 0 {
                img = localContrast(img, amount: p.detail / 100, radius: 2.5 * scale, strength: 0.8, extent: extent)
            }
            if p.exposure != 0 {
                img = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: p.exposure])
            }
            if p.gamma != 1 {
                img = img.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 1 / max(0.1, p.gamma)])
            }
            if p.vibrance != 0 {
                img = img.applyingFilter("CIVibrance", parameters: ["inputAmount": p.vibrance / 100])
            }
            if p.saturation != 0 {
                img = img.applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1 + p.saturation / 100,
                    kCIInputContrastKey: 1.0,
                    kCIInputBrightnessKey: 0.0
                ])
            }
        default:
            break
        }
        if let filterName = ciBlendFilter(for: layer.blendMode) {
            img = img.applyingFilter(filterName, parameters: [kCIInputBackgroundImageKey: input])
        }
        if layer.opacity < 99.9 {
            img = input.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: img,
                kCIInputTimeKey: layer.opacity / 100
            ])
        }
        return img.cropped(to: extent)
    }

    private func ciBlendFilter(for mode: LayerBlendMode) -> String? {
        switch mode {
        case .normal: return nil
        case .multiply: return "CIMultiplyBlendMode"
        case .screen: return "CIScreenBlendMode"
        case .overlay: return "CIOverlayBlendMode"
        case .softLight: return "CISoftLightBlendMode"
        case .hardLight: return "CIHardLightBlendMode"
        case .colorDodge: return "CIColorDodgeBlendMode"
        case .colorBurn: return "CIColorBurnBlendMode"
        case .darken: return "CIDarkenBlendMode"
        case .lighten: return "CILightenBlendMode"
        case .color: return "CIColorBlendMode"
        case .luminosity: return "CILuminosityBlendMode"
        }
    }

    private func localContrast(_ img: CIImage, amount: Double, radius: Double, strength: Double, extent: CGRect) -> CIImage {
        guard amount != 0 else { return img }
        let r = max(0.8, radius)
        if amount > 0 {
            return img.clampedToExtent().applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: r,
                kCIInputIntensityKey: amount * strength
            ]).cropped(to: extent)
        }
        let blurred = img.clampedToExtent().applyingGaussianBlur(sigma: r * 0.6).cropped(to: extent)
        return img.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: blurred,
            kCIInputTimeKey: min(1, -amount * strength * 1.1)
        ]).cropped(to: extent)
    }

    private func vignette(_ img: CIImage, amount: Double, extent: CGRect, reference: CGRect) -> CIImage {
        let center = CIVector(x: reference.midX, y: reference.midY)
        let half = hypot(reference.width, reference.height) / 2
        let darken = amount > 0
        let a = abs(amount)
        let inner = darken ? CIColor(red: 1, green: 1, blue: 1) : CIColor(red: 0, green: 0, blue: 0)
        let edgeV = darken ? 1 - 0.85 * a : 0.6 * a
        let edge = CIColor(red: edgeV, green: edgeV, blue: edgeV)
        guard let grad = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": center,
            "inputRadius0": half * 0.42,
            "inputRadius1": half * 1.05,
            "inputColor0": inner,
            "inputColor1": edge
        ])?.outputImage?.cropped(to: extent) else { return img }
        return grad.applyingFilter(darken ? "CIMultiplyCompositing" : "CIScreenBlendMode",
                                   parameters: [kCIInputBackgroundImageKey: img])
    }

    private func grain(_ img: CIImage, amount: Double, size: Double, extent: CGRect, longSide: CGFloat) -> CIImage {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return img }
        let scale = max(1, (1 + size * 3) * longSide / 2400)
        let k = amount * 0.45
        let mono = noise
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.5 - 0.5 * k, y: 0.5 - 0.5 * k, z: 0.5 - 0.5 * k, w: 1)
            ])
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingGaussianBlur(sigma: scale * 0.35)
            .cropped(to: extent)
        return mono.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img])
    }

    // MARK: 放大时的局部高清渲染

    /// rect：要渲染的区域（0...1，左上为原点）；pixelWidth：屏幕上需要的像素宽度
    func renderDetail(_ source: CIImage, state: EditState, luts: [String: CubeLUT],
                      rect: CGRect, pixelWidth: CGFloat) -> CGImage? {
        let ext = source.extent
        let crop = CGRect(x: ext.minX + rect.minX * ext.width,
                          y: ext.minY + (1 - rect.maxY) * ext.height,
                          width: rect.width * ext.width,
                          height: rect.height * ext.height).integral.intersection(ext)
        guard crop.width >= 2, crop.height >= 2 else { return nil }
        // 多留一圈边，避免清晰度、去朦胧这类大半径效果在边缘出现断层
        let margin = max(ext.width, ext.height) * 0.03
        let region = source.cropped(to: crop.insetBy(dx: -margin, dy: -margin).intersection(ext))
        var out = process(region, state: state, luts: luts, reference: ext).cropped(to: crop)
        let k = min(1, pixelWidth / crop.width)
        if k < 0.98 {
            out = out.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: k, kCIInputAspectRatioKey: 1.0])
            out = RenderEngine.normalized(out)
        }
        return context.createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: displaySpace)
    }

    /// 把 CGImage 缩成小缩略图
    func thumbnail(of cg: CGImage, maxSide: Double) -> CGImage? {
        let w0 = Double(cg.width), h0 = Double(cg.height)
        let s = min(1, maxSide / max(w0, h0))
        let w = max(1, Int(w0 * s)), h = max(1, Int(h0 * s))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: displaySpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: 输出与分析

    func renderCG(_ img: CIImage) -> CGImage? {
        context.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: displaySpace)
    }

    /// 把 CGImage 缩小到指定长边并取出 8 位 RGBA 像素
    func pixels(of cg: CGImage, maxSide: Double) -> (data: [UInt8], width: Int, height: Int) {
        let w0 = Double(cg.width), h0 = Double(cg.height)
        let s = min(1, maxSide / max(w0, h0))
        let w = max(1, Int(w0 * s)), h = max(1, Int(h0 * s))
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: displaySpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (data, w, h)
    }

    func histogram(of cg: CGImage) -> Histogram {
        let (px, w, h) = pixels(of: cg, maxSide: 360)
        var r = [Double](repeating: 0, count: 256)
        var g = r, b = r, l = r
        for i in 0..<(w * h) {
            let rv = Int(px[i * 4]), gv = Int(px[i * 4 + 1]), bv = Int(px[i * 4 + 2])
            r[rv] += 1; g[gv] += 1; b[bv] += 1
            let lv = min(255, Int(0.299 * Double(rv) + 0.587 * Double(gv) + 0.114 * Double(bv)))
            l[lv] += 1
        }
        func norm(_ a: [Double]) -> [Double] {
            let m = max(a[1..<255].max() ?? 1, 1)
            return a.map { min(1, $0 / m) }
        }
        let total = Double(max(1, w * h))
        return Histogram(red: norm(r), green: norm(g), blue: norm(b), luma: norm(l), lumaCounts: l,
                         clipLow: l[0] / total, clipHigh: l[255] / total)
    }

    /// 图片在 YCbCr 空间的颜色统计（匹配颜色用）
    func colorStats(of cg: CGImage) -> ColorStats {
        let (px, w, h) = pixels(of: cg, maxSide: 256)
        var sum = [0.0, 0.0, 0.0], sq = [0.0, 0.0, 0.0]
        let n = Double(max(1, w * h))
        for i in 0..<(w * h) {
            let c = CM.toYCbCr(Double(px[i * 4]) / 255, Double(px[i * 4 + 1]) / 255, Double(px[i * 4 + 2]) / 255)
            let v = [c.0, c.1, c.2]
            for k in 0..<3 { sum[k] += v[k]; sq[k] += v[k] * v[k] }
        }
        let mean = sum.map { $0 / n }
        let std = (0..<3).map { k in max(1e-4, (sq[k] / n - mean[k] * mean[k]).squareRoot()) }
        return ColorStats(mean: mean, std: std)
    }

    /// 读取某个位置（0...1，左上为原点）附近 5×5 的平均颜色
    func sampleColor(_ cg: CGImage, at p: CGPoint) -> RGBColor {
        let x = Int(CM.clamp(Double(p.x)) * Double(cg.width - 1))
        let y = Int(CM.clamp(Double(p.y)) * Double(cg.height - 1))
        let size = 5
        var data = [UInt8](repeating: 0, count: size * size * 4)
        data.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: displaySpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // CGContext 原点在左下，需要把目标像素挪到 5×5 区域中央
            let ox = -CGFloat(x) + CGFloat(size / 2)
            let oy = -CGFloat(cg.height - 1 - y) + CGFloat(size / 2)
            ctx.draw(cg, in: CGRect(x: ox, y: oy, width: CGFloat(cg.width), height: CGFloat(cg.height)))
        }
        var r = 0.0, g = 0.0, b = 0.0
        for i in 0..<(size * size) {
            r += Double(data[i * 4]); g += Double(data[i * 4 + 1]); b += Double(data[i * 4 + 2])
        }
        let n = Double(size * size) * 255
        return RGBColor(r: r / n, g: g / n, b: b / n)
    }

    // MARK: 导出

    enum ExportFormat: String, CaseIterable, Identifiable {
        case jpeg = "JPEG", heic = "HEIC", png = "PNG", tiff = "TIFF"
        var id: String { rawValue }
        var ext: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            case .tiff: return "tiff"
            case .heic: return "heic"
            }
        }
        var utType: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png: return .png
            case .tiff: return .tiff
            case .heic: return .heic
            }
        }
    }

    func export(_ img: CIImage, to url: URL, format: ExportFormat, quality: Double) throws {
        let q = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        switch format {
        case .jpeg:
            try context.writeJPEGRepresentation(of: img, to: url, colorSpace: displaySpace, options: [q: quality])
        case .heic:
            try context.writeHEIFRepresentation(of: img, to: url, format: .RGBA8, colorSpace: displaySpace, options: [q: quality])
        case .png:
            try context.writePNGRepresentation(of: img, to: url, format: .RGBA8, colorSpace: displaySpace, options: [:])
        case .tiff:
            try context.writeTIFFRepresentation(of: img, to: url, format: .RGBA16, colorSpace: displaySpace, options: [:])
        }
    }
}
