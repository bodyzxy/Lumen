import SwiftUI
import AppKit

/// 中间的画布：照片舞台 + 底部的控制条和胶片条 + 顶部的提示
///
/// 缩放方式：
/// · 触控板双指捏合缩放，双指滑动平移
/// · 鼠标滚轮缩放；按住 ⌘ 或 ⌥ 滚动也是缩放
/// · 放大后可以直接拖动照片
/// · 双击在“适应窗口”和“100% 原始像素”之间切换
struct CanvasView: View {
    @EnvironmentObject var doc: EditDocument
    @Namespace private var hero
    @State private var dropHover = false
    /// 显影动画进度：0 = 刚放进显影液，1 = 完全显影
    @State private var developed: Double = 1

    // 手势与滚轮
    @State private var gestureStartZoom: CGFloat?
    @State private var gestureStartPan: CGSize?
    @State private var dragStartPan: CGSize?
    @State private var hoverPoint: CGPoint?
    @State private var canvasSize: CGSize = .zero
    @State private var scrollMonitor: Any?

    /// 底部控制条 + 胶片条占用的高度
    private var bottomReserve: CGFloat { doc.hasImage ? 132 : 0 }

    var body: some View {
        GeometryReader { geo in
            let full = geo.size
            let stage = CGSize(width: full.width, height: max(100, full.height - bottomReserve))
            let fitSize = fittedSize(in: stage)

            ZStack(alignment: .topLeading) {
                Ink.paper
                    .ignoresSafeArea()

                if let edited = doc.previewImage, let original = doc.originalImage, let id = doc.activeID {
                    ZStack {
                        PhotoView(edited: edited, original: original,
                                  width: fitSize.width * doc.zoom, height: fitSize.height * doc.zoom)
                        if doc.isCropping {
                            CropOverlay(crop: $doc.state.crop,
                                        size: CGSize(width: fitSize.width * doc.zoom, height: fitSize.height * doc.zoom))
                        }
                    }
                    .id(id)
                    .matchedGeometryEffect(id: id, in: hero)
                    .modifier(Develop(progress: developed))
                    .offset(doc.pan)
                    .position(x: stage.width / 2, y: stage.height / 2)
                    .transition(.opacity)
                } else if doc.isLoading {
                    ProgressView().controlSize(.small)
                        .position(x: stage.width / 2, y: stage.height / 2)
                } else if !doc.hasImage {
                    EmptyStage(hover: dropHover)
                        .position(x: full.width / 2, y: full.height / 2)
                }

                // 顶部提示
                VStack(spacing: 10) {
                    if let banner = doc.applyBanner {
                        ApplyBannerView(banner: banner)
                            .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                    }
                    if let mode = doc.eyedropper {
                        EyedropperBanner(text: mode.hint)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let toast = doc.toast {
                        Text(toast)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Ink.text)
                            .padding(.horizontal, 16)
                            .frame(height: 32)
                            .background(GlassBackground(shape: Capsule()))
                            .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(.top, 14)
                .frame(width: full.width)

                // 底部：控制条 + 胶片条
                if doc.hasImage {
                    VStack(spacing: 10) {
                        CanvasControlBar()
                        Filmstrip(hero: hero)
                    }
                    .frame(width: full.width)
                    .padding(.bottom, 14)
                    .frame(width: full.width, height: full.height, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if doc.isExporting {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(L("正在导出全尺寸照片", "Exporting full-size photo")).font(.system(size: 12)).foregroundStyle(Ink.text2)
                    }
                    .padding(22)
                    .background(GlassBackground(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
                    .position(x: full.width / 2, y: full.height / 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(width: full.width, height: full.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(panAndZoom(stage: stage))
            .onTapGesture(count: 2, coordinateSpace: .local) { loc in
                guard doc.hasImage, doc.eyedropper == nil, loc.y < stage.height else { return }
                let anchor = CGPoint(x: loc.x - stage.width / 2, y: loc.y - stage.height / 2)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { doc.toggleActualSize(anchor: anchor) }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p): hoverPoint = p
                case .ended: hoverPoint = nil
                }
            }
            .onAppear {
                canvasSize = full
                doc.updateViewport(view: stage, fit: fitSize)
            }
            .onChange(of: full) { _, newValue in
                canvasSize = newValue
                let st = CGSize(width: newValue.width, height: max(100, newValue.height - bottomReserve))
                doc.updateViewport(view: st, fit: fittedSize(in: st))
            }
            .onChange(of: doc.imageSize) { _, _ in
                doc.updateViewport(view: stage, fit: fittedSize(in: stage))
            }
            .onChange(of: doc.hasImage) { _, _ in
                let st = CGSize(width: full.width, height: max(100, full.height - bottomReserve))
                doc.updateViewport(view: st, fit: fittedSize(in: st))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: doc.eyedropper)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: doc.hasImage)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: doc.applyBanner)
        .animation(.easeOut(duration: 0.2), value: doc.isExporting)
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            doc.open(urls: urls)
            return true
        } isTargeted: { h in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dropHover = h }
        }
        .onChange(of: doc.previewImage == nil) { _, isNil in
            // 新照片的第一帧出来时播放“显影”
            guard !isNil else { return }
            developed = 0
            DispatchQueue.main.async {
                withAnimation(.timingCurve(0.16, 0.8, 0.24, 1, duration: 1.6)) { developed = 1 }
            }
        }
        .onExitCommand { doc.eyedropper = nil }
        .onAppear { installScrollMonitor() }
        .onDisappear {
            if let m = scrollMonitor { NSEvent.removeMonitor(m) }
            scrollMonitor = nil
        }
    }

    /// 照片在“适应窗口”时的显示尺寸（按当前预览/裁剪后的比例）
    private func fittedSize(in stage: CGSize) -> CGSize {
        let W = doc.previewImage.map { CGFloat($0.width) } ?? doc.imageSize.width
        let H = doc.previewImage.map { CGFloat($0.height) } ?? doc.imageSize.height
        guard W > 0, H > 0 else { return .zero }
        let availW = max(10, stage.width - 64)
        let availH = max(10, stage.height - 48)
        let k = min(availW / W, availH / H)
        return CGSize(width: W * k, height: H * k)
    }

    /// 双指捏合缩放 + 放大后拖动平移
    private func panAndZoom(stage: CGSize) -> some Gesture {
        let magnify = MagnifyGesture()
            .onChanged { v in
                guard doc.hasImage else { return }
                if gestureStartZoom == nil {
                    gestureStartZoom = doc.zoom
                    gestureStartPan = doc.pan
                }
                let start = gestureStartZoom ?? 1
                let startPan = gestureStartPan ?? .zero
                let newZ = min(max(start * v.magnification, 0.6), doc.maxZoom)
                let p = CGPoint(x: v.startLocation.x - stage.width / 2, y: v.startLocation.y - stage.height / 2)
                let k = newZ / start
                doc.pan = CGSize(width: p.x - (p.x - startPan.width) * k, height: p.y - (p.y - startPan.height) * k)
                doc.zoom = newZ
            }
            .onEnded { _ in
                gestureStartZoom = nil
                gestureStartPan = nil
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    if doc.zoom < 1 { doc.zoomToFit() } else { doc.clampPan() }
                }
            }

        let drag = DragGesture(minimumDistance: 3)
            .onChanged { g in
                guard doc.zoom > 1.01, doc.eyedropper == nil else { return }
                if dragStartPan == nil { dragStartPan = doc.pan }
                let s = dragStartPan ?? .zero
                doc.pan = CGSize(width: s.width + g.translation.width, height: s.height + g.translation.height)
            }
            .onEnded { g in
                guard dragStartPan != nil else { return }
                dragStartPan = nil
                // 松手后带一点惯性
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    doc.pan = CGSize(width: doc.pan.width + (g.predictedEndTranslation.width - g.translation.width) * 0.25,
                                     height: doc.pan.height + (g.predictedEndTranslation.height - g.translation.height) * 0.25)
                    doc.clampPan()
                }
            }

        return SimultaneousGesture(magnify, drag)
    }

    /// 滚轮 / 触控板滚动：放大时平移，按住 ⌘/⌥ 或使用鼠标滚轮时缩放
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            guard doc.hasImage, let p = hoverPoint else { return e }
            let stageH = max(100, canvasSize.height - bottomReserve)
            // 鼠标在底部胶片条上时，不拦截（让胶片条自己横向滚动）
            if p.y > stageH { return e }
            let anchor = CGPoint(x: p.x - canvasSize.width / 2, y: p.y - stageH / 2)
            let wantsZoom = e.modifierFlags.contains(.command) || e.modifierFlags.contains(.option) || !e.hasPreciseScrollingDeltas
            if wantsZoom {
                let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY * 0.012 : e.scrollingDeltaY * 0.1
                guard dy != 0 else { return nil }
                doc.setZoom(doc.zoom * exp(dy), anchor: anchor)
                if doc.zoom <= 1.001 { doc.pan = .zero }
                return nil
            }
            guard doc.zoom > 1.01 else { return e }
            doc.pan = CGSize(width: doc.pan.width + e.scrollingDeltaX, height: doc.pan.height + e.scrollingDeltaY)
            doc.clampPan()
            return nil
        }
    }
}

