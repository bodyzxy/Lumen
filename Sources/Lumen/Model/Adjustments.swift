import Foundation
import CoreGraphics

// MARK: - 基础类型

/// 用 0...1 存储的 sRGB 颜色，方便存成 JSON 预设
struct RGBColor: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    static let white = RGBColor(r: 1, g: 1, b: 1)
    static let black = RGBColor(r: 0, g: 0, b: 0)

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    var hexString: String {
        String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    init(cgColor: CGColor) {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil) ?? cgColor
        let comps = c.components ?? [0, 0, 0, 1]
        if comps.count >= 3 {
            r = Double(comps[0]); g = Double(comps[1]); b = Double(comps[2])
        } else {
            r = Double(comps[0]); g = r; b = r
        }
    }
}

// MARK: - 基础调整（类似 Camera Raw 的基本面板，顺序固定，始终最先计算）

struct BasicSettings: Codable, Equatable {
    // 白平衡
    var temperature: Double = 0      // -100...100
    var tint: Double = 0             // -100...100
    // 光影
    var exposure: Double = 0         // -5...5 EV
    var contrast: Double = 0         // -100...100
    var highlights: Double = 0       // -100...100
    var shadows: Double = 0          // -100...100
    var whites: Double = 0           // -100...100
    var blacks: Double = 0           // -100...100
    // 质感
    var texture: Double = 0          // -100...100
    var clarity: Double = 0          // -100...100
    var dehaze: Double = 0           // -100...100
    // 色彩
    var vibrance: Double = 0         // -100...100
    var saturation: Double = 0       // -100...100
    // 细节
    var sharpen: Double = 0          // 0...100
    var noiseReduction: Double = 0   // 0...100
    // 效果
    var vignette: Double = 0         // -100...100
    var grain: Double = 0            // 0...100
    var grainSize: Double = 25       // 0...100
    // 校准（Camera Raw 的“校准”面板）
    var shadowTint: Double = 0       // -100...100  绿 ↔ 洋红
    var redHue: Double = 0           // -100...100
    var redSaturation: Double = 0    // -100...100
    var greenHue: Double = 0
    var greenSaturation: Double = 0
    var blueHue: Double = 0
    var blueSaturation: Double = 0
}

// MARK: - 调整图层（对应 PS「图像 › 调整」菜单 + Camera Raw 的 HSL 与颜色分级）

