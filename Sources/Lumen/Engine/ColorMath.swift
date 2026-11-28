import Foundation

/// 调色用的小工具函数。所有颜色值都在 0...1（伽马编码后的 RGB）。
enum CM {
    @inline(__always) static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        v < lo ? lo : (v > hi ? hi : v)
    }

    @inline(__always) static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    @inline(__always) static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = clamp((x - e0) / (e1 - e0))
        return t * t * (3 - 2 * t)
    }

    /// 感知亮度（对伽马编码值用 Rec.601 权重，和 PS 的灰度接近）
    @inline(__always) static func luma(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.299 * r + 0.587 * g + 0.114 * b
    }

    // MARK: HSL

    static func rgbToHsl(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        let d = maxV - minV
        if d < 1e-9 { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == r {
            h = (g - b) / d + (g < b ? 6 : 0)
        } else if maxV == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h *= 60
        return (h, s, l)
    }

    @inline(__always) private static func hue2rgb(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
        var t = tIn
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6 { return p + (q - p) * 6 * t }
        if t < 1.0 / 2 { return q }
        if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
        return p
    }

    static func hslToRgb(_ hDeg: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        if s <= 1e-9 { return (l, l, l) }
        var h = hDeg.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        let hn = h / 360
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return (hue2rgb(p, q, hn + 1.0 / 3), hue2rgb(p, q, hn), hue2rgb(p, q, hn - 1.0 / 3))
    }

    /// 纯色相对应的 RGB（饱和度 100%，亮度 50%）
    static func hueColor(_ hDeg: Double) -> (Double, Double, Double) {
        hslToRgb(hDeg, 1, 0.5)
    }

    // MARK: 常用调整

    /// S 形对比曲线，a 在 -1...1.5，0 表示不变
    @inline(__always) static func contrastCurve(_ v: Double, _ a: Double) -> Double {
        let x = clamp(v)
        let e = a > 0 ? 1 + a * 1.2 : 1 / (1 + (-a) * 0.9)
        return x < 0.5 ? 0.5 * pow(2 * x, e) : 1 - 0.5 * pow(2 * (1 - x), e)
    }

    /// 自然饱和度：低饱和的颜色加得多，肤色加得少
    static func vibrance(_ c: (Double, Double, Double), _ amt: Double) -> (Double, Double, Double) {
        if amt == 0 { return c }
        let (r, g, b) = c
        let s = max(r, g, b) - min(r, g, b)
        let l = luma(r, g, b)
        var amount = amt * (1 - s) * (1 - s) * 1.4
        if amt > 0 {
            let h = rgbToHsl(r, g, b).h
            if h > 10 && h < 55 { amount *= 0.5 }
        }
        let f = 1 + amount
        return (l + (r - l) * f, l + (g - l) * f, l + (b - l) * f)
    }

    static func saturate(_ c: (Double, Double, Double), _ amt: Double) -> (Double, Double, Double) {
        if amt == 0 { return c }
        let l = luma(c.0, c.1, c.2)
        let f = max(0, 1 + amt)
        return (l + (c.0 - l) * f, l + (c.1 - l) * f, l + (c.2 - l) * f)
    }

    @inline(__always) static func toLinear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    @inline(__always) static func toGamma(_ v: Double) -> Double {
        let x = max(0, v)
        return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
    }

    @inline(__always) static func toYCbCr(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let y = 0.299 * r + 0.587 * g + 0.114 * b
        return (y, (b - y) * 0.564, (r - y) * 0.713)
    }

    @inline(__always) static func fromYCbCr(_ y: Double, _ cb: Double, _ cr: Double) -> (Double, Double, Double) {
        let r = y + cr / 0.713
        let b = y + cb / 0.564
        let g = (y - 0.299 * r - 0.114 * b) / 0.587
        return (r, g, b)
    }

    /// 两个角度之间的有符号最短差（-180...180）
    @inline(__always) static func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// 逐像素图层混合模式
    static func blend(_ base: (Double, Double, Double), _ top: (Double, Double, Double), mode: LayerBlendMode) -> (Double, Double, Double) {
        if mode == .normal { return top }
        func ch(_ b: Double, _ t: Double) -> Double {
            let b = clamp(b), t = clamp(t)
            switch mode {
            case .normal: return t
            case .multiply: return b * t
            case .screen: return 1 - (1 - b) * (1 - t)
            case .overlay: return b < 0.5 ? 2 * b * t : 1 - 2 * (1 - b) * (1 - t)
            case .softLight: return t <= 0.5 ? b - (1 - 2 * t) * b * (1 - b) : b + (2 * t - 1) * (sqrt(b) - b)
            case .hardLight: return t < 0.5 ? 2 * b * t : 1 - 2 * (1 - b) * (1 - t)
            case .colorDodge: return t >= 0.9999 ? 1 : min(1, b / max(1e-5, 1 - t))
            case .colorBurn: return t <= 0.0001 ? 0 : max(0, 1 - (1 - b) / max(1e-5, t))
            case .darken: return min(b, t)
            case .lighten: return max(b, t)
            case .color, .luminosity: return t
            }
        }
        switch mode {
        case .color:
            let (_, _, lb) = rgbToHsl(clamp(base.0), clamp(base.1), clamp(base.2))
            let (ht, st, _) = rgbToHsl(clamp(top.0), clamp(top.1), clamp(top.2))
            return hslToRgb(ht, st, lb)
        case .luminosity:
            let (hb, sb, _) = rgbToHsl(clamp(base.0), clamp(base.1), clamp(base.2))
            let (_, _, lt) = rgbToHsl(clamp(top.0), clamp(top.1), clamp(top.2))
            return hslToRgb(hb, sb, lt)
        default:
            return (ch(base.0, top.0), ch(base.1, top.1), ch(base.2, top.2))
        }
    }
}

