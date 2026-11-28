import Foundation
import SwiftUI
import AppKit
import CoreImage
import UniformTypeIdentifiers

enum CompareMode: String {
    case off, split
}

/// 吸管取色的用途
enum Eyedropper: Equatable {
    case whiteBalance
    case replaceColor(UUID)

    var hint: String {
        switch self {
        case .whiteBalance: return L("点击照片里本该是白色或灰色的地方", "Click something in the photo that should be white or gray")
        case .replaceColor: return L("点击要替换的颜色", "Click the color you want to replace")
        }
    }
}

/// 一张打开着的照片：图像本身 + 它自己的调整、历史、缓存
final class PhotoSession {
    let id = UUID()
    let url: URL
    let full: CIImage
    let preview: CIImage
    let thumbSource: CIImage
    let original: CGImage?
    var detailSource: CIImage?
    var rendered: CGImage?
    var thumbnail: CGImage?
    var histogram: Histogram?
    var state = EditState()
    var history: [EditState] = [EditState()]
    var historyIndex = 0
    var selectedLayerID: UUID?
    var presetThumbs: [String: CGImage] = [:]

    init(url: URL, full: CIImage, preview: CIImage, thumbSource: CIImage, original: CGImage?) {
        self.url = url
        self.full = full
        self.preview = preview
        self.thumbSource = thumbSource
        self.original = original
    }

    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// 胶片条上的一格
struct FilmItem: Identifiable {
    let id: UUID
    let name: String
    var thumbnail: CGImage?
    var edited: Bool
    var aspect: CGFloat
}

/// 打开新照片时的“沿用调整”提示
enum ApplyBanner: Equatable {
    case offer(sourceID: UUID, name: String, summary: String)
    case applied(name: String)
}

/// 放大时按原图分辨率渲染的局部
struct DetailRender {
    let image: CGImage
    let rect: CGRect
    let state: EditState
    let sessionID: UUID
}

/// 描述一组调整的简短文字，例如“3 个调整图层 · 基础调整”
func adjustmentSummary(_ s: EditState) -> String {
    var parts: [String] = []
    if !s.layers.isEmpty { parts.append(L("\(s.layers.count) 个调整图层", "\(s.layers.count) adjustment layer\(s.layers.count == 1 ? "" : "s")")) }
    if s.basic != BasicSettings() { parts.append(L("基础调整", "Basic")) }
    return parts.isEmpty ? L("无调整", "No adjustments") : parts.joined(separator: " · ")
}

/// 整个 App 的核心状态：多张照片、当前照片的调整、撤销历史、渲染调度、缩放
final class EditDocument: ObservableObject {

    /// 侧栏里“基础调整”这一行的固定 ID
    static let basicID = UUID(uuidString: "00000000-0000-0000-0000-00000000BA51")!

    // MARK: 当前照片

    @Published var state = EditState() {
        didSet { if state != oldValue { stateDidChange() } }
    }
    /// nil 表示选中“基础调整”
    @Published var selectedLayerID: UUID?

    @Published private(set) var previewImage: CGImage?
    @Published private(set) var originalImage: CGImage?
    @Published private(set) var histogram: Histogram?
    @Published private(set) var fileURL: URL?
    @Published private(set) var imageSize: CGSize = .zero
    @Published private(set) var presetThumbnails: [String: CGImage] = [:]
    @Published private(set) var detail: DetailRender?

    // MARK: 多照片

    @Published private(set) var filmstrip: [FilmItem] = []
    @Published private(set) var activeID: UUID?
    @Published var applyBanner: ApplyBanner?
    private var sessions: [PhotoSession] = []
    private var active: PhotoSession? { sessions.first { $0.id == activeID } }
    /// 拷贝下来的调整（⇧⌘C / ⇧⌘V）
    @Published private(set) var clipboard: EditState?

    // MARK: 界面状态

    @Published private(set) var isLoading = false
    @Published private(set) var isExporting = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// 每套用一次风格 +1，画布据此播放“扫光”动画
    @Published private(set) var sweepToken = 0

    @Published var compareMode: CompareMode = .off
    @Published var splitPosition: CGFloat = 0.5
    @Published var showOriginal = false
    /// 相对“适应窗口”的倍数，1 = 刚好放下整张照片
    @Published var zoom: CGFloat = 1 { didSet { if zoom != oldValue { scheduleDetail() } } }
    /// 照片中心相对画布中心的偏移
    @Published var pan: CGSize = .zero { didSet { if pan != oldValue { scheduleDetail() } } }
    @Published var toast: String?
    @Published var showExportSheet = false
    @Published var showInspector = true
    @Published var activeBasicTab = 0
    @Published var isCropping = false { didSet { if isCropping != oldValue { scheduleRender() } } }
    @Published var eyedropper: Eyedropper?