/// 显影：从发白、失焦、无色，慢慢浮现出影像
struct Develop: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = progress
        content
            .saturation(p)
            .brightness((1 - p) * 0.22)
            .blur(radius: (1 - p) * 26)
            .scaleEffect(1 + (1 - p) * 0.035)
            .opacity(min(1, p * 2.2))
    }
}

/// 按住看原图时的擦除遮罩：一道柔和的边从左向右扫过
struct WipeMask: View, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let a = CM.clamp(progress * 1.25 - 0.25)
        let b = CM.clamp(progress * 1.25)
        LinearGradient(stops: [
            .init(color: .black, location: a),
            .init(color: .clear, location: max(a + 0.0001, b))
        ], startPoint: .leading, endPoint: .trailing)
    }
}

struct PhotoView: View {
    @EnvironmentObject var doc: EditDocument
    let edited: CGImage
    let original: CGImage
    let width: CGFloat
    let height: CGFloat

    @State private var wipe: Double = 0
    @State private var sweep: CGFloat = -1.4
    @State private var hoverPoint: CGPoint?
    @State private var cursorPushed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: edited, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: height)

            // 放大时的原图分辨率局部
            if let d = doc.currentDetail {
                Image(decorative: d.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: d.rect.width * width, height: d.rect.height * height)
                    .offset(x: d.rect.minX * width, y: d.rect.minY * height)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // 按住看原图：擦除式过渡
            Image(decorative: original, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: height)
                .mask(WipeMask(progress: wipe))
                .allowsHitTesting(false)

            if doc.compareMode == .split {
                Image(decorative: original, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * doc.splitPosition)
                    }
                    .allowsHitTesting(false)
                splitHandle
                    .transition(.opacity)
            }

            if doc.eyedropper != nil {
                eyedropperLayer
            }
        }
        .frame(width: width, height: height)
        // 扫光：放在 overlay 里，不会影响照片本身的尺寸
        .overlay {
            Color.clear
                .overlay {
                    LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.55), Color.white.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: width * 0.32, height: height * 1.6)
                        .rotationEffect(.degrees(16))
                        .offset(x: sweep * width)
                        .blendMode(.softLight)
                }
                .clipped()
                .allowsHitTesting(false)
        }
        .clipped()
        .coordinateSpace(name: "photo")
        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: 12)
        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        .overlay(alignment: .topLeading) {
            if doc.showOriginal {
                tag(L("原图", "Original")).padding(12).transition(.opacity)
            }
        }
        .onChange(of: doc.showOriginal) { _, v in
            withAnimation(.timingCurve(0.6, 0, 0.2, 1, duration: 0.55)) { wipe = v ? 1 : 0 }
        }
        .onChange(of: doc.sweepToken) { _, _ in
            sweep = -1.4
            withAnimation(.timingCurve(0.45, 0, 0.25, 1, duration: 1.1)) { sweep = 1.4 }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: doc.compareMode)
    }

    private var splitHandle: some View {
        let x = width * doc.splitPosition
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white)
                .frame(width: 1, height: height)
                .shadow(color: .black.opacity(0.25), radius: 1)
                .position(x: x, y: height / 2)
                .allowsHitTesting(false)
            HStack {
                tag(L("原图", "Original"))
                Spacer()
                tag(L("调整后", "Edited"))
            }
            .frame(width: 150)
            .position(x: x, y: 22)
            .allowsHitTesting(false)
            // 只有分割线附近可以拖，其他地方的拖动留给平移
            ZStack {
                Color.clear
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.text)
                    .frame(width: 32, height: 32)
                    .background(GlassBackground(shape: Circle()))
            }
            .frame(width: 40, height: height)
            .contentShape(Rectangle())
            .position(x: x, y: height / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("photo"))
                    .onChanged { g in
                        doc.splitPosition = min(max(g.location.x / width, 0.02), 0.98)
                    }
            )
            .onHover { h in if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
        }
        .frame(width: width, height: height)
    }

    /// 吸管模式：放大镜跟随鼠标，点击取色
    private var eyedropperLayer: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let p = hoverPoint {
                Loupe(image: edited, width: width, height: height, point: p,
                      color: doc.sampleForLoupe(at: CGPoint(x: p.x / width, y: p.y / height)))
                    .offset(x: p.x - 56, y: p.y - 56 - 74)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let loc):
                if !cursorPushed { NSCursor.crosshair.push(); cursorPushed = true }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) { hoverPoint = loc }
            case .ended:
                if cursorPushed { NSCursor.pop(); cursorPushed = false }
                withAnimation(.easeOut(duration: 0.15)) { hoverPoint = nil }
            }
        }
        .gesture(
            SpatialTapGesture().onEnded { t in
                doc.pick(at: CGPoint(x: t.location.x / width, y: t.location.y / height))
                if cursorPushed { NSCursor.pop(); cursorPushed = false }
                hoverPoint = nil
            }
        )
        .onDisappear {
            if cursorPushed { NSCursor.pop(); cursorPushed = false }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(GlassBackground(shape: Capsule()))
    }
}

