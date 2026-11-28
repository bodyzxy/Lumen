import Foundation
import Darwin

// MARK: - IPC Client (Unix Domain Socket -> Lumen.app)

enum IPCError: Error, LocalizedError {
    case appNotRunning
    case connectionFailed(String)
    case invalidResponse
    case remoteError(String)

    var errorDescription: String? {
        switch self {
        case .appNotRunning: return "Could not launch or connect to Lumen.app"
        case .connectionFailed(let msg): return "IPC connection failed: \(msg)"
        case .invalidResponse: return "Invalid response from Lumen.app"
        case .remoteError(let msg): return msg
        }
    }
}

final class IPCClient {
    static let shared = IPCClient()

    private var socketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lumen/lumen.sock").path
    }

    func call(method: String, params: [String: Any] = [:]) throws -> [String: Any] {
        try ensureLumenRunning()

        let fd = try connectSocket()
        defer { close(fd) }

        let req: [String: Any] = [
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]
        var reqData = try JSONSerialization.data(withJSONObject: req)
        reqData.append(0x0A)
        try writeAll(fd: fd, data: reqData)

        let respData = try readLine(fd: fd)
        guard let obj = try JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            throw IPCError.invalidResponse
        }
        if let err = obj["error"] as? [String: Any] {
            let msg = err["message"] as? String ?? "Unknown Lumen error"
            throw IPCError.remoteError(msg)
        }
        if let res = obj["result"] as? [String: Any] {
            return res
        }
        return [:]
    }

    private func connectSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCError.connectionFailed(String(cString: strerror(errno)))
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8CString)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count <= maxLen else {
            close(fd)
            throw IPCError.connectionFailed("Socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            for (i, b) in bytes.enumerated() { ptr[i] = b }
        }

        let res = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if res != 0 {
            let errStr = String(cString: strerror(errno))
            close(fd)
            throw IPCError.connectionFailed(errStr)
        }
        return fd
    }

    private func ensureLumenRunning() throws {
        if let fd = try? connectSocket() {
            close(fd)
            return
        }

        // Launch Lumen
        let fm = FileManager.default
        let selfURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let siblingLumen = selfURL.deletingLastPathComponent().appendingPathComponent("Lumen")

        if fm.isExecutableFile(atPath: siblingLumen.path) {
            let proc = Process()
            proc.executableURL = siblingLumen
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
        } else if fm.fileExists(atPath: "/Applications/Lumen.app") {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["/Applications/Lumen.app"]
            try? proc.run()
        } else {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Lumen"]
            try? proc.run()
        }

        // Poll up to 10 seconds for socket
        let deadline = Date().addingTimeInterval(10.0)
        while Date() < deadline {
            if let fd = try? connectSocket() {
                close(fd)
                return
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        throw IPCError.appNotRunning
    }

    private func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = write(fd, base.advanced(by: sent), data.count - sent)
                if n <= 0 {
                    throw IPCError.connectionFailed("Write failed")
                }
                sent += n
            }
        }
    }

    private func readLine(fd: Int32) throws -> Data {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n < 0 {
                if errno == EINTR { continue }
                throw IPCError.connectionFailed("Read failed")
            }
            if n == 0 { break }
            buffer.append(chunk, count: n)
            if let nl = buffer.firstIndex(of: 0x0A) {
                return buffer.subdata(in: 0..<nl)
            }
        }
        if buffer.isEmpty { throw IPCError.invalidResponse }
        return buffer
    }
}

// MARK: - MCP Schemas & Definitions

