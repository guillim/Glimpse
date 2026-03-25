import AppKit
import IOKit.ps
import SceneKit

/// Hosts a SceneKit scene and offsets the camera based on head tracking data.
final class SceneViewController: NSViewController {

    private let sceneView = SCNView()
    private(set) var headTracker = HeadTracker()
    private let cameraNode = SCNNode()

    // How many scene units the camera shifts per unit of head movement
    // at the default camera distance (20). Actual displacement is scaled
    // proportionally to currentCameraZ so close cameras don't overshoot.
    private let baseLateralScale: Float   = 4.0
    private let baseVerticalScale: Float  = 3.0
    private let baseScaleRefZ: Float      = 20.0   // reference distance for the above

    // 3D model rotation driven by head tracking
    private var modelNode: SCNNode?
    private let modelMaxRotY: Float = 15.0 * .pi / 180.0   // ±15°
    private let modelMaxRotX: Float = 10.0 * .pi / 180.0   // ±10°

    // Neutral camera position (default; overridden per-scene by SceneEntry)
    private let basePosition = SCNVector3(0, 0, 20)
    private var currentCameraX: Float = 0
    private var currentCameraY: Float = 0
    private var currentCameraZ: Float = 20

    // Render-side exponential smoothing — guarantees smooth frame-to-frame
    // transitions regardless of tracking noise.
    // tau = time constant in seconds. At 120Hz: factor ≈ 0.15, at 60Hz: ≈ 0.28.
    // Frame-rate-aware so smoothing feels identical on any display.
    private let smoothingTau: Float = 0.05   // 50ms — ~90% convergence in 150ms
    private var smoothedX: Float = 0
    private var smoothedY: Float = 0
    private var lastRenderTime: TimeInterval = 0

    // Off-axis projection parameters.
    // The virtual screen sits at z = 0 — everything behind it (negative z) appears
    // "through the window."  screenHalfH is chosen so that at the default eye
    // distance (20 units) the vertical field of view matches the previous 70°.
    private let screenZ: Float = 0
    private let fovHalfAngle: Float = 35.0 * .pi / 180.0   // 70° vertical FOV
    private let nearClip: Float  = 0.1
    private let farClip: Float   = 500.0
    private var viewAspect: Float = 16.0 / 9.0

    // MARK: - Scene switching

    struct SceneEntry {
        let id: String
        let displayName: String
        /// Per-scene neutral camera position offset.
        let cameraX: Float
        let cameraY: Float
        let cameraZ: Float
        let isSpriteKit: Bool
        fileprivate let builder: () -> SCNScene

        init(id: String, displayName: String, cameraX: Float = 0, cameraY: Float = 0, cameraZ: Float = 20, isSpriteKit: Bool = false, builder: @escaping () -> SCNScene = { SCNScene() }) {
            self.id = id
            self.displayName = displayName
            self.cameraX = cameraX
            self.cameraY = cameraY
            self.cameraZ = cameraZ
            self.isSpriteKit = isSpriteKit
            self.builder = builder
        }
    }

    /// All available scenes — 3D models auto-discovered from bundle + custom imports.
    private(set) var availableScenes: [SceneEntry] = []

    private(set) var currentSceneIndex: Int = 0

    /// Persistent directory for user-imported custom models.
    static let customModelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Glimpse/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // Holds only the active scene. Previous scene is released so its
    // decoded textures (~30-60 MB each) don't linger in RAM.
    private var currentScene: SCNScene?
    private var pokemonScene: PokemonScene?

    private func discoverScenes() {
        // Pokemon SpriteKit theme — always first
        availableScenes.append(SceneEntry(
            id: "pokemon_monitor",
            displayName: "Pokemon Monitor",
            isSpriteKit: true
        ))

        // Auto-discover 3D model files from bundle's models/ folder.
        if let modelsURL = Bundle.main.resourceURL?.appendingPathComponent("models") {
            discoverModels(in: modelsURL)
        }

        // Auto-discover user-imported custom models from Application Support.
        discoverModels(in: Self.customModelsDirectory, idPrefix: "custom_")

        // Restore last-used scene, fall back to basketball, then first scene.
        if let savedID = UserDefaults.standard.string(forKey: "selectedSceneID"),
           let idx = availableScenes.firstIndex(where: { $0.id == savedID }) {
            currentSceneIndex = idx
        } else {
            currentSceneIndex = availableScenes.firstIndex(where: { $0.id == "model_basketball" }) ?? 0
        }
    }

    /// Per-scene configuration for camera distance, model size, and placement.
    private struct SceneConfig {
        var cameraX: Float    = 0     // lateral offset of neutral camera position
        var cameraY: Float    = 0     // vertical offset of neutral camera position
        var cameraZ: Float    = 20    // camera distance from origin
        var modelSize: Float  = 12    // target bounding-box size in scene units
        var modelZ: Float     = -5    // model Z position (negative = behind window plane)
    }