// MARK: - 单调三次曲线（曲线工具用，不会出现过冲）

struct MonotoneCurve {
    let table: [Double]

    static let tableSize = 1024

    init(points rawPoints: [CurvePoint]) {
        let pts = rawPoints.sorted { $0.x < $1.x }
        let n = pts.count
        var table = [Double](repeating: 0, count: MonotoneCurve.tableSize)

        if n < 2 {
            for i in 0..<MonotoneCurve.tableSize {
                table[i] = Double(i) / Double(MonotoneCurve.tableSize - 1)
            }
            self.table = table
            return
        }

        let xs = pts.map { $0.x }
        let ys = pts.map { $0.y }
        var deltas = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = max(xs[i + 1] - xs[i], 1e-6)
            deltas[i] = (ys[i + 1] - ys[i]) / dx
        }
        var m = [Double](repeating: 0, count: n)
        m[0] = deltas[0]
        m[n - 1] = deltas[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                if deltas[i - 1] * deltas[i] <= 0 {
                    m[i] = 0
                } else {
                    m[i] = (deltas[i - 1] + deltas[i]) / 2
                }
            }
        }
        // Fritsch–Carlson 约束，保证单调
        for i in 0..<(n - 1) {
            if abs(deltas[i]) < 1e-9 {
                m[i] = 0; m[i + 1] = 0
                continue
            }
            let a = m[i] / deltas[i]
            let b = m[i + 1] / deltas[i]
            let s = a * a + b * b
            if s > 9 {
                let t = 3 / s.squareRoot()
                m[i] = t * a * deltas[i]
                m[i + 1] = t * b * deltas[i]
            }
        }

        var seg = 0
        for i in 0..<MonotoneCurve.tableSize {
            let x = Double(i) / Double(MonotoneCurve.tableSize - 1)
            if x <= xs[0] { table[i] = CM.clamp(ys[0]); continue }
            if x >= xs[n - 1] { table[i] = CM.clamp(ys[n - 1]); continue }
            while seg < n - 2 && x > xs[seg + 1] { seg += 1 }
            let h = max(xs[seg + 1] - xs[seg], 1e-6)
            let t = (x - xs[seg]) / h
            let t2 = t * t, t3 = t2 * t
            let h00 = 2 * t3 - 3 * t2 + 1
            let h10 = t3 - 2 * t2 + t
            let h01 = -2 * t3 + 3 * t2
            let h11 = t3 - t2
            let y = h00 * ys[seg] + h10 * h * m[seg] + h01 * ys[seg + 1] + h11 * h * m[seg + 1]
            table[i] = CM.clamp(y)
        }
        self.table = table
    }

    @inline(__always) func value(_ x: Double) -> Double {
        let f = CM.clamp(x) * Double(MonotoneCurve.tableSize - 1)
        let i = Int(f)
        if i >= MonotoneCurve.tableSize - 1 { return table[MonotoneCurve.tableSize - 1] }
        let t = f - Double(i)
        return table[i] + (table[i + 1] - table[i]) * t
    }

    static func isIdentity(_ pts: [CurvePoint]) -> Bool {
        pts.count == 2 && pts[0] == CurvePoint(x: 0, y: 0) && pts[1] == CurvePoint(x: 1, y: 1)
    }
}