/// 吸管放大镜
struct Loupe: View {
    let image: CGImage
    let width: CGFloat
    let height: CGFloat
    let point: CGPoint
    let color: RGBColor?

    private let size: CGFloat = 112
    private let zoom: CGFloat = 6

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: width * zoom, height: height * zoom)
                    .offset(x: -point.x * zoom + size / 2, y: -point.y * zoom + size / 2)
                    .frame(width: size, height: size, alignment: .topLeading)
                    .clipShape(Circle())
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .frame(width: zoom + 4, height: zoom + 4)
                    .shadow(color: .black.opacity(0.4), radius: 1)
                Circle()
                    .strokeBorder(color.map { Color(rgb: $0) } ?? Color.white, lineWidth: 6)
                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)

            if let c = color {
                Text(c.hexString)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.text)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(GlassBackground(shape: Capsule()))
            }
        }
    }
}

struct EyedropperBanner: View {
    @EnvironmentObject var doc: EditDocument
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eyedropper")
                .font(.system(size: 12))
                .symbolEffect(.pulse, options: .repeating)
            Text(text).font(.system(size: 12))
            Rectangle().fill(Ink.line).frame(width: 0.5, height: 14)
            Button(L("取消", "Cancel")) { doc.eyedropper = nil }
                .buttonStyle(TextLinkStyle())
        }
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(GlassBackground(shape: Capsule()))
    }
}