    var lutCache: [String: CubeLUT] = [:]

    let engine = RenderEngine()
    private let renderQueue = DispatchQueue(label: "lumen.render", qos: .userInitiated)
    private let ioQueue = DispatchQueue(label: "lumen.io", qos: .userInitiated)
    private let detailQueue = DispatchQueue(label: "lumen.detail", qos: .userInitiated)
    private var renderInFlight = false
    private var renderPending = false

    private var history: [EditState] = [EditState()]
    private var historyIndex = 0
    private var commitWork: DispatchWorkItem?
    private var applyingHistory = false
    private var toastWork: DispatchWorkItem?
    private var bannerWork: DispatchWorkItem?

    // 视口（画布告诉文档自己的尺寸，用于计算放大时需要渲染哪一块）
    private var viewSize: CGSize = .zero
    private var fitSize: CGSize = .zero
    private var detailWork: DispatchWorkItem?
    private var detailGeneration = 0

    var hasImage: Bool { active != nil }
    var fileName: String { active?.name ?? L("未命名", "Untitled") }

    /// 适应窗口时，1 个原图像素对应多少个点
    var fitScale: CGFloat {
        imageSize.width > 0 ? fitSize.width / imageSize.width : 1
    }

    /// 当前显示比例（相对原图像素）
    var actualPercent: Int { Int((fitScale * zoom * 100).rounded()) }

    var maxZoom: CGFloat { max(4, 4 / max(fitScale, 0.0001)) }