enum MCPCatalog {
    static let tools: [[String: Any]] = [
        tool(
            name: "open_photos",
            description: "Open one or more photos in the live Lumen window (plays the Develop animation and adds them to the filmstrip).",
            properties: [
                "paths": ["type": "array", "items": ["type": "string"], "description": "Absolute file paths to photos (JPEG, PNG, HEIC, TIFF, or camera RAW)."]
            ],
            required: ["paths"]
        ),
        tool(
            name: "list_sessions",
            description: "List all photos currently open in Lumen's filmstrip, including their session IDs, dimensions, and edited status.",
            properties: [:],
            required: []
        ),
        tool(
            name: "switch_session",
            description: "Switch the active photo in Lumen's canvas (plays the filmstrip morph transition).",
            properties: [
                "session_id": ["type": "string", "description": "UUID of the session from list_sessions or open_photos."]
            ],
            required: ["session_id"]
        ),
        tool(
            name: "close_session",
            description: "Close a photo session in Lumen.",
            properties: [
                "session_id": ["type": "string", "description": "Optional session UUID. Defaults to the currently active photo."]
            ],
            required: []
        ),
        tool(
            name: "get_edit_state",
            description: "Get the complete EditState JSON (basic settings + all adjustment layers) for the active photo.",
            properties: [:],
            required: []
        ),
        tool(
            name: "set_basic_adjustments",
            description: "Partially update BasicSettings in Lumen with live UI animation and auto-switching to the corresponding Inspector tab (Light/Color/Texture/Effects/Calibrate). IMPORTANT: Inspect the photo first via render_preview + get_image_analysis before choosing values; never guess blind preset numbers.",
            properties: [
                "params": [
                    "type": "object",
                    "description": "Subset of BasicSettings: exposure (-5..5), contrast (-100..100), highlights (-100..100), shadows (-100..100), whites (-100..100), blacks (-100..100), temperature (-100..100), tint (-100..100), vibrance (-100..100), saturation (-100..100), texture (-100..100), clarity (-100..100), dehaze (-100..100), sharpen (0..100), noiseReduction (0..100), vignette (-100..100), grain (0..100), grainSize (0..100), shadowTint (-100..100), redHue/redSaturation/greenHue/greenSaturation/blueHue/blueSaturation (-100..100)."
                ],
                "reset_others": ["type": "boolean", "description": "If true, resets all other basic fields to default before applying params."]
            ],
            required: ["params"]
        ),
        tool(
            name: "reset_adjustments",
            description: "Reset basic adjustments or all adjustments (including layers) on the active photo.",
            properties: [
                "scope": ["type": "string", "enum": ["basic", "all"], "description": "Whether to reset only 'basic' or 'all'."]
            ],
            required: ["scope"]
        ),
        tool(
            name: "add_layer",
            description: "Add an adjustment layer to the active photo and select it in the UI. Read resource lumen://schema/edit-state for exact parameter structures.",
            properties: [
                "kind": [
                    "type": "string",
                    "enum": [
                        "brightnessContrast", "levels", "curves", "exposure",
                        "vibrance", "hueSaturation", "colorBalance", "blackWhite", "photoFilter", "channelMixer", "lut",
                        "invert", "posterize", "threshold", "gradientMap", "selectiveColor",
                        "shadowsHighlights", "hdrToning",
                        "desaturate", "matchColor", "replaceColor", "equalize",
                        "hsl", "colorGrading"
                    ],
                    "description": "Type of adjustment layer."
                ],
                "name": ["type": "string", "description": "Optional custom layer name."],
                "opacity": ["type": "number", "description": "Layer opacity 0...100 (default 100)."],
                "visible": ["type": "boolean", "description": "Layer visibility (default true)."],
                "blend_mode": [
                    "type": "string",
                    "enum": ["normal", "multiply", "screen", "overlay", "softLight", "hardLight", "colorDodge", "colorBurn", "darken", "lighten", "color", "luminosity"],
                    "description": "Layer blend mode (default normal)."
                ],
                "params": ["type": "object", "description": "Layer-specific parameter fields (e.g. curves: {rgb: [{x:0,y:0.06},{x:1,y:0.96}]}, hsl: {hue: [...], saturation: [...], luminance: [...]}, colorGrading: {shadows: {hue:200,saturation:20,luminance:0}, ...})."],
                "index": ["type": "integer", "description": "Optional stack index (0 = bottom)."]
            ],
            required: ["kind"]
        ),
        tool(
            name: "update_layer",
            description: "Update an existing adjustment layer's visibility, opacity, blend mode, name, or parameters in the live UI.",
            properties: [
                "layer_id": ["type": "string", "description": "UUID of the layer."],
                "name": ["type": "string"],
                "visible": ["type": "boolean"],
                "opacity": ["type": "number"],
                "blend_mode": [
                    "type": "string",
                    "enum": ["normal", "multiply", "screen", "overlay", "softLight", "hardLight", "colorDodge", "colorBurn", "darken", "lighten", "color", "luminosity"]
                ],
                "params": ["type": "object", "description": "Partial parameter patch for this layer."]
            ],
            required: ["layer_id"]
        ),
        tool(
            name: "layer_action",
            description: "Delete, duplicate, reorder, or select an existing adjustment layer.",
            properties: [
                "layer_id": ["type": "string", "description": "UUID of the layer."],
                "action": ["type": "string", "enum": ["delete", "duplicate", "move_up", "move_down", "select"]]
            ],
            required: ["layer_id", "action"]
        ),
        tool(
            name: "apply_preset",
            description: "Apply a built-in look (plays the Light Sweep animation across the photo) or load a JSON preset file. Analyze the photo first via render_preview + get_image_analysis, and fine-tune exposure/WB/shadows afterwards.",
            properties: [
                "preset_key": [
                    "type": "string",
                    "enum": ["warmFilm", "japaneseFresh", "tealOrange", "contrastBW", "fadedVintage", "moodyNight"],
                    "description": "Built-in preset identifier."
                ],
                "preset_path": ["type": "string", "description": "Path to a saved Lumen JSON preset file."]
            ],
            required: []
        ),
        tool(
            name: "sync_adjustments",
            description: "Copy identical adjustments from the active photo to other open photos. WARNING: For multiple photos with different lighting or scenes, DO NOT blindly sync; instead switch_session and analyze + grade each photo one by one. Only use sync_adjustments when the user explicitly requests identical batch copying (e.g. matching burst shots).",
            properties: [
                "target_session_ids": ["type": "array", "items": ["type": "string"], "description": "Optional list of target session UUIDs. Omit to sync to all open photos."]
            ],
            required: []
        ),
        tool(
            name: "undo",
            description: "Undo the last edit on the active photo.",
            properties: [:],
            required: []
        ),
        tool(
            name: "redo",
            description: "Redo the last undone edit on the active photo.",
            properties: [:],
            required: []
        ),
        tool(
            name: "set_view",
            description: "Control Lumen's canvas view: toggle split-view comparison, show original wipe, zoom, or inspector visibility.",
            properties: [
                "compare_mode": ["type": "string", "enum": ["off", "split"]],
                "split_position": ["type": "number", "description": "Split divider position 0.02...0.98."],
                "show_original": ["type": "boolean", "description": "Hold/show original photo with wipe transition."],
                "zoom": ["type": "string", "description": "'fit', '100%', or numeric zoom factor."],
                "show_inspector": ["type": "boolean"]
            ],
            required: []
        ),
        tool(
            name: "get_image_analysis",
            description: "Analyze tonal & color distribution of the active photo: returns 16-bin Luma + Red/Green/Blue histograms, shadows/midtones/highlights zone breakdown (ratio, mean_luma, mean_rgb), near_black_ratio (shadow detail), near_white_ratio, contrast_spread (p05..p95), color_cast_hint, clipping ratios, and YCbCr stats.",
            properties: [
                "source": ["type": "string", "enum": ["preview", "original"], "description": "Analyze edited 'preview' (default) or unedited 'original'."]
            ],
            required: []
        ),
        tool(
            name: "sample_color",
            description: "Sample a 5x5 average RGB/Hex color at normalized coordinates (0..1, top-left origin) on the active photo.",
            properties: [
                "x": ["type": "number", "description": "Normalized X (0...1)."],
                "y": ["type": "number", "description": "Normalized Y (0...1)."],
                "source": ["type": "string", "enum": ["preview", "original"], "description": "Sample edited preview or original image."]
            ],
            required: ["x", "y"]
        ),
        tool(
            name: "auto_white_balance",
            description: "Neutralize white balance by sampling a neutral gray/white point at normalized coordinates (0..1).",
            properties: [
                "x": ["type": "number", "description": "Normalized X (0...1)."],
                "y": ["type": "number", "description": "Normalized Y (0...1)."]
            ],
            required: ["x", "y"]
        ),
        tool(
            name: "render_preview",
            description: "Render the current edited photo as a JPEG image so you can visually inspect the result.",
            properties: [
                "max_side": ["type": "number", "description": "Maximum long edge in pixels (default 1024)."],
                "output_path": ["type": "string", "description": "Optional file path to also save the preview JPEG."]
            ],
            required: []
        ),
        tool(
            name: "export_photo",
            description: "Export the active photo at full resolution (or specified max_side) to JPEG, HEIC, PNG, or 16-bit TIFF.",
            properties: [
                "output_path": ["type": "string", "description": "Destination file path."],
                "format": ["type": "string", "enum": ["jpeg", "heic", "png", "tiff"], "description": "Export format (default jpeg)."],
                "quality": ["type": "number", "description": "Compression quality 0.5...1.0 for JPEG/HEIC (default 0.92)."],
                "max_side": ["type": "number", "description": "Optional max long edge in pixels; omit for original full size."]
            ],
            required: ["output_path"]
        ),
        tool(
            name: "set_crop",
            description: "Crop, rotate (90° turns), flip, or straighten the active photo using normalized coordinates (0..1, top-left origin).",
            properties: [
                "x": ["type": "number", "description": "Normalized left edge (0...1)."],
                "y": ["type": "number", "description": "Normalized top edge (0...1)."],
                "width": ["type": "number", "description": "Normalized width (0.05...1)."],
                "height": ["type": "number", "description": "Normalized height (0.05...1)."],
                "straighten": ["type": "number", "description": "Straighten angle in degrees (-45...45)."],
                "quarter_turns": ["type": "integer", "description": "90-degree clockwise turns (0..3)."],
                "flip_h": ["type": "boolean"],
                "flip_v": ["type": "boolean"],
                "reset": ["type": "boolean", "description": "Reset crop & transform to original."]
            ],
            required: []
        ),
        tool(
            name: "batch_export",
            description: "Batch export all open photos in the filmstrip to a destination directory.",
            properties: [
                "output_dir": ["type": "string", "description": "Destination directory path."],
                "format": ["type": "string", "enum": ["jpeg", "heic", "png", "tiff"], "description": "Export format (default jpeg)."],
                "quality": ["type": "number", "description": "Compression quality 0.5...1.0 (default 0.92)."],
                "max_side": ["type": "number", "description": "Optional max long edge in pixels; omit for original full size."]
            ],
            required: ["output_dir"]
        ),
        tool(
            name: "export_lut",
            description: "Bake and export the color & tone pipeline of the active photo as a .cube 3D LUT file.",
            properties: [
                "output_path": ["type": "string", "description": "Destination .cube file path."],
                "size": ["type": "integer", "description": "LUT cube dimension (default 33)."]
            ],
            required: ["output_path"]
        )
    ]