// MARK: - “沿用上一张的调整？”

struct ApplyBannerView: View {
    @EnvironmentObject var doc: EditDocument
    let banner: ApplyBanner

    var body: some View {
        ZStack {
            switch banner {
            case .offer(let srcID, let name, let summary):
                HStack(spacing: 12) {
                    sourceThumb(srcID)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("沿用「\(name)」的调整？", "Use adjustments from “\(name)”?"))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Ink.text)
                            .lineLimit(1)
                        Text(summary)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Ink.text3)
                    }
                    Spacer(minLength: 16)
                    Button(L("不用", "Not Now")) { doc.dismissBanner() }
                        .buttonStyle(GlassButtonStyle())
                    Button(L("应用", "Apply")) { doc.acceptApply() }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
                .transition(.focusPull)
            case .applied(let name):
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Ink.text))
                    Text(L("已应用「\(name)」的调整", "Applied adjustments from “\(name)”"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                    Rectangle().fill(Ink.line).frame(width: 0.5, height: 14)
                    Button(L("撤销", "Undo")) { doc.undoApply() }
                        .buttonStyle(TextLinkStyle())
                }
                .transition(.focusPull)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 52)
        .fixedSize(horizontal: true, vertical: false)
        .background(GlassBackground(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
    }

    private func sourceThumb(_ id: UUID) -> some View {
        let item = doc.filmstrip.first { $0.id == id }
        return ZStack {
            Rectangle().fill(Ink.washStrong)
            if let img = item?.thumbnail {
                Image(decorative: img, scale: 1).resizable().scaledToFill()
            }
        }
        .frame(width: 34, height: 34)
        .clipped()
        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - 胶片条：所有打开的照片，点击切换（照片会在缩略图和画布之间形变过渡）

struct Filmstrip: View {
    @EnvironmentObject var doc: EditDocument
    let hero: Namespace.ID

    private let cellHeight: CGFloat = 42

    private func cellWidth(_ item: FilmItem) -> CGFloat {
        min(max(cellHeight * item.aspect, 30), 76)
    }

    private var contentWidth: CGFloat {
        doc.filmstrip.reduce(0) { $0 + cellWidth($1) } + CGFloat(max(0, doc.filmstrip.count - 1)) * 8 + 8
    }

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(doc.filmstrip) { item in
                        FilmCell(item: item, width: cellWidth(item), height: cellHeight,
                                 active: item.id == doc.activeID, hero: hero)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
            .frame(width: min(contentWidth, 620))

            Rectangle().fill(Ink.line).frame(width: 0.5, height: 26)

            Button { doc.presentOpenPanel() } label: {
                Image(systemName: "plus").font(.system(size: 12))
            }
            .buttonStyle(BareIconStyle(size: 28))
            .help(L("添加照片（⌘O）", "Add photos (⌘O)"))
        }
        .padding(.horizontal, 8)
        .frame(height: 62)
        .background(GlassBackground(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: doc.filmstrip.map(\.id))
    }
}

struct FilmCell: View {
    @EnvironmentObject var doc: EditDocument
    let item: FilmItem
    let width: CGFloat
    let height: CGFloat
    let active: Bool
    let hero: Namespace.ID
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if active {
                    thumb
                } else {
                    thumb.matchedGeometryEffect(id: item.id, in: hero)
                }
                if item.edited {
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                        .overlay(Circle().strokeBorder(Ink.text, lineWidth: 1))
                        .padding(3)
                        .allowsHitTesting(false)
                }
                if hover && doc.filmstrip.count > 0 {
                    Button {
                        doc.closeSession(item.id)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Ink.text)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.white))
                            .shadow(color: .black.opacity(0.2), radius: 1.5)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .transition(.scale.combined(with: .opacity))
                    .help(L("关闭这张照片", "Close This Photo"))
                }
            }
            .frame(width: width, height: height)

            Capsule()
                .fill(active ? Ink.text : Color.clear)
                .frame(width: active ? 16 : 4, height: 2)
        }
        .scaleEffect(active ? 1 : (hover ? 0.98 : 0.92))
        .opacity(active ? 1 : (hover ? 1 : 0.68))
        .offset(y: hover && !active ? -2 : 0)
        .contentShape(Rectangle())
        .onTapGesture { doc.switchTo(item.id) }
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { hover = h } }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: active)
        .help(item.name)
        .contextMenu {
            if !active {
                Button(L("切换到这张", "Switch to This Photo")) { doc.switchTo(item.id) }
                Divider()
                Button(L("把当前照片的调整应用到这张", "Apply Current Adjustments to This Photo")) { doc.applyCurrent(to: item.id) }
                Button(L("沿用这张的调整到当前照片", "Use This Photo's Adjustments")) { doc.takeAdjustments(from: item.id) }
            } else {
                Button(L("拷贝调整", "Copy Adjustments")) { doc.copyAdjustments() }
                Button(L("同步当前调整到全部照片", "Sync Current Adjustments to All Photos")) { doc.applyCurrentToAll() }
                    .disabled(doc.filmstrip.count < 2)
            }
            Divider()
            Button(L("关闭这张照片", "Close This Photo"), role: .destructive) { doc.closeSession(item.id) }
        }
    }

    private var thumb: some View {
        ZStack {
            Rectangle().fill(Ink.washStrong)
            if let img = item.thumbnail {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(Rectangle().strokeBorder(active ? Ink.text : Color.black.opacity(0.08), lineWidth: active ? 1 : 0.5))
    }
}

// MARK: - 画布底部的玻璃控制条

struct CanvasControlBar: View {
    @EnvironmentObject var doc: EditDocument

    var body: some View {
        HStack(spacing: 4) {
            Button { doc.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(BareIconStyle())
                .disabled(!doc.canUndo)
                .opacity(doc.canUndo ? 1 : 0.35)
                .help(L("撤销 ⌘Z", "Undo ⌘Z"))
            Button { doc.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(BareIconStyle())
                .disabled(!doc.canRedo)
                .opacity(doc.canRedo ? 1 : 0.35)
                .help(L("重做 ⇧⌘Z", "Redo ⇧⌘Z"))

            divider

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    doc.compareMode = doc.compareMode == .split ? .off : .split
                }
            } label: { Image(systemName: "square.split.2x1") }
                .buttonStyle(BareIconStyle(active: doc.compareMode == .split))
                .help(L("左右对比（\\）", "Split view (\\)"))

            HoldOriginalButton()

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    if doc.isCropping {
                        doc.activeBasicTab = 0
                        doc.isCropping = false
                    } else {
                        doc.selectedLayerID = nil
                        doc.showInspector = true
                        doc.activeBasicTab = 5
                        doc.isCropping = true
                    }
                }
            } label: { Image(systemName: "crop") }
                .buttonStyle(BareIconStyle(active: doc.isCropping))
                .help(L("裁剪与旋转", "Crop & Straighten"))

            divider

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { doc.setZoom(doc.zoom / 1.5) }
            } label: { Image(systemName: "minus") }
                .buttonStyle(BareIconStyle())
                .help(L("缩小（⌘-）", "Zoom out (⌘-)"))

            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { doc.toggleActualSize() }
            } label: {
                Text(doc.zoom <= 1.001 ? L("适应", "Fit") : "\(doc.actualPercent)%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.text2)
                    .frame(width: 50, height: 28)
                    .contentTransition(.numericText())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("在适应窗口和 100% 之间切换（也可以双击照片）", "Toggle between Fit and 100% (or double-click the photo)"))

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { doc.setZoom(doc.zoom * 1.5) }
            } label: { Image(systemName: "plus") }
                .buttonStyle(BareIconStyle())
                .help(L("放大（⌘=）", "Zoom in (⌘=)"))
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background(GlassBackground(shape: Capsule()))
        .animation(.snappy(duration: 0.2), value: doc.actualPercent)
    }

    private var divider: some View {
        Rectangle().fill(Ink.line).frame(width: 0.5, height: 16).padding(.horizontal, 4)
    }
}

