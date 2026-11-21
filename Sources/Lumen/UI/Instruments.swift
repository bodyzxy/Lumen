import SwiftUI
import AppKit

// MARK: - 绑定小工具

/// 数组元素的安全绑定
func bindIndex(_ arr: Binding<[Double]>, _ i: Int) -> Binding<Double> {
    Binding(
        get: { i < arr.wrappedValue.count ? arr.wrappedValue[i] : 0 },
        set: { v in if i < arr.wrappedValue.count { arr.wrappedValue[i] = v } }
    )
}

/// RGBColor ↔ ColorPicker 用的 CGColor
func colorBinding(_ c: Binding<RGBColor>) -> Binding<CGColor> {
    Binding(get: { c.wrappedValue.cgColor }, set: { c.wrappedValue = RGBColor(cgColor: $0) })
}

// MARK: - 小标签

struct MicroLabel: View {
    let text: String
    var trailing: String? = nil

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text.uppercased())
                .font(.micro)
                .tracking(1.6)
                .foregroundStyle(Ink.text3)
            Rectangle().fill(Ink.line).frame(height: 0.5)
            if let trailing = trailing {
                Text(trailing).font(.micro).tracking(1.2).foregroundStyle(Ink.text3)
            }
        }
    }
}

// MARK: - 问号说明

struct HelpBadge: View {
    let key: String
    @State private var hovering = false
    @State private var show = false
    @State private var pending: DispatchWorkItem?

    var body: some View {
        Text("?")
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundStyle(hovering ? Color.white : Ink.text3)
            .frame(width: 13, height: 13)
            .background(Circle().fill(hovering ? Ink.text : Color.clear))
            .overlay(Circle().strokeBorder(hovering ? Color.clear : Ink.lineStrong, lineWidth: 0.8))
            .contentShape(Circle().inset(by: -4))
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { inside in
                hovering = inside
                pending?.cancel()
                let work = DispatchWorkItem { show = inside }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.25 : 0.12), execute: work)
            }
            .popover(isPresented: $show, arrowEdge: .leading) {
                HelpCard(entry: HelpTexts.entry(key))
            }
    }
}

struct HelpCard: View {
    let entry: HelpEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.text)
            Text(entry.what)
                .font(.system(size: 12))
                .foregroundStyle(Ink.text2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if entry.up != nil || entry.down != nil {
                VStack(alignment: .leading, spacing: 9) {
                    if let up = entry.up { row("arrow.up", L("调大", "Raise"), up) }
                    if let down = entry.down { row("arrow.down", L("调小", "Lower"), down) }
                }
                .padding(.top, 2)
            }
            if let tip = entry.tip {
                Text(tip)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.text2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Ink.lineStrong).frame(width: 1.5)
                    }
            }
        }
        .padding(16)
        .frame(width: 268, alignment: .leading)
    }

    private func row(_ symbol: String, _ label: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                Text(label).font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(Ink.text)
            .frame(width: 40, alignment: .leading)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Ink.text)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 刻度尺滑杆
//
// 每个参数是一条“刻度尺”：在整行任意位置左右拖动就能调整（相对拖动，不会跳），
// 按住 Option 是微调；单击刻度尺直接跳到那个位置；双击参数名恢复默认。
// 拖动时指针附近的刻度会像放大镜一样隆起。

struct RulerTicks: Shape {
    var needle: Double
    var focus: Double
    var count = 48

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(needle, focus) }
        set { needle = newValue.first; focus = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 0...count {
            let t = Double(i) / Double(count)
            let x = rect.minX + CGFloat(t) * rect.width
            let major = i % 8 == 0
            let base: CGFloat = major ? 6 : 3
            let d = (t - needle) / 0.065
            let boost = CGFloat(focus * exp(-d * d)) * 7
            let h = min(rect.height, base + boost)
            p.addRect(CGRect(x: x - 0.4, y: rect.maxY - h, width: 0.8, height: h))
        }
        return p
    }
}