    static let resources: [[String: Any]] = [
        [
            "uri": "lumen://schema/edit-state",
            "name": "Lumen EditState & Layer Schema",
            "description": "Complete schema and value ranges for BasicSettings and all 24 AdjustmentLayer kinds.",
            "mimeType": "text/markdown"
        ],
        [
            "uri": "lumen://presets/builtin",
            "name": "Lumen Built-in Presets",
            "description": "Descriptions of Lumen's 6 built-in looks.",
            "mimeType": "application/json"
        ]
    ]

    static let prompts: [[String: Any]] = [
        [
            "name": "auto-color-grade",
            "description": "Standard closed-loop workflow for visually analyzing and color-grading a photo in Lumen.",
            "arguments": [
                ["name": "goal", "description": "Desired look or style (e.g. 'warm film', 'clean portrait', 'moody night').", "required": false]
            ]
        ]
    ]

    static func readResource(uri: String) -> String? {
        switch uri {
        case "lumen://schema/edit-state":
            return """
            # Lumen EditState Schema

            ## 1. BasicSettings (`set_basic_adjustments`)
            - **Light (tab 0)**: `exposure` (-5..5 EV), `contrast` (-100..100), `highlights` (-100..100), `shadows` (-100..100), `whites` (-100..100), `blacks` (-100..100)
            - **Color (tab 1)**: `temperature` (-100..100), `tint` (-100..100), `vibrance` (-100..100), `saturation` (-100..100)
            - **Texture (tab 2)**: `texture` (-100..100), `clarity` (-100..100), `dehaze` (-100..100), `sharpen` (0..100), `noiseReduction` (0..100)
            - **Effects (tab 3)**: `vignette` (-100..100), `grain` (0..100), `grainSize` (0..100, default 25)
            - **Calibrate (tab 4)**: `shadowTint` (-100..100), `redHue`, `redSaturation`, `greenHue`, `greenSaturation`, `blueHue`, `blueSaturation` (-100..100)

            ## 2. AdjustmentLayer `params` by `kind`
            - `brightnessContrast`: `{ "brightness": -150..150, "contrast": -50..100 }`
            - `levels`: `{ "master"|"red"|"green"|"blue": { "inBlack": 0..255, "inWhite": 0..255, "gamma": 0.1..3, "outBlack": 0..255, "outWhite": 0..255 } }`
            - `curves`: `{ "rgb"|"red"|"green"|"blue": [{"x": 0..1, "y": 0..1}, ...] }`
            - `exposure`: `{ "exposure": -5..5, "offset": -0.5..0.5, "gamma": 0.1..3 }`
            - `vibrance`: `{ "vibrance": -100..100, "saturation": -100..100 }`
            - `hueSaturation`: `{ "hue": -180..180, "saturation": -100..100, "lightness": -100..100, "colorize": bool, "colorizeHue": 0..360, "colorizeSaturation": 0..100 }`
            - `hsl`: `{ "hue": [8 doubles], "saturation": [8 doubles], "luminance": [8 doubles] }` (8 bands: Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta; each -100..100)
            - `colorBalance`: `{ "shadows": [3], "midtones": [3], "highlights": [3], "preserveLuminosity": bool }` ([Cyan-Red, Magenta-Green, Yellow-Blue], -100..100)
            - `colorGrading`: `{ "shadows"|"midtones"|"highlights"|"global": { "hue": 0..360, "saturation": 0..100, "luminance": -100..100 }, "blending": 0..100, "balance": -100..100 }`
            - `blackWhite`: `{ "weights": [6 doubles in -200..300], "tint": bool, "tintHue": 0..360, "tintSaturation": 0..100 }`
            - `photoFilter`: `{ "color": {"r":0..1,"g":0..1,"b":0..1}, "density": 0..100, "preserveLuminosity": bool }`
            - `channelMixer`: `{ "red"|"green"|"blue"|"gray": [R, G, B, Constant in -200..200], "monochrome": bool }`
            - `lut`: `{ "path": "/path/to/file.cube", "intensity": 0..100 }`
            - `selectiveColor`: `{ "groups": [[C,M,Y,K] x 9], "relative": bool }`
            - `gradientMap`: `{ "stops": [{"position":0..1,"color":{"r":0..1,"g":0..1,"b":0..1}}], "reverse": bool }`
            - `posterize`: `{ "levels": 2..32 }`
            - `threshold`: `{ "level": 1..255 }`
            - `shadowsHighlights`: `{ "shadowsAmount": 0..100, "shadowsRadius": 1..100, "highlightsAmount": 0..100, "highlightsRadius": 1..100, "colorCorrection": -100..100, "midtoneContrast": -100..100 }`
            - `hdrToning`: `{ "radius": 1..100, "strength": 0..100, "gamma": 0.2..2.5, "exposure": -3..3, "detail": -100..200, "vibrance": -100..100, "saturation": -100..100 }`
            - `replaceColor`: `{ "target": {"r":0..1,"g":0..1,"b":0..1}, "fuzziness": 0..200, "hue": -180..180, "saturation": -100..100, "lightness": -100..100 }`
            - `invert`, `desaturate`, `equalize`: no required params.
            """
        case "lumen://presets/builtin":
            return """
            [
              {"key": "warmFilm", "name": "Warm Film", "description": "Faded blacks, warm highlights, light grain"},
              {"key": "japaneseFresh", "name": "Airy Japanese", "description": "High-key, low contrast, cool teal"},
              {"key": "tealOrange", "name": "Teal & Orange", "description": "Teal shadows, orange highlights"},
              {"key": "contrastBW", "name": "Contrasty Mono", "description": "Red-filter look with darkened sky"},
              {"key": "fadedVintage", "name": "Faded Vintage", "description": "Gray blacks, yellowed, coarse grain"},
              {"key": "moodyNight", "name": "City Night", "description": "Cool shadows, warm lights"}
            ]
            """
        default:
            return nil
        }
    }