    /// Overrides for specific scenes. Scenes not listed use SceneConfig defaults.
    private static let sceneConfigs: [String: SceneConfig] = [
        "model_sea": SceneConfig(
            cameraZ: 0.5,        // nearly inside the scene
            modelSize: 80,       // fill the entire viewport and beyond
            modelZ: -10          // model center closer to camera
        ),
        "model_tree": SceneConfig(
            cameraX: 3,
            cameraY: 4,
            cameraZ: 2,
            modelSize: 80,
            modelZ: -20
        ),
    ]

    private func discoverModels(in directory: URL, idPrefix: String = "model_") {
        let supportedExts: Set<String> = ["usdz", "obj", "dae", "scn"]
        guard let modelFiles = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        for fileURL in modelFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard supportedExts.contains(fileURL.pathExtension.lowercased()) else { continue }
            let name = fileURL.deletingPathExtension().lastPathComponent
            let displayName = name.prefix(1).uppercased() + name.dropFirst()
            let url = fileURL
            let sceneID = "\(idPrefix)\(name)"
            let config = Self.sceneConfigs[sceneID] ?? SceneConfig()
            availableScenes.append(SceneEntry(id: sceneID, displayName: displayName, cameraX: config.cameraX, cameraY: config.cameraY, cameraZ: config.cameraZ) { [weak self] in
                self?.makeModelScene(fileURL: url, config: config) ?? SCNScene()
            })
        }
    }

    /// Validates and imports a 3D model file into persistent storage.
    /// Returns the index of the new scene entry, or throws on failure.
    func importCustomModel(from sourceURL: URL) throws -> Int {
        let ext = sourceURL.pathExtension.lowercased()
        let supportedExts: Set<String> = ["usdz", "obj", "dae", "scn"]
        guard supportedExts.contains(ext) else {
            throw ImportError.unsupportedFormat(ext)
        }

        // Validate the file can actually be loaded as a 3D scene.
        do {
            _ = try SCNScene(url: sourceURL, options: [.checkConsistency: true])
        } catch {
            throw ImportError.invalidModel(error.localizedDescription)
        }

        let destURL = Self.customModelsDirectory.appendingPathComponent(sourceURL.lastPathComponent)

        // If a file with the same name already exists, remove it first (overwrite).
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Add the new model as a scene entry.
        let name = destURL.deletingPathExtension().lastPathComponent
        let displayName = name.prefix(1).uppercased() + name.dropFirst()
        let url = destURL
        availableScenes.append(SceneEntry(id: "custom_\(name)", displayName: displayName) { [weak self] in
            self?.makeModelScene(fileURL: url) ?? SCNScene()
        })

        return availableScenes.count - 1
    }

    enum ImportError: LocalizedError {
        case unsupportedFormat(String)
        case invalidModel(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return "Unsupported file format \".\(ext)\". Please use .usdz, .obj, .dae, or .scn."
            case .invalidModel(let reason):
                return "The file could not be loaded as a 3D model.\n\n\(reason)"
            }
        }
    }

    func cycleScene() {
        let next = (currentSceneIndex + 1) % availableScenes.count
        switchToScene(index: next)
    }

    func switchToScene(index: Int) {
        guard index < availableScenes.count else { return }
        currentSceneIndex = index

        // Persist the selection so it survives relaunch.
        UserDefaults.standard.set(availableScenes[index].id, forKey: "selectedSceneID")

        let entry = availableScenes[index]

        if entry.isSpriteKit {
            // Switching to SpriteKit theme — notify the window controller
            modelNode = nil
            currentScene = nil
            sceneView.scene = nil
            sceneView.isPlaying = false

            let pokemon = PokemonScene(size: view.bounds.size)
            pokemon.scaleMode = .resizeFill
            pokemon.headTracker = headTracker
            pokemonScene = pokemon

            // Tell the window controller to swap views
            NotificationCenter.default.post(
                name: .switchToSpriteKit,
                object: self,
                userInfo: ["scene": pokemon]
            )
        } else {
            // Switching to SceneKit theme
            pokemonScene = nil
            NotificationCenter.default.post(
                name: .switchToSceneKit,
                object: self
            )

            let scene = entry.builder()
            currentScene = scene
            currentCameraX = entry.cameraX
            currentCameraY = entry.cameraY
            currentCameraZ = entry.cameraZ
            cameraNode.position = SCNVector3(CGFloat(entry.cameraX), CGFloat(entry.cameraY), CGFloat(entry.cameraZ))
            scene.rootNode.addChildNode(cameraNode)
            sceneView.scene = scene
            updatePowerState()
        }
    }

    /// Removes a custom model from disk and the scene list. Returns true if removed.
    func deleteCustomModel(at index: Int) -> Bool {
        guard index < availableScenes.count else { return false }
        let entry = availableScenes[index]
        guard entry.id.hasPrefix("custom_") else { return false }

        // Delete the file from Application Support.
        let name = String(entry.id.dropFirst("custom_".count))
        let supportedExts = ["usdz", "obj", "dae", "scn"]
        for ext in supportedExts {
            let url = Self.customModelsDirectory.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
                break
            }
        }

        availableScenes.remove(at: index)

        // If we deleted the active scene, switch to the first available.
        if currentSceneIndex == index {
            switchToScene(index: 0)
        } else if currentSceneIndex > index {
            currentSceneIndex -= 1
        }

        return true
    }

    // MARK: - View lifecycle

    override func loadView() {
        self.view = sceneView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupPowerSourceMonitoring()
        setupHeadTracking()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let b = view.bounds
        if b.height > 0 { viewAspect = Float(b.width / b.height) }
    }

    // MARK: - Scene setup

    private func setupScene() {
        discoverScenes()

        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling2X
        sceneView.preferredFramesPerSecond = 0   // uncapped — matches display refresh (120 Hz+)
        sceneView.rendersContinuously = true
        sceneView.delegate = self

        // Camera — projection is set per-frame via off-axis frustum in updateCamera()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = Double(nearClip)
        cameraNode.camera?.zFar  = Double(farClip)
        cameraNode.position = basePosition

        switchToScene(index: currentSceneIndex)
    }

    /// 3D model scene — loads an external model file, centers and scales it,
    /// and rotates it per-frame based on head tracking.
    private func makeModelScene(fileURL: URL, config: SceneConfig = SceneConfig()) -> SCNScene {
        let loaded: SCNScene
        do {
            loaded = try SCNScene(url: fileURL, options: [.checkConsistency: true])
        } catch {
            print("Warning: failed to load model \(fileURL.path): \(error)")
            return SCNScene()
        }

        // Gather all content nodes into a single container for bounding-box calculation.
        let content = SCNNode()
        for child in loaded.rootNode.childNodes {
            child.removeFromParentNode()
            content.addChildNode(child)
        }

        // Center the model at the origin and scale it to fit within a target size.
        let (minB, maxB) = content.boundingBox
        let center = SCNVector3(
            (minB.x + maxB.x) / 2,
            (minB.y + maxB.y) / 2,
            (minB.z + maxB.z) / 2
        )
        let maxExtent = max(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
        let scale = maxExtent > 0 ? config.modelSize / Float(maxExtent) : 1.0

        content.position = SCNVector3(-center.x, -center.y, -center.z)

        let wrapper = SCNNode()
        wrapper.addChildNode(content)
        wrapper.scale = SCNVector3(scale, scale, scale)
        wrapper.position = SCNVector3(0, 0, config.modelZ)

        let scene = SCNScene()
        scene.rootNode.addChildNode(wrapper)
        modelNode = wrapper

        // Three-point lighting for good model readability
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        ambient.light?.color = NSColor(calibratedWhite: 0.8, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 800
        key.light?.color = NSColor.white
        key.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 300
        fill.light?.color = NSColor(calibratedWhite: 0.9, alpha: 1)
        fill.eulerAngles = SCNVector3(Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fill)

        return scene
    }

    // MARK: - Power Management

    private var isOccluded = false
    private var isSystemSuspended = false
    private var isOnBattery = false
    private var powerSource: Any?

    private var shouldRun: Bool { !isOccluded && !isSystemSuspended }

    /// Called by DesktopWindowController when the window's occlusion state changes.
    func setOccluded(_ occluded: Bool) {
        isOccluded = occluded
        updatePowerState()
    }

    /// Called by AppDelegate on system sleep, wake, screensaver start/stop.
    func setSystemSuspended(_ suspended: Bool) {
        isSystemSuspended = suspended
        updatePowerState()
    }

    private func setupPowerSourceMonitoring() {
        isOnBattery = !Self.isPluggedIn()

        let context = Unmanaged.passUnretained(self).toOpaque()
        let loop = IOPSNotificationCreateRunLoopSource({ context in
            guard let ctx = context else { return }
            let vc = Unmanaged<SceneViewController>.fromOpaque(ctx).takeUnretainedValue()
            vc.isOnBattery = !SceneViewController.isPluggedIn()
            vc.updatePowerState()
        }, context).takeRetainedValue()

        CFRunLoopAddSource(CFRunLoopGetMain(), loop, .defaultMode)
        powerSource = loop
    }

    private static func isPluggedIn() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty else {
            // Desktop Mac or can't determine — assume plugged in.
            return true
        }
        // Check if any source is charging or on AC.
        for src in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, src as CFTypeRef)?.takeUnretainedValue() as? [String: Any],
               let state = desc[kIOPSPowerSourceStateKey] as? String {
                if state == kIOPSACPowerValue { return true }
            }
        }
        return false
    }

    private static let batteryFPS = 30

    private func updatePowerState() {
        if shouldRun {
            headTracker.start()
            sceneView.isPlaying = true
            // Throttle frame rate on battery to save energy.
            sceneView.preferredFramesPerSecond = isOnBattery ? Self.batteryFPS : 0
        } else {
            sceneView.isPlaying = false
            headTracker.stop()
        }
    }

    // MARK: - Head Tracking

    private func setupHeadTracking() {
        updatePowerState()
    }

    fileprivate func updateCamera(offset: HeadTracker.HeadOffset, time: TimeInterval) {
        // Frame-rate-aware EMA: compute smoothing factor from elapsed time and
        // a fixed time constant (tau). This produces identical smoothing behaviour
        // whether the display runs at 60 Hz, 120 Hz, or anything in between.
        let dt = Float(lastRenderTime > 0 ? time - lastRenderTime : 1.0 / 120.0)
        lastRenderTime = time
        let alpha = 1.0 - exp(-dt / smoothingTau)

        smoothedX += (offset.x - smoothedX) * alpha
        smoothedY += (offset.y - smoothedY) * alpha

        // Scale lateral/vertical movement proportionally to camera distance.
        // At cameraZ=20 (default), movement matches the base scales.
        // At cameraZ=0.5 (sea), movement is 40x smaller — preventing overshoot.
        let distanceFactor = currentCameraZ / baseScaleRefZ
        let eyeX = currentCameraX + smoothedX * baseLateralScale * distanceFactor
        let eyeY = currentCameraY + smoothedY * baseVerticalScale * distanceFactor
        let eyeZ = currentCameraZ

        // Disable implicit SceneKit animation — we set final values directly
        // each frame via the EMA. Any implicit animation would add latency.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true

        cameraNode.position = SCNVector3(CGFloat(eyeX), CGFloat(eyeY), CGFloat(eyeZ))

        // Off-axis projection: compute the virtual screen size from the current
        // camera distance so the FOV stays consistent (~70°) regardless of how
        // close or far the per-scene cameraZ places us.
        let dist = eyeZ - screenZ
        guard dist > nearClip else {
            SCNTransaction.commit()
            return
        }

        let screenHalfH = dist * tan(fovHalfAngle)
        let halfW = screenHalfH * viewAspect
        let s     = nearClip / dist

        cameraNode.camera?.projectionTransform = Self.offAxisProjection(
            left:   (-halfW      - eyeX) * s,
            right:  ( halfW      - eyeX) * s,
            bottom: (-screenHalfH - eyeY) * s,
            top:    ( screenHalfH - eyeY) * s,
            near:   nearClip,
            far:    farClip
        )

        // Rotate 3D model opposite to head movement so it reveals its far side —
        // head moves left → object turns right, head moves up → object tilts down.
        // Power curve (exp 1.5) amplifies rotation at extremes while keeping center subtle.
        if let model = modelNode {
            let curvedX = copysign(pow(abs(smoothedX), 1.5), smoothedX)
            let curvedY = copysign(pow(abs(smoothedY), 1.5), smoothedY)
            model.eulerAngles = SCNVector3(
                curvedY * modelMaxRotX,
               -curvedX * modelMaxRotY,
                0
            )
        }

        SCNTransaction.commit()
    }

    /// Builds an off-center perspective projection matrix (OpenGL convention).
    private static func offAxisProjection(left l: Float, right r: Float,
                                          bottom b: Float, top t: Float,
                                          near n: Float, far f: Float) -> SCNMatrix4 {
        let rl = r - l, tb = t - b, fn = f - n
        return SCNMatrix4(
            m11: CGFloat(2 * n / rl), m12: 0,                    m13: 0,                       m14: 0,
            m21: 0,                   m22: CGFloat(2 * n / tb),   m23: 0,                       m24: 0,
            m31: CGFloat((r+l)/rl),   m32: CGFloat((t+b)/tb),     m33: CGFloat(-(f+n)/fn),       m34: -1,
            m41: 0,                   m42: 0,                    m43: CGFloat(-2 * f * n / fn), m44: 0
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let switchToSpriteKit = Notification.Name("Glimpse.switchToSpriteKit")
    static let switchToSceneKit  = Notification.Name("Glimpse.switchToSceneKit")
}

// MARK: - SCNSceneRendererDelegate

extension SceneViewController: SCNSceneRendererDelegate {
    /// Called by SceneKit once per frame, right before rendering.
    /// Pulling the latest head offset here instead of via async dispatch
    /// ensures every frame uses the freshest available data with zero scheduling jitter.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        updateCamera(offset: headTracker.predictedOffset(atTime: time), time: time)
    }
}