struct ScrubRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let help: String?
    let hint: [Color]?
    let decimals: Int
    let suffix: String
    let dot: Color?

    @State private var hover = false
    @State private var dragging = false
    @State private var dragStart: Double?
    @State private var width: CGFloat = 200
    @State private var snapTick = 0

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, defaultValue: Double = 0,
         help: String? = nil, hint: [Color]? = nil, decimals: Int = 0, suffix: String = "", dot: Color? = nil) {
        self.title = title
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
        self.help = help
        self.hint = hint
        self.decimals = decimals
        self.suffix = suffix
        self.dot = dot
    }

    private var span: Double { range.upperBound - range.lowerBound }
    private var frac: Double { CM.clamp((value - range.lowerBound) / span) }
    private var originFrac: Double { CM.clamp((defaultValue - range.lowerBound) / span) }
    private var modified: Bool { abs(value - defaultValue) > 0.0001 }

    private var valueText: String {
        let s = String(format: "%.\(decimals)f", value)
        let signed = (range.lowerBound < 0 && value > 0.00001 && defaultValue == 0) ? "+" + s : s
        return signed + suffix
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                if let dot = dot {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: modified ? .medium : .regular))
                    .foregroundStyle(modified ? Ink.text : Ink.text2)
                if let help = help { HelpBadge(key: help) }
                Spacer(minLength: 6)
                Text(valueText)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(modified ? Ink.text : Ink.text3)
                    .contentTransition(.numericText(value: value))
                    .animation(.snappy(duration: 0.18), value: value)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { value = defaultValue }
            }
            .help(L("双击恢复默认值 · 左右拖动调整 · 按住 Option 微调", "Double-click to reset · drag left or right · hold Option to fine-tune"))

            ruler
                .frame(height: 16)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { width = g.size.width }
                        .onChange(of: g.size.width) { _, w in width = w }
                })
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Rectangle().fill(hover || dragging ? Ink.wash : Color.clear))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { g in
                    if dragStart == nil {
                        dragStart = value
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { dragging = true }
                    }
                    let fine = NSEvent.modifierFlags.contains(.option)
                    let delta = Double(g.translation.width / max(width, 1)) * span * (fine ? 0.12 : 1)
                    set((dragStart ?? value) + delta)
                }
                .onEnded { _ in
                    dragStart = nil
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { dragging = false }
                }
        )
        .sensoryFeedback(.alignment, trigger: snapTick)
    }

    private func set(_ raw: Double) {
        var v = min(max(raw, range.lowerBound), range.upperBound)
        let p = pow(10, Double(decimals))
        v = (v * p).rounded() / p
        if abs(v - defaultValue) < span * 0.008 { v = defaultValue }
        if v == defaultValue && value != defaultValue { snapTick += 1 }
        if v != value { value = v }
    }

    private var ruler: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = CGFloat(frac) * w
            let ox = CGFloat(originFrac) * w
            ZStack(alignment: .bottomLeading) {
                if let hint = hint {
                    LinearGradient(colors: hint, startPoint: .leading, endPoint: .trailing)
                        .frame(height: 2)
                        .opacity(0.9)
                }
                RulerTicks(needle: frac, focus: dragging ? 1 : (hover ? 0.35 : 0))
                    .fill(hover || dragging ? Ink.text2 : Ink.text3.opacity(0.75))
                    .padding(.bottom, hint == nil ? 0 : 3)

                // 从默认值到当前值的那一段
                Rectangle()
                    .fill(Ink.text.opacity(0.85))
                    .frame(width: max(0, abs(x - ox)), height: 1.5)
                    .offset(x: min(x, ox))

                // 指针
                Capsule()
                    .fill(Ink.text)
                    .frame(width: dragging ? 2.5 : 1.75, height: dragging ? 16 : 13)
                    .offset(x: x - (dragging ? 1.25 : 0.875))
            }
            .frame(width: w, height: g.size.height, alignment: .bottomLeading)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: frac)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { t in
                    let f = Double(t.location.x / max(w, 1))
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                        set(range.lowerBound + f * span)
                    }
                }
            )
        }
    }
}

// MARK: - 分页标签

