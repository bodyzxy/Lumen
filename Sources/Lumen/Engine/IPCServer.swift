import Foundation
import SwiftUI
import AppKit
import Darwin

/// 本地 Unix Domain Socket 服务（~/.lumen/lumen.sock）
/// 供 LumenMCP 实时控制 Lumen.app 界面与 EditDocument，所有修改均在主线程带动画执行。
final class IPCServer {
    static let shared = IPCServer()

    static var socketPath: String {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lumen")
        return dir.appendingPathComponent("lumen.sock").path
    }

    private weak var doc: EditDocument?
    private var serverFD: Int32 = -1
    private var running = false
    private let acceptQueue = DispatchQueue(label: "lumen.ipc.accept", qos: .userInitiated)
    private let clientQueue = DispatchQueue(label: "lumen.ipc.client", qos: .userInitiated, attributes: .concurrent)

    private init() {}

    func start(doc: EditDocument) {
        self.doc = doc
        guard !running else { return }

        signal(SIGPIPE, SIG_IGN)

        let path = Self.socketPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= maxLen else {
            close(fd)
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            for (i, b) in bytes.enumerated() {
                ptr[i] = b
            }
        }

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindRes == 0, listen(fd, 16) == 0 else {
            close(fd)
            return
        }

        serverFD = fd
        running = true

        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        running = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(Self.socketPath)
    }