    private static func tool(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        ]
    }
}

// MARK: - Stdio JSON-RPC 2.0 Server

final class MCPServer {
    private let stdout = FileHandle.standardOutput
    private let stderr = FileHandle.standardError

    func run() {
        signal(SIGPIPE, SIG_IGN)
        let stdin = FileHandle.standardInput
        var buffer = Data()

        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                let trimmed = line.filter { $0 != 0x0D }
                if trimmed.isEmpty { continue }
                handleLine(Data(trimmed))
            }
        }
    }

    private func handleLine(_ data: Data) {
        guard let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = req["method"] as? String else {
            return
        }
        let id = req["id"]
        let params = req["params"] as? [String: Any] ?? [:]

        // Notifications have no id
        if id == nil {
            return
        }

        do {
            let result = try dispatch(method: method, params: params)
            send(["jsonrpc": "2.0", "id": id!, "result": result])
        } catch {
            send([
                "jsonrpc": "2.0",
                "id": id!,
                "error": [
                    "code": -32000,
                    "message": error.localizedDescription
                ]
            ])
        }
    }

    private func dispatch(method: String, params: [String: Any]) throws -> [String: Any] {
        switch method {
        case "initialize":
            return [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": ["listChanged": false],
                    "resources": ["subscribe": false, "listChanged": false],
                    "prompts": ["listChanged": false]
                ],
                "serverInfo": [
                    "name": "LumenMCP",
                    "version": "1.0.0"
                ],
                "instructions": """
                Lumen MCP Editing Protocol:
                1. UNDERSTAND BEFORE EDITING: Never blindly apply static parameters or presets. Always inspect the active photo first with BOTH `render_preview` (visual composition, subject, lighting, mood) AND `get_image_analysis` (RGB histograms, shadow/midtone/highlight zones, near_black_ratio, color_cast_hint, contrast_spread). Summarize what you observe before adjusting.
                2. SEQUENTIAL PER-PHOTO WORKFLOW: When multiple photos are open (`list_sessions`), process ONE photo at a time (`switch_session` -> inspect -> tailor edits -> verify -> next photo). Do NOT call `sync_adjustments` across photos with different lighting/scenes unless the user explicitly asks to copy identical settings.
                3. VERIFY & PROTECT DETAIL: After editing, call `render_preview` and `get_image_analysis` again to verify shadow detail (avoid unintended crushed blacks), highlight headroom, and overall color harmony.
                """
            ]

        case "ping":
            return [:]

        case "tools/list":
            return ["tools": MCPCatalog.tools]

        case "tools/call":
            guard let name = params["name"] as? String else {
                throw IPCError.remoteError("Missing tool name")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            return executeTool(name: name, args: args)

        case "resources/list":
            return ["resources": MCPCatalog.resources]

        case "resources/read":
            guard let uri = params["uri"] as? String,
                  let text = MCPCatalog.readResource(uri: uri) else {
                throw IPCError.remoteError("Resource not found")
            }
            return [
                "contents": [
                    [
                        "uri": uri,
                        "mimeType": uri.hasSuffix("builtin") ? "application/json" : "text/markdown",
                        "text": text
                    ]
                ]
            ]

        case "prompts/list":
            return ["prompts": MCPCatalog.prompts]

        case "prompts/get":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            let goal = args["goal"] as? String ?? "balanced, natural color grade"
            guard name == "auto-color-grade" else {
                throw IPCError.remoteError("Unknown prompt")
            }
            return [
                "description": "Closed-loop color grading workflow in Lumen",
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            "type": "text",
                            "text": """
                            Edit the photo in Lumen with goal: \(goal).
                            Follow these steps so the user can watch every adjustment live in Lumen.app:
                            1. Ensure photos are open (`list_sessions` or `open_photos`). If multiple photos are open, process them ONE BY ONE (`switch_session` -> understand -> grade -> verify -> next photo); never blindly `sync_adjustments` across different scenes.
                            2. Inspect the active photo with BOTH `get_image_analysis` (RGB histograms, shadow/midtone/highlight zones, `near_black_ratio`, `color_cast_hint`) and `render_preview`. Briefly diagnose its lighting, shadows, highlights, and RGB balance before touching sliders.
                            3. Fix exposure, contrast, white balance, and shadow/highlight detail via `set_basic_adjustments`.
                            4. Add stylistic layers (`curves`, `hsl`, `colorGrading`, etc.) via `add_layer`.
                            5. Call `render_preview` and `get_image_analysis` again to verify shadow detail is preserved and there is no unwanted highlight/shadow clipping.
                            6. Optionally call `set_view(compare_mode: "split")` so the user can compare before & after.
                            """
                        ]
                    ]
                ]
            ]

        default:
            throw IPCError.remoteError("Method not supported: \(method)")
        }
    }

    private func executeTool(name: String, args: [String: Any]) -> [String: Any] {
        do {
            let res = try IPCClient.shared.call(method: name, params: args)

            if name == "render_preview",
               let base64 = res["base64"] as? String,
               let mime = res["mime_type"] as? String {
                var meta = res
                meta.removeValue(forKey: "base64")
                let metaText = jsonString(meta)
                return [
                    "content": [
                        ["type": "image", "data": base64, "mimeType": mime],
                        ["type": "text", "text": metaText]
                    ],
                    "isError": false
                ]
            }

            return [
                "content": [
                    ["type": "text", "text": jsonString(res)]
                ],
                "isError": false
            ]
        } catch {
            return [
                "content": [
                    ["type": "text", "text": "Error: \(error.localizedDescription)"]
                ],
                "isError": true
            ]
        }
    }

    private func jsonString(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    private func send(_ obj: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        data.append(0x0A)
        stdout.write(data)
    }
}

MCPServer().run()
