import Foundation

/// .cube 格式的 3D LUT（读取外部 LUT、导出自己的调色）
struct CubeLUT {
    let size: Int
    /// RGB 三个一组，红色变化最快，其次绿色，最后蓝色
    let data: [Float]
    var domainMin: (Double, Double, Double) = (0, 0, 0)
    var domainMax: (Double, Double, Double) = (1, 1, 1)

    enum ParseError: Error { case noSize, badData }

    static func load(url: URL) throws -> CubeLUT {
        let text = try String(contentsOf: url, encoding: .utf8)
        var size = 0
        var values: [Float] = []
        var dMin = (0.0, 0.0, 0.0), dMax = (1.0, 1.0, 1.0)

        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let first = parts.first else { continue }
            if first == "LUT_3D_SIZE", parts.count > 1 {
                size = Int(parts[1]) ?? 0
                values.reserveCapacity(size * size * size * 3)
            } else if first == "DOMAIN_MIN", parts.count > 3 {
                dMin = (Double(parts[1]) ?? 0, Double(parts[2]) ?? 0, Double(parts[3]) ?? 0)
            } else if first == "DOMAIN_MAX", parts.count > 3 {
                dMax = (Double(parts[1]) ?? 1, Double(parts[2]) ?? 1, Double(parts[3]) ?? 1)
            } else if let v0 = Float(first), parts.count >= 3,
                      let v1 = Float(parts[1]), let v2 = Float(parts[2]) {
                values.append(v0); values.append(v1); values.append(v2)
            }
        }
        guard size >= 2 else { throw ParseError.noSize }
        guard values.count >= size * size * size * 3 else { throw ParseError.badData }
        var lut = CubeLUT(size: size, data: Array(values.prefix(size * size * size * 3)))
        lut.domainMin = dMin
        lut.domainMax = dMax
        return lut
    }

    /// 三线性插值取样
    func sample(_ rIn: Double, _ gIn: Double, _ bIn: Double) -> (Double, Double, Double) {
        let n = size - 1
        func norm(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            CM.clamp((v - lo) / max(hi - lo, 1e-6)) * Double(n)
        }
        let fr = norm(rIn, domainMin.0, domainMax.0)
        let fg = norm(gIn, domainMin.1, domainMax.1)
        let fb = norm(bIn, domainMin.2, domainMax.2)
        let r0 = min(Int(fr), n - 1), g0 = min(Int(fg), n - 1), b0 = min(Int(fb), n - 1)
        let tr = fr - Double(r0), tg = fg - Double(g0), tb = fb - Double(b0)

        @inline(__always) func at(_ r: Int, _ g: Int, _ b: Int, _ c: Int) -> Double {
            Double(data[((b * size + g) * size + r) * 3 + c])
        }
        var out = [0.0, 0.0, 0.0]
        for c in 0..<3 {
            let c000 = at(r0, g0, b0, c), c100 = at(r0 + 1, g0, b0, c)
            let c010 = at(r0, g0 + 1, b0, c), c110 = at(r0 + 1, g0 + 1, b0, c)
            let c001 = at(r0, g0, b0 + 1, c), c101 = at(r0 + 1, g0, b0 + 1, c)
            let c011 = at(r0, g0 + 1, b0 + 1, c), c111 = at(r0 + 1, g0 + 1, b0 + 1, c)
            let c00 = c000 + (c100 - c000) * tr
            let c10 = c010 + (c110 - c010) * tr
            let c01 = c001 + (c101 - c001) * tr
            let c11 = c011 + (c111 - c011) * tr
            let c0 = c00 + (c10 - c00) * tg
            let c1 = c01 + (c11 - c01) * tg
            out[c] = c0 + (c1 - c0) * tb
        }
        return (out[0], out[1], out[2])
    }

    /// 把 RGBA 浮点 LUT 数据（Core Image 用的格式）写成 .cube 文件
    static func writeCube(rgba: [Float], size: Int, title: String, to url: URL) throws {
        var s = "# Created by Lumen 光调\nTITLE \"\(title)\"\nLUT_3D_SIZE \(size)\nDOMAIN_MIN 0.0 0.0 0.0\nDOMAIN_MAX 1.0 1.0 1.0\n"
        s.reserveCapacity(size * size * size * 30)
        let count = size * size * size
        for i in 0..<count {
            let r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2]
            s += String(format: "%.6f %.6f %.6f\n", r, g, b)
        }
        try s.write(to: url, atomically: true, encoding: .utf8)
    }
}
