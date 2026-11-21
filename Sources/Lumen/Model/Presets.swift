import Foundation

/// 内置风格预设：一键出效果，也可以作为学习各个参数的起点
struct BuiltInPreset: Identifiable {
    /// 稳定的标识（不随语言变化），缩略图缓存按它存放
    let key: String
    let name: String
    let subtitle: String
    let state: EditState

    var id: String { key }

    /// 每次读取都按当前语言重新生成名字
    static var all: [BuiltInPreset] {
        [warmFilm, japaneseFresh, tealOrange, contrastBW, fadedVintage, moodyNight]
    }

    static var warmFilm: BuiltInPreset {
        var s = EditState()
        s.basic.temperature = 18
        s.basic.contrast = 12
        s.basic.highlights = -25
        s.basic.shadows = 15
        s.basic.blacks = 10
        s.basic.vibrance = 10
        s.basic.grain = 22
        s.basic.vignette = 15
        var curves = AdjustmentLayer(kind: .curves)
        curves.name = L("胶片褪黑", "Faded Blacks")
        curves.params.curves.rgb = [
            CurvePoint(x: 0, y: 0.06), CurvePoint(x: 0.25, y: 0.24),
            CurvePoint(x: 0.75, y: 0.8), CurvePoint(x: 1, y: 0.96)
        ]
        var grading = AdjustmentLayer(kind: .colorGrading)
        grading.params.colorGrading.shadows = ToneWheel(hue: 200, saturation: 18, luminance: 0)
        grading.params.colorGrading.highlights = ToneWheel(hue: 40, saturation: 22, luminance: 0)
        s.layers = [curves, grading]
        return BuiltInPreset(key: "warmFilm", name: L("暖调胶片", "Warm Film"), subtitle: L("褪黑、暖高光、轻颗粒", "Faded blacks, warm highlights, light grain"), state: s)
    }

    static var japaneseFresh: BuiltInPreset {
        var s = EditState()
        s.basic.exposure = 0.35
        s.basic.temperature = -10
        s.basic.tint = 4
        s.basic.contrast = -18
        s.basic.highlights = -30
        s.basic.shadows = 35
        s.basic.blacks = 20
        s.basic.saturation = -12
        s.basic.vibrance = 8
        var hsl = AdjustmentLayer(kind: .hsl)
        hsl.name = L("日系分色", "Japanese Split")
        hsl.params.hsl.hue[3] = 30         // 绿色偏青
        hsl.params.hsl.saturation[3] = -25
        hsl.params.hsl.luminance[5] = 20   // 蓝色提亮
        hsl.params.hsl.saturation[1] = -10 // 橙色（肤色）收一点
        hsl.params.hsl.luminance[1] = 15
        s.layers = [hsl]
        return BuiltInPreset(key: "japaneseFresh", name: L("清新日系", "Airy Japanese"), subtitle: L("高调、低反差、偏青", "High-key, low contrast, cool teal"), state: s)
    }

    static var tealOrange: BuiltInPreset {
        var s = EditState()
        s.basic.contrast = 20
        s.basic.clarity = 10
        s.basic.vibrance = 15
        var balance = AdjustmentLayer(kind: .colorBalance)
        balance.name = L("青橙分离", "Teal & Orange Split")
        balance.params.colorBalance.shadows = [-22, 0, 25]
        balance.params.colorBalance.highlights = [18, 0, -20]
        var hsl = AdjustmentLayer(kind: .hsl)
        hsl.params.hsl.hue[3] = 60      // 绿色推向青
        hsl.params.hsl.saturation[3] = -40
        hsl.params.hsl.hue[5] = -15
        hsl.params.hsl.saturation[1] = 10
        s.layers = [balance, hsl]
        return BuiltInPreset(key: "tealOrange", name: L("青橙电影", "Teal & Orange"), subtitle: L("暗部青、亮部橙", "Teal shadows, orange highlights"), state: s)
    }

    static var contrastBW: BuiltInPreset {
        var s = EditState()
        s.basic.contrast = 35
        s.basic.clarity = 25
        s.basic.blacks = -15
        s.basic.grain = 30
        var bw = AdjustmentLayer(kind: .blackWhite)
        bw.name = L("红滤镜黑白", "Red-Filter Mono")
        bw.params.blackWhite.weights = [110, 90, -10, -50, -60, 60]
        s.layers = [bw]
        return BuiltInPreset(key: "contrastBW", name: L("高反差黑白", "Contrasty Mono"), subtitle: L("红滤镜效果，天空压暗", "Red-filter look with darkened sky"), state: s)
    }

    static var fadedVintage: BuiltInPreset {
        var s = EditState()
        s.basic.contrast = -10
        s.basic.saturation = -25
        s.basic.temperature = 12
        s.basic.grain = 40
        s.basic.grainSize = 55
        s.basic.vignette = 25
        var curves = AdjustmentLayer(kind: .curves)
        curves.name = L("褪色", "Fade")
        curves.params.curves.rgb = [CurvePoint(x: 0, y: 0.12), CurvePoint(x: 0.5, y: 0.52), CurvePoint(x: 1, y: 0.9)]
        curves.params.curves.blue = [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 1, y: 0.88)]
        var filter = AdjustmentLayer(kind: .photoFilter)
        filter.params.photoFilter.color = RGBColor(hex: 0xAC7A33)
        filter.params.photoFilter.density = 20
        s.layers = [curves, filter]
        return BuiltInPreset(key: "fadedVintage", name: L("复古褪色", "Faded Vintage"), subtitle: L("发灰的黑、泛黄、粗颗粒", "Gray blacks, yellowed, coarse grain"), state: s)
    }

    static var moodyNight: BuiltInPreset {
        var s = EditState()
        s.basic.exposure = -0.3
        s.basic.temperature = -20
        s.basic.contrast = 15
        s.basic.highlights = -20
        s.basic.dehaze = 15
        s.basic.vignette = 30
        var grading = AdjustmentLayer(kind: .colorGrading)
        grading.name = L("夜色", "Night")
        grading.params.colorGrading.shadows = ToneWheel(hue: 220, saturation: 35, luminance: -10)
        grading.params.colorGrading.midtones = ToneWheel(hue: 190, saturation: 12, luminance: 0)
        grading.params.colorGrading.highlights = ToneWheel(hue: 35, saturation: 25, luminance: 0)
        var hsl = AdjustmentLayer(kind: .hsl)
        hsl.params.hsl.saturation[1] = 20
        hsl.params.hsl.luminance[1] = 10
        hsl.params.hsl.saturation[2] = 15
        s.layers = [grading, hsl]
        return BuiltInPreset(key: "moodyNight", name: L("城市夜色", "City Night"), subtitle: L("冷暗部、暖灯光", "Cool shadows, warm lights"), state: s)
    }
}