struct HoldOriginalButton: View {
    @EnvironmentObject var doc: EditDocument
    @State private var hover = false

    var body: some View {
        Image(systemName: doc.showOriginal ? "eye.fill" : "eye")
            .font(.system(size: 13))
            .foregroundStyle(doc.showOriginal ? Color.white : Ink.text)
            .frame(width: 28, height: 28)
            .background(Circle().fill(doc.showOriginal ? Ink.text : (hover ? Ink.washStrong : Color.clear)))
            .contentShape(Circle())
            .onHover { hover = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !doc.showOriginal { doc.showOriginal = true } }
                    .onEnded { _ in doc.showOriginal = false }
            )
            .help(L("按住查看原图", "Hold to see the original"))
            .animation(.easeOut(duration: 0.15), value: doc.showOriginal)
    }
}

// MARK: - 空状态

struct EmptyStage: View {
    @EnvironmentObject var doc: EditDocument
    let hover: Bool

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Rectangle()
                    .strokeBorder(Ink.lineStrong, style: StrokeStyle(lineWidth: 0.8, dash: hover ? [] : [4, 4]))
                    .frame(width: hover ? 132 : 112, height: hover ? 96 : 80)
                Image(systemName: "camera.aperture")
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(Ink.text2)
                    .rotationEffect(.degrees(hover ? 60 : 0))
            }
            .frame(height: 100)

            VStack(spacing: 8) {
                Text(hover ? L("松开以打开", "Release to open") : L("将照片拖到这里", "Drop photos here"))
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Ink.text)
                    .contentTransition(.opacity)
                Text(L("JPG · PNG · HEIC · TIFF · RAW　可一次打开多张", "JPG · PNG · HEIC · TIFF · RAW — open several at once"))
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(Ink.text3)
            }

            Button(L("打开照片…", "Open Photos…")) { doc.presentOpenPanel() }
                .buttonStyle(GlassButtonStyle())
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: hover)
    }
}