enum LayerKind: String, Codable, CaseIterable, Identifiable {
    // 明暗
    case brightnessContrast, levels, curves, exposure
    // 色彩
    case vibrance, hueSaturation, colorBalance, blackWhite, photoFilter, channelMixer, lut
    // 特殊
    case invert, posterize, threshold, gradientMap, selectiveColor
    // 影调（需要看周围像素的“空间类”调整）
    case shadowsHighlights, hdrToning
    // 图像
    case desaturate, matchColor, replaceColor, equalize
    // Camera Raw
    case hsl, colorGrading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brightnessContrast: return L("亮度/对比度", "Brightness/Contrast")
        case .levels: return L("色阶", "Levels")
        case .curves: return L("曲线", "Curves")
        case .exposure: return L("曝光度", "Exposure")
        case .vibrance: return L("自然饱和度", "Vibrance")
        case .hueSaturation: return L("色相/饱和度", "Hue/Saturation")
        case .colorBalance: return L("色彩平衡", "Color Balance")
        case .blackWhite: return L("黑白", "Black & White")
        case .photoFilter: return L("照片滤镜", "Photo Filter")
        case .channelMixer: return L("通道混合器", "Channel Mixer")
        case .lut: return L("颜色查找", "Color Lookup")
        case .invert: return L("反相", "Invert")
        case .posterize: return L("色调分离", "Posterize")
        case .threshold: return L("阈值", "Threshold")
        case .gradientMap: return L("渐变映射", "Gradient Map")
        case .selectiveColor: return L("可选颜色", "Selective Color")
        case .shadowsHighlights: return L("阴影/高光", "Shadows/Highlights")
        case .hdrToning: return L("HDR 色调", "HDR Toning")
        case .desaturate: return L("去色", "Desaturate")
        case .matchColor: return L("匹配颜色", "Match Color")
        case .replaceColor: return L("替换颜色", "Replace Color")
        case .equalize: return L("色调均化", "Equalize")
        case .hsl: return L("HSL 混色器", "HSL Mixer")
        case .colorGrading: return L("颜色分级", "Color Grading")
        }
    }

    var english: String {
        switch self {
        case .brightnessContrast: return "BRIGHTNESS"
        case .levels: return "LEVELS"
        case .curves: return "CURVES"
        case .exposure: return "EXPOSURE"
        case .vibrance: return "VIBRANCE"
        case .hueSaturation: return "HUE · SAT"
        case .colorBalance: return "BALANCE"
        case .blackWhite: return "MONO"
        case .photoFilter: return "FILTER"
        case .channelMixer: return "MIXER"
        case .lut: return "LOOKUP"
        case .invert: return "INVERT"
        case .posterize: return "POSTERIZE"
        case .threshold: return "THRESHOLD"
        case .gradientMap: return "GRADIENT"
        case .selectiveColor: return "SELECTIVE"
        case .shadowsHighlights: return "SHADOW · HIGHLIGHT"
        case .hdrToning: return "HDR"
        case .desaturate: return "DESATURATE"
        case .matchColor: return "MATCH"
        case .replaceColor: return "REPLACE"
        case .equalize: return "EQUALIZE"
        case .hsl: return "HSL"
        case .colorGrading: return "GRADING"
        }
    }

    var symbol: String {
        switch self {
        case .brightnessContrast: return "sun.max"
        case .levels: return "chart.bar.xaxis"
        case .curves: return "point.topleft.down.curvedto.point.bottomright.up"
        case .exposure: return "plusminus.circle"
        case .vibrance: return "drop.halffull"
        case .hueSaturation: return "drop"
        case .colorBalance: return "scalemass"
        case .blackWhite: return "circle.lefthalf.filled"
        case .photoFilter: return "camera.filters"
        case .channelMixer: return "slider.horizontal.3"
        case .lut: return "cube"
        case .invert: return "arrow.left.arrow.right.circle"
        case .posterize: return "square.stack.3d.down.right"
        case .threshold: return "circle.righthalf.filled"
        case .gradientMap: return "rectangle.split.3x1"
        case .selectiveColor: return "eyedropper"
        case .shadowsHighlights: return "circle.bottomhalf.filled"
        case .hdrToning: return "camera.aperture"
        case .desaturate: return "circle.slash"
        case .matchColor: return "square.on.square"
        case .replaceColor: return "arrow.triangle.swap"
        case .equalize: return "equal.square"
        case .hsl: return "paintpalette"
        case .colorGrading: return "circle.hexagongrid"
        }
    }

    /// 需要参考周围像素，不能合进 LUT，单独在 GPU 上处理
    var isSpatial: Bool {
        self == .shadowsHighlights || self == .hdrToning
    }

    /// 和 PS「图像 › 调整」菜单同样的分组顺序
    static var groups: [(String, [LayerKind])] { [
        (L("明暗", "Tone"), [.brightnessContrast, .levels, .curves, .exposure]),
        (L("色彩", "Color"), [.vibrance, .hueSaturation, .colorBalance, .blackWhite, .photoFilter, .channelMixer, .lut]),
        (L("特殊", "Special"), [.invert, .posterize, .threshold, .gradientMap, .selectiveColor]),
        (L("影调", "Light"), [.shadowsHighlights, .hdrToning]),
        (L("图像", "Image"), [.desaturate, .matchColor, .replaceColor, .equalize]),
        ("Camera Raw", [.hsl, .colorGrading])
    ] }
}

struct CurvePoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct CurvesParams: Codable, Equatable {
    static let identity = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
    var rgb: [CurvePoint] = CurvesParams.identity
    var red: [CurvePoint] = CurvesParams.identity
    var green: [CurvePoint] = CurvesParams.identity
    var blue: [CurvePoint] = CurvesParams.identity
}

struct LevelsChannel: Codable, Equatable {
    var inBlack: Double = 0       // 0...255
    var inWhite: Double = 255     // 0...255
    var gamma: Double = 1         // 0.1...3
    var outBlack: Double = 0      // 0...255
    var outWhite: Double = 255    // 0...255

    var isIdentity: Bool { self == LevelsChannel() }
}

struct LevelsParams: Codable, Equatable {
    var master = LevelsChannel()
    var red = LevelsChannel()
    var green = LevelsChannel()
    var blue = LevelsChannel()
}

struct BrightnessContrastParams: Codable, Equatable {
    var brightness: Double = 0    // -150...150
    var contrast: Double = 0      // -50...100
}

struct ExposureParams: Codable, Equatable {
    var exposure: Double = 0      // -5...5
    var offset: Double = 0        // -0.5...0.5
    var gamma: Double = 1         // 0.1...3
}

struct VibranceParams: Codable, Equatable {
    var vibrance: Double = 0      // -100...100
    var saturation: Double = 0    // -100...100
}

struct HueSatParams: Codable, Equatable {
    var hue: Double = 0              // -180...180
    var saturation: Double = 0       // -100...100
    var lightness: Double = 0        // -100...100
    var colorize = false
    var colorizeHue: Double = 30     // 0...360
    var colorizeSaturation: Double = 25 // 0...100
}