struct InkTabs: View {
    let items: [String]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: LanguageSettings.current == .en ? 14 : 20) {
            ForEach(items.indices, id: \.self) { i in
                let selected = i == selection
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { selection = i }
                } label: {
                    VStack(spacing: 7) {
                        Text(items[i])
                            .font(.system(size: LanguageSettings.current == .en ? 12 : 12.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Ink.text : Ink.text3)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 1.5)
                            if selected {
                                Rectangle().fill(Ink.text).frame(height: 1.5)
                                    .matchedGeometryEffect(id: "underline", in: ns)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }
}

/// 分页容器：切换时旧页失焦淡出、新页从虚到实
struct Pager<Content: View>: View {
    let tabs: [String]
    @Binding var selection: Int
    let content: (Int) -> Content

    init(_ tabs: [String], selection: Binding<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.tabs = tabs
        self._selection = selection
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            if tabs.count > 1 {
                InkTabs(items: tabs, selection: $selection)
                Rectangle().fill(Ink.line).frame(height: 0.5)
            }
            ZStack(alignment: .top) {
                content(min(selection, max(0, tabs.count - 1)))
                    .id(selection)
                    .transition(.focusPull)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

// MARK: - 分段选择

struct InkSegment<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns

    init(_ items: [(T, String)], selection: Binding<T>) {
        self.items = items
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let selected = items[i].0 == selection
                Text(items[i].1)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Ink.text : Ink.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.1), radius: 1.5, x: 0, y: 0.5)
                                .matchedGeometryEffect(id: "thumb", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = items[i].0 }
                    }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Ink.washStrong))
    }
}

// MARK: - 开关

struct InkToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var help: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(isOn ? Ink.text : Ink.text2)
            if let help = help { HelpBadge(key: help) }
            Spacer()
            InkSwitch(isOn: $isOn)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

struct InkSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Ink.text : Ink.washStrong)
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : Ink.line, lineWidth: 0.5))
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                .padding(2)
        }
        .frame(width: 30, height: 18)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { isOn.toggle() }
        }
    }
}

// MARK: - 色块选择

struct ColorChip: View {
    let color: Color
    let selected: Bool
    var modified = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(color)
                    .frame(width: 20, height: 20)
                    .overlay(Rectangle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                if selected {
                    Rectangle().strokeBorder(Ink.text, lineWidth: 1.5).frame(width: 26, height: 26)
                }
                if modified {
                    Circle().fill(Ink.text).frame(width: 4, height: 4).offset(y: 16)
                }
            }
            .frame(width: 28, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
    }
}

// MARK: - 会“流动”的直方图

struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatableVector { AnimatableVector(values: []) }

    private static func combine(_ a: AnimatableVector, _ b: AnimatableVector, _ op: (Double, Double) -> Double) -> AnimatableVector {
        let n = max(a.values.count, b.values.count)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let x = i < a.values.count ? a.values[i] : 0
            let y = i < b.values.count ? b.values[i] : 0
            out[i] = op(x, y)
        }
        return AnimatableVector(values: out)
    }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector { combine(lhs, rhs, +) }
    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector { combine(lhs, rhs, -) }
    static func += (lhs: inout AnimatableVector, rhs: AnimatableVector) { lhs = lhs + rhs }
    static func -= (lhs: inout AnimatableVector, rhs: AnimatableVector) { lhs = lhs - rhs }

    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

struct HistogramShape: Shape {
    var data: AnimatableVector
    var filled = true

    var animatableData: AnimatableVector {
        get { data }
        set { data = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let v = data.values
        guard v.count > 1 else { return p }
        let n = v.count
        func pt(_ i: Int) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(i) / CGFloat(n - 1) * rect.width,
                    y: rect.maxY - CGFloat(sqrt(max(0, v[i]))) * rect.height * 0.94)
        }
        if filled {
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            for i in 0..<n { p.addLine(to: pt(i)) }
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        } else {
            p.move(to: pt(0))
            for i in 1..<n { p.addLine(to: pt(i)) }
        }
        return p
    }
}