// MARK: - 交互式裁剪框

private struct CropOverlay: View {
    @Binding var crop: CropSettings
    let size: CGSize

    @State private var startCrop: CropSettings?

    private enum Handle { case move, tl, tr, bl, br, t, b, l, r }

    var body: some View {
        let rx = crop.x * size.width
        let ry = crop.y * size.height
        let rw = crop.width * size.width
        let rh = crop.height * size.height
        let cropRect = CGRect(x: rx, y: ry, width: rw, height: rh)

        ZStack(alignment: .topLeading) {
            // 外部暗化遮罩
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRect(cropRect)
            }
            .fill(Color.black.opacity(0.48), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            // 三分线网格
            Path { p in
                for i in 1...2 {
                    let gx = rx + rw * CGFloat(i) / 3
                    p.move(to: CGPoint(x: gx, y: ry))
                    p.addLine(to: CGPoint(x: gx, y: ry + rh))
                    let gy = ry + rh * CGFloat(i) / 3
                    p.move(to: CGPoint(x: rx, y: gy))
                    p.addLine(to: CGPoint(x: rx + rw, y: gy))
                }
            }
            .stroke(Color.white.opacity(0.38), lineWidth: 0.6)
            .allowsHitTesting(false)

            // 内部平移手势
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: max(1, rw), height: max(1, rh))
                .offset(x: rx, y: ry)
                .gesture(drag(.move))

            // 白色外框
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.2)
                .frame(width: max(1, rw), height: max(1, rh))
                .offset(x: rx, y: ry)
                .allowsHitTesting(false)