/// 8 个颜色区间：红 橙 黄 绿 浅绿 蓝 紫 洋红
struct HSLParams: Codable, Equatable {
    var hue: [Double] = Array(repeating: 0, count: 8)
    var saturation: [Double] = Array(repeating: 0, count: 8)
    var luminance: [Double] = Array(repeating: 0, count: 8)

    static var names: [String] { [L("红色", "Red"), L("橙色", "Orange"), L("黄色", "Yellow"), L("绿色", "Green"), L("浅绿", "Aqua"), L("蓝色", "Blue"), L("紫色", "Purple"), L("洋红", "Magenta")] }
    static let centers: [Double] = [0, 30, 60, 120, 180, 240, 280, 320]
}

struct ColorBalanceParams: Codable, Equatable {
    /// 每组 3 个值：[青↔红, 洋红↔绿, 黄↔蓝]，-100...100
    var shadows: [Double] = [0, 0, 0]
    var midtones: [Double] = [0, 0, 0]
    var highlights: [Double] = [0, 0, 0]
    var preserveLuminosity = true
}

struct SelectiveColorParams: Codable, Equatable {
    /// 9 组：红 黄 绿 青 蓝 洋红 白 中性 黑；每组 [青, 洋红, 黄, 黑]，-100...100
    var groups: [[Double]] = Array(repeating: [0, 0, 0, 0], count: 9)
    var relative = true

    static var names: [String] { [L("红色", "Reds"), L("黄色", "Yellows"), L("绿色", "Greens"), L("青色", "Cyans"), L("蓝色", "Blues"), L("洋红", "Magentas"), L("白色", "Whites"), L("中性色", "Neutrals"), L("黑色", "Blacks")] }
}

struct ChannelMixerParams: Codable, Equatable {
    /// 每个输出通道：[红, 绿, 蓝, 常数]，百分比 -200...200
    var red: [Double] = [100, 0, 0, 0]
    var green: [Double] = [0, 100, 0, 0]
    var blue: [Double] = [0, 0, 100, 0]
    var monochrome = false
    var gray: [Double] = [40, 40, 20, 0]
}

struct BlackWhiteParams: Codable, Equatable {
    /// 红 黄 绿 青 蓝 洋红 的明暗权重，百分比 -200...300
    var weights: [Double] = [40, 60, 40, 60, 20, 80]
    var tint = false
    var tintHue: Double = 35          // 0...360
    var tintSaturation: Double = 25   // 0...100

    static var names: [String] { [L("红色", "Reds"), L("黄色", "Yellows"), L("绿色", "Greens"), L("青色", "Cyans"), L("蓝色", "Blues"), L("洋红", "Magentas")] }
}

struct PhotoFilterParams: Codable, Equatable {
    var color = RGBColor(hex: 0xEC8A00)
    var density: Double = 25          // 0...100
    var preserveLuminosity = true
}

struct GradientStop: Codable, Equatable, Identifiable {
    var id = UUID()
    var position: Double              // 0...1
    var color: RGBColor
}

struct GradientMapParams: Codable, Equatable {
    var stops: [GradientStop] = [
        GradientStop(position: 0, color: .black),
        GradientStop(position: 1, color: .white)
    ]
    var reverse = false
}

struct ToneWheel: Codable, Equatable {
    var hue: Double = 0               // 0...360
    var saturation: Double = 0        // 0...100
    var luminance: Double = 0         // -100...100
}

struct ColorGradingParams: Codable, Equatable {
    var shadows = ToneWheel()
    var midtones = ToneWheel()
    var highlights = ToneWheel()
    var global = ToneWheel()
    var blending: Double = 50         // 0...100
    var balance: Double = 0           // -100...100
}

struct PosterizeParams: Codable, Equatable {
    var levels: Double = 6            // 2...32
}

struct ThresholdParams: Codable, Equatable {
    var level: Double = 128           // 1...255
}

struct LUTParams: Codable, Equatable {
    var path: String? = nil
    var displayName: String = ""
    var intensity: Double = 100       // 0...100
}

struct ShadowsHighlightsParams: Codable, Equatable {
    var shadowsAmount: Double = 35    // 0...100
    var shadowsRadius: Double = 30    // 1...100
    var highlightsAmount: Double = 0  // 0...100
    var highlightsRadius: Double = 30 // 1...100
    var colorCorrection: Double = 20  // -100...100
    var midtoneContrast: Double = 0   // -100...100
}