    private func acceptLoop() {
        while running && serverFD >= 0 {
            var clientAddr = sockaddr()
            var len = socklen_t(MemoryLayout<sockaddr>.size)
            let clientFD = accept(serverFD, &clientAddr, &len)
            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }
            clientQueue.async { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)

        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(chunk, count: n)

            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                if lineData.isEmpty { continue }
                let response = processLine(lineData)
                var out = response
                out.append(0x0A)
                writeAll(fd: fd, data: out)
            }
        }
    }

    private func writeAll(fd: Int32, data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = write(fd, base.advanced(by: sent), data.count - sent)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    private func processLine(_ data: Data) -> Data {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = obj["method"] as? String else {
            return encodeError(id: nil, code: -32600, message: "Invalid JSON request")
        }
        let reqID = obj["id"]
        let params = obj["params"] as? [String: Any] ?? [:]

        let sem = DispatchSemaphore(value: 0)
        var resultPayload: Data?

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let doc = self.doc else {
                resultPayload = self?.encodeError(id: reqID, code: -32000, message: "EditDocument unavailable")
                sem.signal()
                return
            }
            self.dispatch(method: method, params: params, doc: doc) { outcome in
                switch outcome {
                case .success(let value):
                    resultPayload = self.encodeSuccess(id: reqID, result: value)
                case .failure(let err):
                    resultPayload = self.encodeError(id: reqID, code: err.code, message: err.message)
                }
                sem.signal()
            }
        }

        _ = sem.wait(timeout: .now() + 60)
        return resultPayload ?? encodeError(id: reqID, code: -32001, message: "IPC timeout")
    }

    private struct IPCError: Error {
        let code: Int
        let message: String
    }

    // MARK: - 指令路由（运行在 MainActor / 主线程）

    private func dispatch(method: String, params: [String: Any], doc: EditDocument, done: @escaping (Result<Any, IPCError>) -> Void) {
        switch method {
        case "ping":
            done(.success([
                "status": "ok",
                "hasImage": doc.hasImage,
                "activeSession": doc.activeID?.uuidString as Any,
                "fileName": doc.fileName
            ]))

        case "open_photos":
            guard let paths = params["paths"] as? [String], !paths.isEmpty else {
                done(.failure(IPCError(code: -32602, message: "Missing 'paths' array"))); return
            }
            let urls = paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            NSApp.activate(ignoringOtherApps: false)
            doc.open(urls: urls) { ids in
                if ids.isEmpty {
                    done(.failure(IPCError(code: -32002, message: "Failed to open any image from provided paths")))
                } else {
                    let sessions = doc.sessionSummaries().compactMap { Self.toDict($0) }
                    done(.success(["opened_ids": ids.map(\.uuidString), "sessions": sessions]))
                }
            }

        case "list_sessions":
            let sessions = doc.sessionSummaries().compactMap { Self.toDict($0) }
            done(.success(["sessions": sessions, "active_id": doc.activeID?.uuidString as Any]))

        case "switch_session":
            guard let sidStr = params["session_id"] as? String, let sid = UUID(uuidString: sidStr) else {
                done(.failure(IPCError(code: -32602, message: "Invalid 'session_id'"))); return
            }
            guard doc.filmstrip.contains(where: { $0.id == sid }) else {
                done(.failure(IPCError(code: -32004, message: "Session not found"))); return
            }
            doc.switchTo(sid)
            done(.success(["active_id": sid.uuidString]))

        case "close_session":
            let sid: UUID?
            if let s = params["session_id"] as? String {
                sid = UUID(uuidString: s)
            } else {
                sid = doc.activeID
            }
            guard let target = sid, doc.filmstrip.contains(where: { $0.id == target }) else {
                done(.failure(IPCError(code: -32004, message: "Session not found"))); return
            }
            doc.closeSession(target)
            done(.success(["closed_id": target.uuidString]))

        case "get_edit_state":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            done(.success([
                "state": Self.toDict(doc.state) ?? [:],
                "selected_layer_id": doc.selectedLayerID?.uuidString as Any,
                "active_basic_tab": doc.activeBasicTab,
                "compare_mode": doc.compareMode.rawValue,
                "zoom": doc.zoom
            ]))

        case "set_basic_adjustments":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            let patch = params["params"] as? [String: Any] ?? params
            let resetOthers = params["reset_others"] as? Bool ?? false
            let baseObj: Any = resetOthers ? (Self.toDict(BasicSettings()) ?? [:]) : (Self.toDict(doc.state.basic) ?? [:])
            let merged = Self.mergeJSON(base: baseObj, patch: patch)
            guard let data = try? JSONSerialization.data(withJSONObject: merged),
                  let decoded = try? JSONDecoder().decode(BasicSettings.self, from: data) else {
                done(.failure(IPCError(code: -32602, message: "Invalid BasicSettings fields"))); return
            }
            let tab = Self.basicTab(forKeys: Array(patch.keys))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                doc.selectedLayerID = nil
                if let tab = tab { doc.activeBasicTab = tab }
                doc.state.basic = decoded
            }
            let summary = patch.keys.filter { $0 != "reset_others" }.sorted().prefix(3).joined(separator: ", ")
            doc.showToast("AI · \(L("调整基础参数", "Basic")): \(summary)")
            done(.success(["basic": Self.toDict(doc.state.basic) ?? [:], "active_basic_tab": doc.activeBasicTab]))

        case "reset_adjustments":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            let scope = params["scope"] as? String ?? "all"
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                if scope == "basic" {
                    doc.resetBasic()
                    doc.selectedLayerID = nil
                } else {
                    doc.resetAll()
                }
            }
            doc.showToast("AI · \(L("重置调整", "Reset"))")
            done(.success(["reset": scope]))

        case "add_layer":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            guard let kindStr = params["kind"] as? String, let kind = LayerKind(rawValue: kindStr) else {
                done(.failure(IPCError(code: -32602, message: "Invalid or missing 'kind'"))); return
            }
            var layer = AdjustmentLayer(kind: kind)
            let sameCount = doc.state.layers.filter { $0.kind == kind }.count
            if let name = params["name"] as? String, !name.isEmpty {
                layer.name = name
            } else if sameCount > 0 {
                layer.name = "\(kind.title) \(sameCount + 1)"
            }
            if let opacity = params["opacity"] as? Double {
                layer.opacity = max(0, min(100, opacity))
            }
            if let visible = params["visible"] as? Bool {
                layer.visible = visible
            }
            if let layerParamsPatch = params["params"] as? [String: Any] {
                if let mergedParams = Self.decodeMergedLayerParams(base: layer.params, kind: kind, patch: layerParamsPatch) {
                    layer.params = mergedParams
                } else {
                    done(.failure(IPCError(code: -32602, message: "Invalid 'params' for layer kind '\(kind.rawValue)'"))); return
                }
            }
            if kind == .equalize && layer.params.equalize.curve.isEmpty {
                layer.params.equalize.curve = doc.equalizeCurve()
            }

            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                if let index = params["index"] as? Int, index >= 0 && index <= doc.state.layers.count {
                    doc.state.layers.insert(layer, at: index)
                } else if let sel = doc.selectedLayerID, let idx = doc.state.layers.firstIndex(where: { $0.id == sel }) {
                    doc.state.layers.insert(layer, at: idx + 1)
                } else {
                    doc.state.layers.append(layer)
                }
                doc.selectedLayerID = layer.id
            }

            if kind == .lut, let path = layer.params.lut.path {
                try? doc.loadLUTFile(for: layer.id, url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            }
            doc.showToast("AI · \(L("添加图层", "Added")) 「\(layer.name)」")
            let latest = doc.state.layers.first(where: { $0.id == layer.id }) ?? layer
            done(.success(["layer": Self.toDict(latest) ?? [:]]))

        case "update_layer":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            guard let idStr = params["layer_id"] as? String, let lid = UUID(uuidString: idStr),
                  let idx = doc.state.layers.firstIndex(where: { $0.id == lid }) else {
                done(.failure(IPCError(code: -32004, message: "Layer not found"))); return
            }
            var layer = doc.state.layers[idx]
            if let name = params["name"] as? String { layer.name = name }
            if let visible = params["visible"] as? Bool { layer.visible = visible }
            if let opacity = params["opacity"] as? Double { layer.opacity = max(0, min(100, opacity)) }
            if let patch = params["params"] as? [String: Any] {
                if let merged = Self.decodeMergedLayerParams(base: layer.params, kind: layer.kind, patch: patch) {
                    layer.params = merged
                } else {
                    done(.failure(IPCError(code: -32602, message: "Invalid 'params' for layer '\(layer.kind.rawValue)'"))); return
                }
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                doc.selectedLayerID = lid
                doc.state.layers[idx] = layer
            }
            if layer.kind == .lut, let path = layer.params.lut.path {
                try? doc.loadLUTFile(for: lid, url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            }
            doc.showToast("AI · \(L("更新图层", "Updated")) 「\(layer.name)」")
            done(.success(["layer": Self.toDict(doc.state.layers[idx]) ?? [:]]))

        case "layer_action":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            guard let idStr = params["layer_id"] as? String, let lid = UUID(uuidString: idStr),
                  doc.state.layers.contains(where: { $0.id == lid }),
                  let action = params["action"] as? String else {
                done(.failure(IPCError(code: -32602, message: "Invalid 'layer_id' or 'action'"))); return
            }
            switch action {
            case "delete": doc.deleteLayer(lid)
            case "duplicate": doc.duplicateLayer(lid)
            case "move_up": doc.moveLayer(lid, up: true)
            case "move_down": doc.moveLayer(lid, up: false)
            case "select":
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { doc.selectedLayerID = lid }
            default:
                done(.failure(IPCError(code: -32602, message: "Unknown layer action '\(action)'"))); return
            }
            done(.success(["ok": true, "layers_count": doc.state.layers.count]))

        case "apply_preset":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            if let key = params["preset_key"] as? String,
               let preset = BuiltInPreset.all.first(where: { $0.key == key }) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
                    doc.applyBuiltInPreset(preset)
                }
                doc.showToast("AI · \(L("套用风格", "Applied")) 「\(preset.name)」")
                done(.success(["preset": preset.key, "state": Self.toDict(doc.state) ?? [:]]))
            } else if let path = params["preset_path"] as? String {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                guard let data = try? Data(contentsOf: url),
                      let s = try? JSONDecoder().decode(EditState.self, from: data) else {
                    done(.failure(IPCError(code: -32002, message: "Failed to load preset JSON"))); return
                }
                doc.applyEditState(s, triggerSweep: true)
                doc.showToast("AI · \(L("已套用预设", "Preset applied"))")
                done(.success(["preset_path": url.path, "state": Self.toDict(doc.state) ?? [:]]))
            } else {
                done(.failure(IPCError(code: -32602, message: "Specify 'preset_key' or 'preset_path'")))
            }

        case "sync_adjustments":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            if let targets = params["target_session_ids"] as? [String] {
                for t in targets {
                    if let uuid = UUID(uuidString: t) { doc.applyCurrent(to: uuid) }
                }
                done(.success(["synced": targets.count]))
            } else {
                doc.applyCurrentToAll()
                done(.success(["synced": max(0, doc.filmstrip.count - 1)]))
            }

        case "undo":
            guard doc.canUndo else {
                done(.failure(IPCError(code: -32005, message: "Nothing to undo"))); return
            }
            doc.undo()
            doc.showToast("AI · \(L("撤销", "Undo"))")
            done(.success(["can_undo": doc.canUndo, "can_redo": doc.canRedo]))

        case "redo":
            guard doc.canRedo else {
                done(.failure(IPCError(code: -32005, message: "Nothing to redo"))); return
            }
            doc.redo()
            doc.showToast("AI · \(L("重做", "Redo"))")
            done(.success(["can_undo": doc.canUndo, "can_redo": doc.canRedo]))

        case "set_view":
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                if let mode = params["compare_mode"] as? String {
                    doc.compareMode = (mode == "split") ? .split : .off
                }
                if let pos = params["split_position"] as? Double {
                    doc.splitPosition = min(max(pos, 0.02), 0.98)
                }
                if let orig = params["show_original"] as? Bool {
                    doc.showOriginal = orig
                }
                if let showInsp = params["show_inspector"] as? Bool {
                    doc.showInspector = showInsp
                }
                if let zStr = params["zoom"] as? String {
                    if zStr == "fit" { doc.zoomToFit() }
                    else if zStr == "100%" || zStr == "actual" {
                        doc.setZoom(max(1 / max(doc.fitScale, 0.0001), 2))
                    }
                } else if let zNum = params["zoom"] as? Double {
                    doc.setZoom(zNum)
                }
            }
            done(.success([
                "compare_mode": doc.compareMode.rawValue,
                "split_position": doc.splitPosition,
                "show_original": doc.showOriginal,
                "zoom": doc.zoom
            ]))

        case "get_image_analysis":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            doc.currentColorStats { stats in
                var res: [String: Any] = [
                    "file_name": doc.fileName,
                    "width": Int(doc.imageSize.width),
                    "height": Int(doc.imageSize.height)
                ]
                if let h = doc.histogram {
                    res["clip_low_ratio"] = h.clipLow
                    res["clip_high_ratio"] = h.clipHigh
                    res["histogram_luma_16bins"] = Self.downsample16(h.luma)
                }
                if let st = stats {
                    res["ycbcr_mean"] = st.mean
                    res["ycbcr_std"] = st.std
                }
                done(.success(res))
            }

        case "sample_color":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            guard let x = params["x"] as? Double, let y = params["y"] as? Double else {
                done(.failure(IPCError(code: -32602, message: "Missing 'x' and 'y' in 0...1"))); return
            }
            let src = (params["source"] as? String == "original") ? doc.originalImage : doc.previewImage
            guard let cg = src else {
                done(.failure(IPCError(code: -32003, message: "Image not rendered yet"))); return
            }
            let c = doc.engine.sampleColor(cg, at: CGPoint(x: x, y: y))
            done(.success(["r": c.r, "g": c.g, "b": c.b, "hex": c.hexString]))

        case "auto_white_balance":
            guard doc.hasImage, let orig = doc.originalImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            guard let x = params["x"] as? Double, let y = params["y"] as? Double else {
                done(.failure(IPCError(code: -32602, message: "Missing 'x' and 'y' in 0...1"))); return
            }
            let c = doc.engine.sampleColor(orig, at: CGPoint(x: x, y: y))
            let wb = EditDocument.neutralizingWhiteBalance(for: c)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                doc.selectedLayerID = nil
                doc.activeBasicTab = 1
                doc.state.basic.temperature = wb.0
                doc.state.basic.tint = wb.1
            }
            doc.showToast("AI · \(L("白平衡校准", "White Balance")) (\(Int(wb.0)), \(Int(wb.1)))")
            done(.success(["temperature": wb.0, "tint": wb.1, "sampled_hex": c.hexString]))

        case "render_preview":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            let maxSide = (params["max_side"] as? Double).map { CGFloat($0) } ?? 1024
            let outPath = params["output_path"] as? String
            doc.renderPreviewJPEG(maxSide: maxSide) { result in
                guard let res = result else {
                    done(.failure(IPCError(code: -32002, message: "Failed to render preview"))); return
                }
                var dict: [String: Any] = [
                    "width": res.width,
                    "height": res.height,
                    "mime_type": "image/jpeg",
                    "base64": res.data.base64EncodedString()
                ]
                if let p = outPath {
                    let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
                    try? res.data.write(to: url)
                    dict["output_path"] = url.path
                }
                done(.success(dict))
            }

        case "export_photo":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            guard let outPath = params["output_path"] as? String else {
                done(.failure(IPCError(code: -32602, message: "Missing 'output_path'"))); return
            }
            let fmtStr = (params["format"] as? String ?? "jpeg").uppercased()
            let format = RenderEngine.ExportFormat(rawValue: fmtStr) ?? .jpeg
            let quality = (params["quality"] as? Double) ?? 0.92
            let maxSide = (params["max_side"] as? Double).map { CGFloat($0) }
            let url = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
            doc.exportToURL(url, format: format, quality: quality, maxSide: maxSide) { res in
                switch res {
                case .success(let u): done(.success(["output_path": u.path, "format": format.rawValue]))
                case .failure(let e): done(.failure(IPCError(code: -32002, message: e.localizedDescription)))
                }
            }

        case "export_lut":
            guard doc.hasImage else {
                done(.failure(IPCError(code: -32003, message: "No photo open"))); return
            }
            guard let outPath = params["output_path"] as? String else {
                done(.failure(IPCError(code: -32602, message: "Missing 'output_path'"))); return
            }
            let size = (params["size"] as? Int) ?? 33
            let url = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
            doc.exportLUTToURL(url, size: size) { res in
                switch res {
                case .success(let u): done(.success(["output_path": u.path, "size": size]))
                case .failure(let e): done(.failure(IPCError(code: -32002, message: e.localizedDescription)))
                }
            }

        default:
            done(.failure(IPCError(code: -32601, message: "Unknown method '\(method)'")))
        }
    }

    // MARK: - 辅助方法

    private static func basicTab(forKeys keys: [String]) -> Int? {
        for k in keys {
            switch k {
            case "exposure", "contrast", "highlights", "shadows", "whites", "blacks": return 0
            case "temperature", "tint", "vibrance", "saturation": return 1
            case "texture", "clarity", "dehaze", "sharpen", "noiseReduction": return 2
            case "vignette", "grain", "grainSize": return 3
            case "shadowTint", "redHue", "redSaturation", "greenHue", "greenSaturation", "blueHue", "blueSaturation": return 4
            default: continue
            }
        }
        return nil
    }

    private static func toDict<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    private static func mergeJSON(base: Any, patch: Any) -> Any {
        guard let bDict = base as? [String: Any], let pDict = patch as? [String: Any] else {
            return patch
        }
        var out = bDict
        for (k, v) in pDict {
            if let existing = out[k], existing is [String: Any], v is [String: Any] {
                out[k] = mergeJSON(base: existing, patch: v)
            } else {
                out[k] = v
            }
        }
        return out
    }

    /// 支持两种传入方式：直接传子结构字段（如 {"rgb": [...]}），或传带 key 的字典（如 {"curves": {"rgb": [...]}}）
    private static func decodeMergedLayerParams(base: LayerParams, kind: LayerKind, patch: [String: Any]) -> LayerParams? {
        guard var baseDict = toDict(base) else { return nil }
        let key = kind.rawValue
        let normalizedPatch: [String: Any]
        if patch[key] != nil {
            normalizedPatch = patch
        } else if baseDict[key] != nil {
            normalizedPatch = [key: patch]
        } else {
            normalizedPatch = patch
        }
        let merged = mergeJSON(base: baseDict, patch: normalizedPatch)
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let decoded = try? JSONDecoder().decode(LayerParams.self, from: data) else {
            return nil
        }
        baseDict.removeAll()
        return decoded
    }

    private static func downsample16(_ arr: [Double]) -> [Double] {
        guard arr.count >= 256 else { return arr }
        return (0..<16).map { i in
            let slice = arr[(i * 16)..<((i + 1) * 16)]
            let avg = slice.reduce(0, +) / 16.0
            return (avg * 1000).rounded() / 1000
        }
    }

    private func encodeSuccess(id: Any?, result: Any) -> Data {
        var obj: [String: Any] = ["result": result]
        if let id = id { obj["id"] = id }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{\"error\":{\"code\":-32603,\"message\":\"Encode error\"}}".utf8)
    }

    private func encodeError(id: Any?, code: Int, message: String) -> Data {
        var obj: [String: Any] = ["error": ["code": code, "message": message]]
        if let id = id { obj["id"] = id }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{\"error\":{\"code\":-32603,\"message\":\"Encode error\"}}".utf8)
    }
}