            // 四角 & 四边手柄
            handleDot(x: rx, y: ry, kind: .tl)
            handleDot(x: rx + rw, y: ry, kind: .tr)
            handleDot(x: rx, y: ry + rh, kind: .bl)
            handleDot(x: rx + rw, y: ry + rh, kind: .br)
            handleDot(x: rx + rw / 2, y: ry, kind: .t)
            handleDot(x: rx + rw / 2, y: ry + rh, kind: .b)
            handleDot(x: rx, y: ry + rh / 2, kind: .l)
            handleDot(x: rx + rw, y: ry + rh / 2, kind: .r)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func handleDot(x: CGFloat, y: CGFloat, kind: Handle) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 10, height: 10)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .position(x: x, y: y)
            .gesture(drag(kind))
    }

    private func drag(_ kind: Handle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if startCrop == nil { startCrop = crop }
                guard let s = startCrop, size.width > 1, size.height > 1 else { return }
                let dx = Double(v.translation.width / size.width)
                let dy = Double(v.translation.height / size.height)
                let minSpan = 0.08
                var nx = s.x, ny = s.y, nw = s.width, nh = s.height

                switch kind {
                case .move:
                    nx = max(0, min(1 - s.width, s.x + dx))
                    ny = max(0, min(1 - s.height, s.y + dy))
                case .tl:
                    let r = s.x + s.width, b = s.y + s.height
                    nx = max(0, min(r - minSpan, s.x + dx)); ny = max(0, min(b - minSpan, s.y + dy))
                    nw = r - nx; nh = b - ny
                case .tr:
                    let b = s.y + s.height
                    ny = max(0, min(b - minSpan, s.y + dy))
                    nw = max(minSpan, min(1 - s.x, s.width + dx)); nh = b - ny
                case .bl:
                    let r = s.x + s.width
                    nx = max(0, min(r - minSpan, s.x + dx))
                    nw = r - nx; nh = max(minSpan, min(1 - s.y, s.height + dy))
                case .br:
                    nw = max(minSpan, min(1 - s.x, s.width + dx))
                    nh = max(minSpan, min(1 - s.y, s.height + dy))
                case .t:
                    let b = s.y + s.height
                    ny = max(0, min(b - minSpan, s.y + dy)); nh = b - ny
                case .b:
                    nh = max(minSpan, min(1 - s.y, s.height + dy))
                case .l:
                    let r = s.x + s.width
                    nx = max(0, min(r - minSpan, s.x + dx)); nw = r - nx
                case .r:
                    nw = max(minSpan, min(1 - s.x, s.width + dx))
                }
                crop.x = nx; crop.y = ny; crop.width = nw; crop.height = nh
            }
            .onEnded { _ in startCrop = nil }
    }
}