struct HDRToningParams: Codable, Equatable {
    var radius: Double = 30           // 1...100
    var strength: Double = 50         // 0...100
    var gamma: Double = 1             // 0.2...2.5
    var exposure: Double = 0          // -3...3
    var detail: Double = 30           // -100...200
    var vibrance: Double = 0          // -100...100
    var saturation: Double = 20       // -100...100
}

/// 颜色统计（YCbCr 空间的均值和标准差），匹配颜色用
struct ColorStats: Codable, Equatable {
    var mean: [Double]   // [Y, Cb, Cr]
    var std: [Double]
}

struct MatchColorParams: Codable, Equatable {
    var referenceName: String = ""
    var reference: ColorStats? = nil
    var source: ColorStats? = nil
    var luminance: Double = 100       // 1...200
    var intensity: Double = 100       // 1...200
    var fade: Double = 0              // 0...100
    var neutralize = false
}

struct ReplaceColorParams: Codable, Equatable {
    var target = RGBColor(hex: 0xD0402B)
    var fuzziness: Double = 40        // 0...200
    var hue: Double = 0               // -180...180
    var saturation: Double = 0        // -100...100
    var lightness: Double = 0         // -100...100
}

struct EqualizeParams: Codable, Equatable {
    /// 256 级亮度映射表，空数组表示还没计算
    var curve: [Double] = []
}

/// 每个图层都带着全部参数结构，只使用和自己类型对应的那一份。
/// 这样写 SwiftUI 绑定最简单，而且这些结构都很小。
struct LayerParams: Codable, Equatable {
    var curves = CurvesParams()
    var levels = LevelsParams()
    var brightnessContrast = BrightnessContrastParams()
    var exposure = ExposureParams()
    var vibrance = VibranceParams()
    var hueSaturation = HueSatParams()
    var hsl = HSLParams()
    var colorBalance = ColorBalanceParams()
    var selectiveColor = SelectiveColorParams()
    var channelMixer = ChannelMixerParams()
    var blackWhite = BlackWhiteParams()
    var photoFilter = PhotoFilterParams()
    var gradientMap = GradientMapParams()
    var colorGrading = ColorGradingParams()
    var posterize = PosterizeParams()
    var threshold = ThresholdParams()
    var lut = LUTParams()
    var shadowsHighlights = ShadowsHighlightsParams()
    var hdrToning = HDRToningParams()
    var matchColor = MatchColorParams()
    var replaceColor = ReplaceColorParams()
    var equalize = EqualizeParams()
}

struct AdjustmentLayer: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: LayerKind
    var name: String
    var visible = true
    var opacity: Double = 100         // 0...100
    var params = LayerParams()

    init(kind: LayerKind) {
        self.kind = kind
        self.name = kind.title
    }

    /// 把当前类型的参数恢复默认（保留载入的文件和取样结果）
    mutating func resetParams() {
        let fresh = LayerParams()
        switch kind {
        case .curves: params.curves = fresh.curves
        case .levels: params.levels = fresh.levels
        case .brightnessContrast: params.brightnessContrast = fresh.brightnessContrast
        case .exposure: params.exposure = fresh.exposure
        case .vibrance: params.vibrance = fresh.vibrance
        case .hueSaturation: params.hueSaturation = fresh.hueSaturation
        case .hsl: params.hsl = fresh.hsl
        case .colorBalance: params.colorBalance = fresh.colorBalance
        case .selectiveColor: params.selectiveColor = fresh.selectiveColor
        case .channelMixer: params.channelMixer = fresh.channelMixer
        case .blackWhite: params.blackWhite = fresh.blackWhite
        case .photoFilter: params.photoFilter = fresh.photoFilter
        case .gradientMap: params.gradientMap = fresh.gradientMap
        case .colorGrading: params.colorGrading = fresh.colorGrading
        case .posterize: params.posterize = fresh.posterize
        case .threshold: params.threshold = fresh.threshold
        case .lut: params.lut.intensity = 100
        case .shadowsHighlights: params.shadowsHighlights = fresh.shadowsHighlights
        case .hdrToning: params.hdrToning = fresh.hdrToning
        case .matchColor:
            params.matchColor.luminance = 100
            params.matchColor.intensity = 100
            params.matchColor.fade = 0
            params.matchColor.neutralize = false
        case .replaceColor:
            let target = params.replaceColor.target
            params.replaceColor = fresh.replaceColor
            params.replaceColor.target = target
        case .invert, .desaturate, .equalize: break
        }
    }
}

// MARK: - 整体编辑状态（撤销历史保存的就是它）

struct EditState: Codable, Equatable {
    var basic = BasicSettings()
    /// 数组下标 0 是最底层，最后一个是最顶层（和 PS 一样，越上面越后计算）
    var layers: [AdjustmentLayer] = []
}