    // MARK: - 打开照片

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .rawImage]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = L("选择要调色的照片（可以多选）", "Choose photos to edit (you can select several)")
        if panel.runModal() == .OK {
            open(urls: panel.urls)
        }
    }

    func open(url: URL) { open(urls: [url]) }

    /// 打开照片：不会覆盖正在编辑的照片，而是加到胶片条里
    func open(urls: [URL], completion: (([UUID]) -> Void)? = nil) {
        guard !urls.isEmpty else { completion?([]); return }
        isLoading = true
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            var loaded: [PhotoSession] = []
            for url in urls {
                guard let full = RenderEngine.loadImage(url: url) else { continue }
                let preview = self.engine.bake(RenderEngine.downscale(full, maxSide: 2200))
                let thumbSource = self.engine.bake(RenderEngine.downscale(preview, maxSide: 280))
                let original = self.engine.renderCG(preview)
                let s = PhotoSession(url: url, full: full, preview: preview, thumbSource: thumbSource, original: original)
                s.thumbnail = original.flatMap { self.engine.thumbnail(of: $0, maxSide: 160) }
                loaded.append(s)
            }
            DispatchQueue.main.async {
                self.isLoading = false
                guard let first = loaded.first else {
                    self.showToast(L("打不开这张图片", "Couldn't open this image"))
                    completion?([])
                    return
                }
                let previous = self.active
                self.stashActive()
                if case .offer = self.applyBanner { self.dismissBanner() }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    self.sessions.append(contentsOf: loaded)
                    self.refreshFilmstrip()
                }
                self.activate(first, isNew: true)
                // 上一张照片有调整的话，询问是否沿用
                if let prev = previous, prev.state != EditState() {
                    self.offerApply(from: prev)
                }
                completion?(loaded.map(\.id))
            }
        }
    }

    // MARK: - 切换照片

    private func stashActive() {
        guard let s = active else { return }
        commitWork?.cancel()
        commitHistory()
        s.state = state
        s.history = history
        s.historyIndex = historyIndex
        s.selectedLayerID = selectedLayerID
        s.rendered = previewImage
        s.histogram = histogram
        s.presetThumbs = presetThumbnails
    }

    func switchTo(_ id: UUID) {
        guard id != activeID, let s = sessions.first(where: { $0.id == id }) else { return }
        stashActive()
        if case .offer = applyBanner { dismissBanner() }
        activate(s, isNew: false)
    }

    private func activate(_ s: PhotoSession, isNew: Bool) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            activeID = s.id
            fileURL = s.url
            imageSize = s.full.extent.size
            originalImage = s.original
            previewImage = isNew ? nil : s.rendered
            histogram = s.histogram
            presetThumbnails = s.presetThumbs
            zoom = 1
            pan = .zero
            detail = nil
            compareMode = .off
            eyedropper = nil
            applyingHistory = true
            state = s.state
            applyingHistory = false
            history = s.history
            historyIndex = s.historyIndex
            selectedLayerID = s.selectedLayerID
        }
        updateUndoFlags(pending: false)
        scheduleRender()
        if s.presetThumbs.isEmpty { renderPresetThumbnails(for: s) }
    }

    func closeSession(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = id == activeID
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            sessions.remove(at: idx)
            refreshFilmstrip()
        }
        if case .offer(let src, _, _) = applyBanner, src == id { dismissBanner() }
        guard wasActive else { return }
        if sessions.isEmpty {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                activeID = nil
                previewImage = nil
                originalImage = nil
                histogram = nil
                fileURL = nil
                detail = nil
                presetThumbnails = [:]
                applyingHistory = true
                state = EditState()
                applyingHistory = false
                history = [EditState()]
                historyIndex = 0
                selectedLayerID = nil
            }
            updateUndoFlags(pending: false)
        } else {
            activate(sessions[min(idx, sessions.count - 1)], isNew: false)
        }
    }

    private func refreshFilmstrip() {
        filmstrip = sessions.map { s in
            let st = s.id == activeID ? state : s.state
            return FilmItem(id: s.id, name: s.name, thumbnail: s.thumbnail, edited: st != EditState(),
                            aspect: s.full.extent.width / max(1, s.full.extent.height))
        }
    }

    /// 给某张照片重新生成缩略图（反映它当前的调整）
    private func refreshThumbnail(for s: PhotoSession) {
        let st = s.id == activeID ? state : s.state
        let luts = lutCache
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let out = self.engine.process(s.thumbSource, state: st, luts: luts)
            let cg = self.engine.renderCG(out)
            DispatchQueue.main.async {
                s.thumbnail = cg
                withAnimation(.easeOut(duration: 0.35)) { self.refreshFilmstrip() }
            }
        }
    }

    private func renderPresetThumbnails(for s: PhotoSession) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            for preset in BuiltInPreset.all {
                let out = self.engine.process(s.thumbSource, state: preset.state, luts: [:])
                guard let cg = self.engine.renderCG(out) else { continue }
                DispatchQueue.main.async {
                    s.presetThumbs[preset.key] = cg
                    if self.activeID == s.id {
                        withAnimation(.easeOut(duration: 0.5)) { self.presetThumbnails[preset.key] = cg }
                    }
                }
            }
        }
    }

    // MARK: - 沿用 / 拷贝 / 粘贴调整

    private func offerApply(from source: PhotoSession) {
        bannerWork?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            applyBanner = .offer(sourceID: source.id, name: source.name, summary: adjustmentSummary(source.state))
        }
    }

    /// 横幅上的“应用”
    func acceptApply() {
        guard case .offer(let srcID, let name, _) = applyBanner,
              let src = sessions.first(where: { $0.id == srcID }) else { return }
        applyState(src.state)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { applyBanner = .applied(name: name) }
        bannerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissBanner() }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    /// 已应用后的“撤销”
    func undoApply() {
        undo()
        dismissBanner()
    }

    func dismissBanner() {
        bannerWork?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { applyBanner = nil }
    }

    private func applyState(_ s: EditState) {
        var copy = s
        // 图层换新 ID，避免和原照片的图层混在一起
        for i in copy.layers.indices { copy.layers[i].id = UUID() }
        ensureLUTsLoaded(copy)
        state = copy
        selectedLayerID = nil
        sweepToken += 1
    }

    func copyAdjustments() {
        clipboard = state
        showToast(L("已拷贝调整 · \(adjustmentSummary(state))", "Adjustments copied · \(adjustmentSummary(state))"))
    }

    func pasteAdjustments() {
        guard let c = clipboard else { return }
        applyState(c)
        showToast(L("已粘贴调整", "Adjustments pasted"))
    }

    /// 把当前照片的调整应用到另一张照片
    func applyCurrent(to id: UUID) {
        guard id != activeID, let s = sessions.first(where: { $0.id == id }) else { return }
        var copy = state
        for i in copy.layers.indices { copy.layers[i].id = UUID() }
        s.history = Array(s.history.prefix(s.historyIndex + 1)) + [copy]
        s.historyIndex = s.history.count - 1
        s.state = copy
        s.rendered = nil
        refreshThumbnail(for: s)
        showToast(L("已应用到「\(s.name)」", "Applied to “\(s.name)”"))
    }

    /// 把当前照片的调整同步到所有照片
    func applyCurrentToAll() {
        for s in sessions where s.id != activeID { applyCurrent(to: s.id) }
        showToast(L("已同步到全部 \(sessions.count - 1) 张照片", "Synced to all \(sessions.count - 1) photos"))
    }

    /// 把另一张照片的调整拿到当前照片
    func takeAdjustments(from id: UUID) {
        guard let s = sessions.first(where: { $0.id == id }) else { return }
        applyState(s.state)
        showToast(L("已沿用「\(s.name)」的调整", "Using adjustments from “\(s.name)”"))
    }

    // MARK: - 渲染

    private func stateDidChange() {
        scheduleRender()
        guard !applyingHistory else { return }
        commitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitHistory() }
        commitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        updateUndoFlags(pending: true)
    }

    func scheduleRender() {
        guard let s = active else { return }
        if renderInFlight {
            renderPending = true
            return
        }
        renderInFlight = true
        var snapshot = state
        if isCropping {
            snapshot.crop.x = 0
            snapshot.crop.y = 0
            snapshot.crop.width = 1
            snapshot.crop.height = 1
        }
        let luts = lutCache
        let src = s.preview
        let origSrc = s.original
        let sid = s.id
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            let out = self.engine.process(src, state: snapshot, luts: luts)
            let cg = self.engine.renderCG(out)
            let hist = cg.map { self.engine.histogram(of: $0) }
            let croppedOrig: CGImage? = snapshot.crop.isIdentity
                ? origSrc
                : self.engine.renderCG(RenderEngine.applyCropAndTransform(src, crop: snapshot.crop))
            DispatchQueue.main.async {
                self.renderInFlight = false
                // 渲染期间切换了照片，就丢掉这次结果
                if sid == self.activeID {
                    if let cg = cg { self.previewImage = cg }
                    if let croppedOrig = croppedOrig { self.originalImage = croppedOrig }
                    if let hist = hist { self.histogram = hist }
                    self.scheduleDetail()
                }
                if self.renderPending {
                    self.renderPending = false
                    self.scheduleRender()
                }
            }
        }
    }

    // MARK: - 缩放与局部高清

    func updateViewport(view: CGSize, fit: CGSize) {
        guard view != viewSize || fit != fitSize else { return }
        viewSize = view
        fitSize = fit
        scheduleDetail()
    }

    /// 以画布上某一点为中心缩放（anchor 是相对画布中心的偏移）
    func setZoom(_ z: CGFloat, anchor: CGPoint = .zero) {
        let newZ = min(max(z, 1), maxZoom)
        let k = newZ / zoom
        let p = CGSize(width: anchor.x, height: anchor.y)
        pan = CGSize(width: p.width - (p.width - pan.width) * k, height: p.height - (p.height - pan.height) * k)
        zoom = newZ
        clampPan()
    }

    func zoomToFit() {
        zoom = 1
        pan = .zero
    }

    /// 切换“适应 ↔ 原始像素”
    func toggleActualSize(anchor: CGPoint = .zero) {
        if zoom > 1.05 {
            zoomToFit()
        } else {
            setZoom(max(1 / max(fitScale, 0.0001), 2), anchor: anchor)
        }
    }

    func clampPan() {
        let disp = CGSize(width: fitSize.width * zoom, height: fitSize.height * zoom)
        let mx = max(0, (disp.width - viewSize.width) / 2 + 60)
        let my = max(0, (disp.height - viewSize.height) / 2 + 60)
        let c = CGSize(width: min(max(pan.width, -mx), mx), height: min(max(pan.height, -my), my))
        if c != pan { pan = c }
    }

    private func scheduleDetail() {
        detailWork?.cancel()
        detailGeneration += 1
        guard let s = active, let preview = previewImage, zoom > 1.05,
              state.crop.isIdentity, !isCropping,
              fitSize.width > 0, viewSize.width > 0 else {
            if detail != nil { detail = nil }
            return
        }
        let disp = CGSize(width: fitSize.width * zoom, height: fitSize.height * zoom)
        let ox = viewSize.width / 2 + pan.width - disp.width / 2
        let oy = viewSize.height / 2 + pan.height - disp.height / 2
        let x0 = max(0, -ox), y0 = max(0, -oy)
        let x1 = min(disp.width, viewSize.width - ox), y1 = min(disp.height, viewSize.height - oy)
        guard x1 > x0, y1 > y0 else { return }
        let rect = CGRect(x: x0 / disp.width, y: y0 / disp.height,
                          width: (x1 - x0) / disp.width, height: (y1 - y0) / disp.height)
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = (x1 - x0) * backing
        // 预览图的分辨率已经够用，就不必额外渲染
        if pixelWidth <= CGFloat(preview.width) * rect.width * 1.1 {
            if detail != nil { detail = nil }
            return
        }
        let gen = detailGeneration
        let snapshot = state
        let luts = lutCache
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.detailQueue.async {
                if s.detailSource == nil {
                    s.detailSource = self.engine.bake(RenderEngine.downscale(s.full, maxSide: 6000))
                }
                guard let src = s.detailSource, gen == self.detailGeneration else { return }
                let cg = self.engine.renderDetail(src, state: snapshot, luts: luts, rect: rect, pixelWidth: pixelWidth)
                DispatchQueue.main.async {
                    guard gen == self.detailGeneration, s.id == self.activeID, let cg = cg else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.detail = DetailRender(image: cg, rect: rect, state: snapshot, sessionID: s.id)
                    }
                }
            }
        }
        detailWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    /// 当前可以显示的局部高清图（参数变了就先不显示，等新的渲染好）
    var currentDetail: DetailRender? {
        guard let d = detail, d.sessionID == activeID, d.state == state, zoom > 1.05 else { return nil }
        return d
    }

    // MARK: - 撤销 / 重做

    private func commitHistory() {
        guard active != nil else { return }
        if history[historyIndex] != state {
            history = Array(history.prefix(historyIndex + 1))
            history.append(state)
            if history.count > 120 { history.removeFirst() }
            historyIndex = history.count - 1
            if let s = active {
                s.state = state
                refreshThumbnail(for: s)
            }
        }
        updateUndoFlags(pending: false)
    }

    private func updateUndoFlags(pending: Bool) {
        canUndo = historyIndex > 0 || pending
        canRedo = !pending && historyIndex < history.count - 1
    }

    func undo() {
        commitWork?.cancel()
        commitHistory()
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        applyHistory()
    }

    func redo() {
        commitWork?.cancel()
        commitHistory()
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
        applyHistory()
    }

    private func applyHistory() {
        applyingHistory = true
        state = history[historyIndex]
        applyingHistory = false
        if let id = selectedLayerID, !state.layers.contains(where: { $0.id == id }) {
            selectedLayerID = nil
        }
        updateUndoFlags(pending: false)
        if let s = active {
            s.state = state
            refreshThumbnail(for: s)
        }
    }

    // MARK: - 图层操作

    func addLayer(_ kind: LayerKind) {
        guard hasImage else { return }
        var layer = AdjustmentLayer(kind: kind)
        let sameKind = state.layers.filter { $0.kind == kind }.count
        if sameKind > 0 { layer.name = "\(kind.title) \(sameKind + 1)" }
        if kind == .equalize { layer.params.equalize.curve = equalizeCurve() }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            if let id = selectedLayerID, let idx = state.layers.firstIndex(where: { $0.id == id }) {
                state.layers.insert(layer, at: idx + 1)
            } else {
                state.layers.append(layer)
            }
            selectedLayerID = layer.id
        }
        switch kind {
        case .lut: chooseLUT(for: layer.id)
        case .matchColor: chooseMatchReference(for: layer.id)
        case .replaceColor: eyedropper = .replaceColor(layer.id)
        default: break
        }
    }

    func deleteLayer(_ id: UUID) {
        guard let idx = state.layers.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            state.layers.remove(at: idx)
            if selectedLayerID == id {
                selectedLayerID = state.layers.isEmpty ? nil : state.layers[max(0, idx - 1)].id
            }
        }
    }

    func duplicateLayer(_ id: UUID) {
        guard let idx = state.layers.firstIndex(where: { $0.id == id }) else { return }
        var copy = state.layers[idx]
        copy.id = UUID()
        copy.name += L(" 拷贝", " copy")
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            state.layers.insert(copy, at: idx + 1)
            selectedLayerID = copy.id
        }
    }

    func moveLayer(_ id: UUID, up: Bool) {
        guard let idx = state.layers.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? idx + 1 : idx - 1
        guard target >= 0 && target < state.layers.count else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            state.layers.swapAt(idx, target)
        }
    }

    func toggleVisible(_ id: UUID) {
        guard let idx = state.layers.firstIndex(where: { $0.id == id }) else { return }
        state.layers[idx].visible.toggle()
    }

    /// 安全的图层绑定：图层被删除时不会越界崩溃
    func layerBinding(_ id: UUID) -> Binding<AdjustmentLayer> {
        let fallback = AdjustmentLayer(kind: .invert)
        return Binding(
            get: { [weak self] in
                self?.state.layers.first(where: { $0.id == id }) ?? fallback
            },
            set: { [weak self] newValue in
                guard let self = self, let idx = self.state.layers.firstIndex(where: { $0.id == id }) else { return }
                self.state.layers[idx] = newValue
            }
        )
    }

    var selectedLayer: AdjustmentLayer? {
        guard let id = selectedLayerID else { return nil }
        return state.layers.first(where: { $0.id == id })
    }

    func resetBasic() { state.basic = BasicSettings() }

    func resetAll() {
        state = EditState()
        selectedLayerID = nil
    }

    // MARK: - 吸管

    /// p 是图片上的相对位置（0...1，左上为原点）
    func pick(at p: CGPoint) {
        guard let mode = eyedropper else { return }
        switch mode {
        case .whiteBalance:
            guard let orig = originalImage else { break }
            let c = engine.sampleColor(orig, at: p)
            let wb = EditDocument.neutralizingWhiteBalance(for: c)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                state.basic.temperature = wb.0
                state.basic.tint = wb.1
            }
        case .replaceColor(let id):
            guard let img = previewImage,
                  let idx = state.layers.firstIndex(where: { $0.id == id }) else { break }
            state.layers[idx].params.replaceColor.target = engine.sampleColor(img, at: p)
        }
        eyedropper = nil
    }

    func sampleForLoupe(at p: CGPoint) -> RGBColor? {
        guard let img = previewImage else { return nil }
        return engine.sampleColor(img, at: p)
    }

    /// 找到让取样点变成中性灰的色温、色调
    static func neutralizingWhiteBalance(for c: RGBColor) -> (Double, Double) {
        let r = CM.toLinear(c.r), g = CM.toLinear(c.g), b = CM.toLinear(c.b)
        var best = (0.0, 0.0), bestErr = Double.infinity
        var t = -100.0
        while t <= 100 {
            var m = -100.0
            while m <= 100 {
                let gains = RenderEngine.whiteBalanceGains(temperature: t, tint: m)
                let rr = r * gains.0, gg = g * gains.1, bb = b * gains.2
                let mean = (rr + gg + bb) / 3
                let err = (rr - mean) * (rr - mean) + (gg - mean) * (gg - mean) + (bb - mean) * (bb - mean)
                if err < bestErr { bestErr = err; best = (t, m) }
                m += 1
            }
            t += 1
        }
        return best
    }

    // MARK: - 色调均化 / 匹配颜色

    func equalizeCurve() -> [Double] {
        guard let counts = histogram?.lumaCounts else { return [] }
        let total = counts.reduce(0, +)
        guard total > 0 else { return [] }
        var acc = 0.0
        var curve = [Double](repeating: 0, count: 256)
        for i in 0..<256 {
            acc += counts[i]
            curve[i] = acc / total
        }
        return curve
    }

    func recomputeEqualize(for id: UUID) {
        guard let idx = state.layers.firstIndex(where: { $0.id == id }) else { return }
        state.layers[idx].params.equalize.curve = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, let i = self.state.layers.firstIndex(where: { $0.id == id }) else { return }
            self.state.layers[i].params.equalize.curve = self.equalizeCurve()
        }
    }

    func chooseMatchReference(for id: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .rawImage]
        panel.message = L("选择一张参考照片，当前照片的色调会向它靠拢", "Choose a reference photo — this photo's tones will move toward it")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let current = previewImage else { return }
        ioQueue.async { [weak self] in
            guard let self = self,
                  let ref = RenderEngine.loadImage(url: url),
                  let refCG = self.engine.renderCG(RenderEngine.downscale(ref, maxSide: 512)) else {
                DispatchQueue.main.async { self?.showToast(L("参考照片读不了", "Couldn't read the reference photo")) }
                return
            }
            let refStats = self.engine.colorStats(of: refCG)
            let srcStats = self.engine.colorStats(of: current)
            DispatchQueue.main.async {
                guard let idx = self.state.layers.firstIndex(where: { $0.id == id }) else { return }
                self.state.layers[idx].params.matchColor.reference = refStats
                self.state.layers[idx].params.matchColor.source = srcStats
                self.state.layers[idx].params.matchColor.referenceName = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    // MARK: - LUT 文件

    func chooseLUT(for id: UUID) {
        let panel = NSOpenPanel()
        if let cube = UTType(filenameExtension: "cube") {
            panel.allowedContentTypes = [cube]
        }
        panel.message = L("选择一个 .cube 格式的 LUT 文件", "Choose a .cube LUT file")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let lut = try CubeLUT.load(url: url)
            lutCache[url.path] = lut
            guard let idx = state.layers.firstIndex(where: { $0.id == id }) else { return }
            state.layers[idx].params.lut.path = url.path
            state.layers[idx].params.lut.displayName = url.deletingPathExtension().lastPathComponent
            state.layers[idx].name = url.deletingPathExtension().lastPathComponent
        } catch {
            showToast(L("这个 LUT 文件读不了，请确认是 3D .cube 格式", "Couldn't read this LUT. Make sure it's a 3D .cube file"))
        }
    }

    private func ensureLUTsLoaded(_ s: EditState) {
        for layer in s.layers where layer.kind == .lut {
            if let path = layer.params.lut.path, lutCache[path] == nil,
               let lut = try? CubeLUT.load(url: URL(fileURLWithPath: path)) {
                lutCache[path] = lut
            }
        }
    }

    // MARK: - 预设

    func savePreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = L("\(fileName)-预设.json", "\(fileName)-preset.json")
        panel.message = L("把当前所有调整保存成预设，以后可以一键套用到别的照片", "Save all current adjustments as a preset to apply to other photos later")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: url)
            showToast(L("预设已保存", "Preset saved"))
        } catch {
            showToast(L("保存失败：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)"))
        }
    }

    func loadPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = L("选择之前保存的预设文件", "Choose a saved preset file")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let s = try JSONDecoder().decode(EditState.self, from: data)
            applyState(s)
            showToast(L("已套用预设", "Preset applied"))
        } catch {
            showToast(L("这个预设文件读不了", "Couldn't read this preset file"))
        }
    }

    func applyBuiltInPreset(_ preset: BuiltInPreset) {
        var next = preset.state
        next.crop = state.crop
        state = next
        selectedLayerID = nil
        sweepToken += 1
    }

    // MARK: - 导出

    func export(format: RenderEngine.ExportFormat, quality: Double, maxSide: CGFloat?) {
        guard let s = active else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = "\(fileName)-Lumen.\(format.ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        showExportSheet = false
        let snapshot = state
        let luts = lutCache
        let full = s.full
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            var src = full
            if let m = maxSide { src = RenderEngine.downscale(src, maxSide: m) }
            let out = self.engine.process(src, state: snapshot, luts: luts)
            var message = L("已导出", "Exported")
            do {
                try self.engine.export(out, to: url, format: format, quality: quality)
            } catch {
                message = L("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self.isExporting = false
                self.showToast(message)
            }
        }
    }

    func exportAll(format: RenderEngine.ExportFormat, quality: Double, maxSide: CGFloat?) {
        guard !sessions.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("导出到此文件夹", "Export to Folder")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        showExportSheet = false
        exportAllToDirectory(dir, format: format, quality: quality, maxSide: maxSide) { _ in }
    }

    func exportAllToDirectory(
        _ dir: URL,
        format: RenderEngine.ExportFormat,
        quality: Double,
        maxSide: CGFloat?,
        completion: @escaping (Result<[URL], Error>) -> Void
    ) {
        if let id = activeID, let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].state = state
        }
        let items = sessions.map { ($0.url.deletingPathExtension().lastPathComponent, $0.full, $0.state) }
        guard !items.isEmpty else {
            completion(.success([]))
            return
        }
        isExporting = true
        let luts = lutCache
        let total = items.count
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            var exportedURLs: [URL] = []
            var usedNames = Set<String>()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for (index, item) in items.enumerated() {
                    DispatchQueue.main.async {
                        self.showToast(L("正在批量导出 \(index + 1)/\(total)…", "Exporting \(index + 1)/\(total)…"))
                    }
                    var src = item.1
                    if let m = maxSide { src = RenderEngine.downscale(src, maxSide: m) }
                    let out = self.engine.process(src, state: item.2, luts: luts)
                    let base = "\(item.0)-Lumen"
                    var candidate = "\(base).\(format.ext)"
                    var suffix = 2
                    while usedNames.contains(candidate) {
                        candidate = "\(base)-\(suffix).\(format.ext)"
                        suffix += 1
                    }
                    usedNames.insert(candidate)
                    let dest = dir.appendingPathComponent(candidate)
                    try self.engine.export(out, to: dest, format: format, quality: quality)
                    exportedURLs.append(dest)
                }
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.showToast(L("已批量导出 \(exportedURLs.count) 张照片", "Batch exported \(exportedURLs.count) photos"))
                    completion(.success(exportedURLs))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.showToast(L("批量导出失败：\(error.localizedDescription)", "Batch export failed: \(error.localizedDescription)"))
                    completion(.failure(error))
                }
            }
        }
    }

    func exportLUT() {
        let panel = NSSavePanel()
        if let cube = UTType(filenameExtension: "cube") {
            panel.allowedContentTypes = [cube]
        }
        panel.nameFieldStringValue = "\(fileName)-Lumen.cube"
        panel.message = L("LUT 只包含颜色和明暗，不包含清晰度、锐化、暗角、颗粒、阴影/高光、HDR 等局部效果", "The LUT contains color and tone only — not clarity, sharpening, vignette, grain, shadows/highlights, HDR or other local effects")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let snapshot = state
        let luts = lutCache
        ioQueue.async { [weak self] in
            let size = 33
            let data = LUTBuilder.build(LUTInputs(fullColorOf: snapshot), size: size, luts: luts)
            var message = L("LUT 已导出", "LUT exported")
            do {
                try CubeLUT.writeCube(rgba: data, size: size, title: url.deletingPathExtension().lastPathComponent, to: url)
            } catch {
                message = L("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { self?.showToast(message) }
        }
    }

    // MARK: - 提示

    func showToast(_ text: String) {
        toastWork?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { toast = text }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    // MARK: - 自动化 / MCP 程序化接口（无弹窗）

    struct SessionSummary: Codable {
        let id: String
        let name: String
        let path: String
        let width: Int
        let height: Int
        let edited: Bool
        let active: Bool
    }

    func sessionSummaries() -> [SessionSummary] {
        sessions.map { s in
            let st = s.id == activeID ? state : s.state
            return SessionSummary(
                id: s.id.uuidString,
                name: s.name,
                path: s.url.path,
                width: Int(s.full.extent.width),
                height: Int(s.full.extent.height),
                edited: st != EditState(),
                active: s.id == activeID
            )
        }
    }

    func applyEditState(_ s: EditState, triggerSweep: Bool = true) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
            applyState(s)
            if !triggerSweep {
                // applyState already increments sweepToken; keep it when triggerSweep is true
            }
        }
    }

    func loadLUTFile(for id: UUID, url: URL) throws {
        let lut = try CubeLUT.load(url: url)
        lutCache[url.path] = lut
        guard let idx = state.layers.firstIndex(where: { $0.id == id }) else { return }
        state.layers[idx].params.lut.path = url.path
        state.layers[idx].params.lut.displayName = url.deletingPathExtension().lastPathComponent
        state.layers[idx].name = url.deletingPathExtension().lastPathComponent
    }

    func setMatchReference(for id: UUID, url: URL, completion: @escaping (Bool) -> Void) {
        guard let current = previewImage else { completion(false); return }
        ioQueue.async { [weak self] in
            guard let self = self,
                  let ref = RenderEngine.loadImage(url: url),
                  let refCG = self.engine.renderCG(RenderEngine.downscale(ref, maxSide: 512)) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let refStats = self.engine.colorStats(of: refCG)
            let srcStats = self.engine.colorStats(of: current)
            DispatchQueue.main.async {
                guard let idx = self.state.layers.firstIndex(where: { $0.id == id }) else {
                    completion(false)
                    return
                }
                self.state.layers[idx].params.matchColor.reference = refStats
                self.state.layers[idx].params.matchColor.source = srcStats
                self.state.layers[idx].params.matchColor.referenceName = url.deletingPathExtension().lastPathComponent
                completion(true)
            }
        }
    }

    func renderPreviewJPEG(maxSide: CGFloat = 1024, quality: Double = 0.86, completion: @escaping ((data: Data, width: Int, height: Int)?) -> Void) {
        guard let s = active else { completion(nil); return }
        let snapshot = state
        let luts = lutCache
        let src = RenderEngine.downscale(s.preview, maxSide: maxSide)
        renderQueue.async { [weak self] in
            guard let self = self else { DispatchQueue.main.async { completion(nil) }; return }
            let out = self.engine.process(src, state: snapshot, luts: luts)
            guard let cg = self.engine.renderCG(out) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async {
                completion((data, cg.width, cg.height))
            }
        }
    }

    func currentColorStats(completion: @escaping (ColorStats?) -> Void) {
        guard let s = active else { completion(nil); return }
        let snapshot = state
        let luts = lutCache
        let src = RenderEngine.downscale(s.preview, maxSide: 512)
        renderQueue.async { [weak self] in
            guard let self = self else { DispatchQueue.main.async { completion(nil) }; return }
            let out = self.engine.process(src, state: snapshot, luts: luts)
            let stats = self.engine.renderCG(out).map { self.engine.colorStats(of: $0) }
            DispatchQueue.main.async { completion(stats) }
        }
    }

    func exportToURL(_ url: URL, format: RenderEngine.ExportFormat, quality: Double, maxSide: CGFloat?, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let s = active else {
            completion(.failure(NSError(domain: "Lumen", code: 404, userInfo: [NSLocalizedDescriptionKey: "No active photo"])))
            return
        }
        isExporting = true
        let snapshot = state
        let luts = lutCache
        let full = s.full
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            var src = full
            if let m = maxSide { src = RenderEngine.downscale(src, maxSide: m) }
            let out = self.engine.process(src, state: snapshot, luts: luts)
            do {
                try self.engine.export(out, to: url, format: format, quality: quality)
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.showToast(L("已导出", "Exported"))
                    completion(.success(url))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.showToast(L("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)"))
                    completion(.failure(error))
                }
            }
        }
    }

    func exportLUTToURL(_ url: URL, size: Int = 33, completion: @escaping (Result<URL, Error>) -> Void) {
        let snapshot = state
        let luts = lutCache
        ioQueue.async { [weak self] in
            let clampedSize = max(17, min(65, size))
            let data = LUTBuilder.build(LUTInputs(fullColorOf: snapshot), size: clampedSize, luts: luts)
            do {
                try CubeLUT.writeCube(rgba: data, size: clampedSize, title: url.deletingPathExtension().lastPathComponent, to: url)
                DispatchQueue.main.async {
                    self?.showToast(L("LUT 已导出", "LUT exported"))
                    completion(.success(url))
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showToast(L("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)"))
                    completion(.failure(error))
                }
            }
        }
    }
}