struct HistogramPanel: View {
    let histogram: Histogram?
    @State private var showRGB = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(L("直方图", "Histogram")).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Ink.text2)
                HelpBadge(key: "histogram")
                Spacer()
                InkSegment([(false, L("亮度", "Luma")), (true, "RGB")], selection: $showRGB)
                    .frame(width: 96)
            }
            ZStack {
                // 四分之一参考线
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { i in
                        Rectangle().fill(Color.clear)
                            .overlay(alignment: .trailing) {
                                if i < 3 { Rectangle().fill(Ink.line).frame(width: 0.5) }
                            }
                    }
                }
                if let h = histogram {
                    if showRGB {
                        Group {
                            HistogramShape(data: AnimatableVector(values: h.red), filled: true)
                                .fill(Color(red: 0.85, green: 0.35, blue: 0.32).opacity(0.28))
                            HistogramShape(data: AnimatableVector(values: h.green), filled: true)
                                .fill(Color(red: 0.32, green: 0.7, blue: 0.42).opacity(0.28))
                            HistogramShape(data: AnimatableVector(values: h.blue), filled: true)
                                .fill(Color(red: 0.32, green: 0.45, blue: 0.85).opacity(0.28))
                        }
                        .blendMode(.multiply)
                    } else {
                        HistogramShape(data: AnimatableVector(values: h.luma), filled: true)
                            .fill(LinearGradient(colors: [Ink.text.opacity(0.22), Ink.text.opacity(0.08)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                    HistogramShape(data: AnimatableVector(values: h.luma), filled: false)
                        .stroke(Ink.text.opacity(0.7), lineWidth: 1)
                } else {
                    Text(L("打开照片后显示", "Appears when a photo is open")).font(.system(size: 11)).foregroundStyle(Ink.text3)
                }
            }
            .frame(height: 78)
            .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 0.5))
            .animation(.easeOut(duration: 0.3), value: histogram)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showRGB)

            HStack {
                clipLabel(L("暗部溢出", "Shadow clipping"), histogram?.clipLow ?? 0)
                Spacer()
                clipLabel(L("高光溢出", "Highlight clipping"), histogram?.clipHigh ?? 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func clipLabel(_ title: String, _ v: Double) -> some View {
        let warn = v > 0.003
        return HStack(spacing: 5) {
            Circle()
                .fill(warn ? Ink.text : Color.clear)
                .overlay(Circle().strokeBorder(Ink.lineStrong, lineWidth: 0.8))
                .frame(width: 6, height: 6)
            Text("\(title) \(String(format: "%.1f", v * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(warn ? Ink.text : Ink.text3)
        }
    }
}

// MARK: - 色轮（低饱和、细线条）

struct ColorWheel: View {
    @Binding var hue: Double
    @Binding var saturation: Double

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let r = d / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let angle = hue * Double.pi / 180
            let dist = CGFloat(saturation / 100) * r
            let puck = CGPoint(x: center.x + CGFloat(cos(angle)) * dist,
                               y: center.y + CGFloat(sin(angle)) * dist)

            ZStack {
                Circle()
                    .fill(AngularGradient(gradient: Gradient(colors: Hint.spectrum(steps: 24)), center: .center))
                    .frame(width: d, height: d)
                    .position(center)
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.96), Color(white: 0.96).opacity(0)],
                                         center: .center, startRadius: 0, endRadius: r))
                    .frame(width: d, height: d)
                    .position(center)
                ForEach([0.33, 0.66], id: \.self) { k in
                    Circle()
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                        .frame(width: d * k, height: d * k)
                        .position(center)
                }
                Path { p in
                    p.move(to: CGPoint(x: center.x - r, y: center.y)); p.addLine(to: CGPoint(x: center.x + r, y: center.y))
                    p.move(to: CGPoint(x: center.x, y: center.y - r)); p.addLine(to: CGPoint(x: center.x, y: center.y + r))
                }
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                Circle()
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                    .frame(width: d, height: d)
                    .position(center)
                Path { p in
                    p.move(to: center); p.addLine(to: puck)
                }
                .stroke(Ink.text.opacity(0.6), lineWidth: 1)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Ink.text, lineWidth: 1.5))
                    .overlay(Circle().fill(saturation < 1 ? Color.clear : Color(muted: hue, s: 0.7, b: 0.85)).frame(width: 7, height: 7))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                    .position(puck)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let dx = g.location.x - center.x
                        let dy = g.location.y - center.y
                        var a = Double(atan2(dy, dx)) * 180 / Double.pi
                        if a < 0 { a += 360 }
                        let k = min(1, Double(hypot(dx, dy) / r))
                        hue = a.rounded()
                        saturation = (k * 100).rounded()
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { saturation = 0 }
            })
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hue)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: saturation)
        }
    }
}

// MARK: - 段落容器（面板里的一组控件）

struct Group0<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(spacing: 0) { content } }
}

/// 面板里的说明性文字
struct NoteText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Ink.text2)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
    }
}
