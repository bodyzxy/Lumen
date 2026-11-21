import SwiftUI
import AppKit

/// 视觉语言：像一张安静的相纸。
/// 浅色、单色调，只用墨色的深浅表达层级；彩色只出现在它真正代表颜色的地方。
enum Ink {
    /// 主文字、选中状态、指针
    static let text = Color(red: 0.114, green: 0.114, blue: 0.122)
    static let text2 = Color(red: 0.43, green: 0.43, blue: 0.45)
    static let text3 = Color(red: 0.64, green: 0.64, blue: 0.66)
    /// 发丝线
    static let line = Color.black.opacity(0.075)
    static let lineStrong = Color.black.opacity(0.14)
    /// 悬停、凹槽等极浅的底
    static let wash = Color.black.opacity(0.035)
    static let washStrong = Color.black.opacity(0.06)
    /// 画布：带一点暖意的浅灰，像博物馆的墙
    static let paper = Color(red: 0.929, green: 0.925, blue: 0.914)
    static let surface = Color(red: 0.982, green: 0.980, blue: 0.976)
}

extension Font {
    /// 英文小标签（字距拉开，作为排版点缀）
    static let micro = Font.system(size: 9, weight: .semibold)
}

extension Color {
    init(rgb: RGBColor) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }

    /// 低饱和的“说明性”颜色，只用在色温、色相等需要提示方向的地方
    init(muted h: Double, s: Double = 0.42, b: Double = 0.9) {
        var hh = h.truncatingRemainder(dividingBy: 360)
        if hh < 0 { hh += 360 }
        self.init(hue: hh / 360, saturation: s, brightness: b)
    }
}

enum Hint {
    static func spectrum(from start: Double = 0, to end: Double = 360, steps: Int = 12) -> [Color] {
        (0...steps).map { Color(muted: start + (end - start) * Double($0) / Double(steps)) }
    }
    static let temperature = [Color(red: 0.55, green: 0.68, blue: 0.86), Color(white: 0.86), Color(red: 0.88, green: 0.76, blue: 0.48)]
    static let tint = [Color(red: 0.56, green: 0.78, blue: 0.6), Color(white: 0.86), Color(red: 0.84, green: 0.6, blue: 0.8)]
    static let cyanRed = [Color(red: 0.5, green: 0.78, blue: 0.82), Color(white: 0.86), Color(red: 0.86, green: 0.52, blue: 0.5)]
    static let magentaGreen = [Color(red: 0.84, green: 0.56, blue: 0.8), Color(white: 0.86), Color(red: 0.56, green: 0.78, blue: 0.58)]
    static let yellowBlue = [Color(red: 0.88, green: 0.82, blue: 0.5), Color(white: 0.86), Color(red: 0.52, green: 0.6, blue: 0.86)]
    static let tone = [Color(white: 0.15), Color(white: 0.95)]
}

// MARK: - 系统毛玻璃

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// 玻璃质感：材质 + 顶部高光描边 + 外侧发丝线 + 柔和投影
struct GlassBackground<S: InsettableShape>: View {
    let shape: S
    var prominent = false
    var pressed = false

    var body: some View {
        ZStack {
            if prominent {
                shape.fill(Ink.text.opacity(pressed ? 0.82 : 1))
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)],
                                          startPoint: .top, endPoint: .center))
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.white.opacity(pressed ? 0.18 : 0.42))
            }
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(prominent ? 0.28 : 0.95), Color.white.opacity(0.08)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
            shape.strokeBorder(Color.black.opacity(prominent ? 0.2 : 0.07), lineWidth: 0.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(pressed ? 0.04 : 0.08), radius: pressed ? 2 : 7, x: 0, y: pressed ? 1 : 3)
    }
}

/// 胶囊形玻璃按钮
struct GlassButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(prominent ? Color.white : Ink.text)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(GlassBackground(shape: Capsule(), prominent: prominent, pressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 圆形玻璃图标按钮（尺寸固定，保证图标对齐）
struct GlassIconStyle: ButtonStyle {
    var size: CGFloat = 30
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(active ? Color.white : Ink.text)
            .frame(width: size, height: size)
            .background(GlassBackground(shape: Circle(), prominent: active, pressed: configuration.isPressed))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 无底色的图标按钮（悬停时出现一层很淡的底）
struct BareIconStyle: ButtonStyle {
    var size: CGFloat = 28
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        BareIconBody(configuration: configuration, size: size, active: active)
    }

    private struct BareIconBody: View {
        let configuration: ButtonStyleConfiguration
        let size: CGFloat
        let active: Bool
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(active ? Color.white : Ink.text)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(active ? Ink.text : (hover || configuration.isPressed ? Ink.washStrong : Color.clear))
                )
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// 纯文字按钮（链接样式）
struct TextLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TextLinkBody(configuration: configuration)
    }

    private struct TextLinkBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(.system(size: 11.5))
                .foregroundStyle(hover ? Ink.text : Ink.text2)
                .underline(hover, color: Ink.text3)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hover = $0 }
        }
    }
}

/// 让一块区域可以拖动窗口
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - 对焦转场：旧内容失焦淡出，新内容从虚到实

struct FocusPull: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: blur).opacity(opacity).scaleEffect(scale, anchor: .top)
    }
}

extension AnyTransition {
    static var focusPull: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FocusPull(blur: 12, opacity: 0, scale: 0.985),
                                 identity: FocusPull(blur: 0, opacity: 1, scale: 1)),
            removal: .modifier(active: FocusPull(blur: 8, opacity: 0, scale: 1.01),
                               identity: FocusPull(blur: 0, opacity: 1, scale: 1))
        )
    }
}
