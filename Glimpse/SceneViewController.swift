import AppKit
import SceneKit

/// Hosts a SceneKit scene and offsets the camera based on head tracking data.
final class SceneViewController: NSViewController {

    private let sceneView = SCNView()
    private let headTracker = HeadTracker()
    private let cameraNode = SCNNode()

    // How many scene units the camera shifts per unit of head movement
    private let lateralScale: Float   = 4.0
    private let verticalScale: Float  = 3.0
    private let depthScale: Float     = 2.0

    // 3D model rotation driven by head tracking
    private var modelNode: SCNNode?
    private var modelBaseScale: Float = 1.0
    private let modelMaxRotY: Float = 15.0 * .pi / 180.0   // ±15°
    private let modelMaxRotX: Float = 10.0 * .pi / 180.0   // ±10°

    // Neutral camera position
    private let basePosition = SCNVector3(0, 0, 20)

    // Off-axis projection parameters.
    // The virtual screen sits at z = 0 — everything behind it (negative z) appears
    // "through the window."  screenHalfH is chosen so that at the default eye
    // distance (20 units) the vertical field of view matches the previous 70°.
    private let screenZ: Float = 0
    private let screenHalfH: Float = 20.0 * tan(35.0 * .pi / 180.0)   // ≈ 14.0
    private let nearClip: Float  = 1.0
    private let farClip: Float   = 500.0
    private var viewAspect: Float = 16.0 / 9.0

    // MARK: - Scene switching

    struct SceneEntry {
        let id: String
        let displayName: String
        fileprivate let builder: () -> SCNScene
    }

    /// All available scenes — procedural (hardcoded) + parallax (auto-discovered from bundle).
    private(set) var availableScenes: [SceneEntry] = []

    private var currentIndex: Int = 0

    // Holds only the active scene. Previous scene is released so its
    // decoded textures (~30-60 MB each) don't linger in RAM.
    private var currentScene: SCNScene?

    private func discoverScenes() {
        // Auto-discover parallax scenes from bundle's layers/ folder.
        // Convention: layers/{SceneName}/ contains {basename}_layer_01_*.png files.
        guard let layersURL = Bundle.main.resourceURL?.appendingPathComponent("layers") else { return }
        guard let sceneDirs = try? FileManager.default.contentsOfDirectory(
            at: layersURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return }

        for dirURL in sceneDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? dirURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dirURL.path)) ?? []

            // Find the base name from the first _layer_01_ file
            guard let marker = files.first(where: { $0.contains("_layer_01_") && $0.hasSuffix(".png") }),
                  let range = marker.range(of: "_layer_01_") else { continue }
            let baseName = String(marker[..<range.lowerBound])
            let displayName = dirURL.lastPathComponent.prefix(1).uppercased() + dirURL.lastPathComponent.dropFirst()
            let sceneDir = dirURL

            availableScenes.append(SceneEntry(id: baseName, displayName: displayName) { [weak self] in
                self?.makeParallaxScene(baseName: baseName, directory: sceneDir) ?? SCNScene()
            })
        }

        // Auto-discover 3D model files from bundle's models/ folder.
        // Supported: .usdz, .obj, .dae, .scn
        if let modelsURL = Bundle.main.resourceURL?.appendingPathComponent("models") {
            let supportedExts: Set<String> = ["usdz", "obj", "dae", "scn"]
            if let modelFiles = try? FileManager.default.contentsOfDirectory(
                at: modelsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) {
                for fileURL in modelFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    guard supportedExts.contains(fileURL.pathExtension.lowercased()) else { continue }
                    let name = fileURL.deletingPathExtension().lastPathComponent
                    let displayName = name.prefix(1).uppercased() + name.dropFirst()
                    let url = fileURL
                    availableScenes.append(SceneEntry(id: "model_\(name)", displayName: displayName) { [weak self] in
                        self?.makeModelScene(fileURL: url) ?? SCNScene()
                    })
                }
            }
        }

        // Default to first scene
        currentIndex = 0
    }

    func cycleScene() {
        let next = (currentIndex + 1) % availableScenes.count
        switchToScene(index: next)
    }

    func switchToScene(index: Int) {
        guard index < availableScenes.count else { return }
        currentIndex = index

        // Release the previous scene and its textures before building the new one.
        modelNode = nil
        currentScene = nil
        sceneView.scene = nil

        let entry = availableScenes[index]
        let scene = entry.builder()
        currentScene = scene
        scene.rootNode.addChildNode(cameraNode)
        sceneView.scene = scene
    }

    // MARK: - View lifecycle

    override func loadView() {
        self.view = sceneView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
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

        switchToScene(index: currentIndex)
    }

    // MARK: - Layer manifest

    private struct LayerManifestEntry: Decodable {
        let file: String
        let label: String
        let z: Int
    }

    /// Generic parallax photo scene built from depth-sliced PNG layers.
    ///
    /// If a `{baseName}_layers.json` manifest exists, uses trim metadata to
    /// create smaller planes positioned correctly — saving RAM.
    /// Falls back to filename-based discovery when no manifest is present.
    private func makeParallaxScene(baseName: String, directory: URL) -> SCNScene {
        let scene = SCNScene()

        // Try manifest first; fall back to filename-based discovery.
        let layers: [(file: String, z: CGFloat)]

        let manifestURL = directory.appendingPathComponent("\(baseName)_layers.json")
        if let data = try? Data(contentsOf: manifestURL),
           let entries = try? JSONDecoder().decode([LayerManifestEntry].self, from: data) {
            layers = entries
                .map { (file: $0.file, z: CGFloat($0.z)) }
                .sorted { $0.z < $1.z }
        } else {
            // Fallback: discover layers from filenames
            let allFiles = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            let prefix = "\(baseName)_layer_"
            var discovered: [(file: String, z: CGFloat)] = []
            for file in allFiles.sorted() where file.hasPrefix(prefix) && file.hasSuffix(".png") {
                let stem = String(file.dropLast(4))
                let parts = stem.split(separator: "_")
                if let zPart = parts.first(where: { $0.hasPrefix("z") && $0.count > 1 }),
                   let zVal = Int(zPart.dropFirst()) {
                    discovered.append((file: file, z: CGFloat(-zVal)))
                }
            }
            layers = discovered.sorted { $0.z < $1.z }
        }

        guard !layers.isEmpty else {
            print("Warning: no layers found for parallax scene '\(baseName)' in \(directory.path)")
            return scene
        }

        let fovVertical = Float(70.0 * Double.pi / 180.0)
        let tanHalfFov  = CGFloat(tan(fovVertical / 2.0))
        let cameraZ: CGFloat = 20.0
        let overscanFactor: CGFloat = 1.5

        // Pre-load all layer images from the scene directory.
        var layerImages: [NSImage] = []
        for entry in layers {
            let imageURL = directory.appendingPathComponent(entry.file)
            guard let image = NSImage(contentsOf: imageURL) else {
                print("Warning: image not found: \(imageURL.path)")
                layerImages.append(NSImage())
                continue
            }
            layerImages.append(image)
        }

        // Derive aspect ratio from the first layer image (all layers are full-frame).
        var origAspect: CGFloat = 16.0 / 9.0
        if let first = layerImages.first, first.size.height > 0 {
            origAspect = first.size.width / first.size.height
        }

        // Background fill plane behind all layers (stretched sky to cover extreme angles).
        // Reuses the already-loaded sky image to avoid a duplicate ~30-60 MB decode.
        let skyImage = layerImages[0]
        if skyImage.size.width > 0 {
            let fillZ: CGFloat = -200
            let fillDist = cameraZ - fillZ
            let fillHeight = 2.0 * fillDist * tanHalfFov * 2.0
            let fillWidth  = fillHeight * origAspect
            let fillPlane  = SCNPlane(width: fillWidth, height: fillHeight)
            let fillMat    = SCNMaterial()
            fillMat.diffuse.contents    = skyImage
            fillMat.isDoubleSided       = true
            fillMat.blendMode           = .alpha
            fillMat.writesToDepthBuffer = false
            fillPlane.materials = [fillMat]
            let fillNode = SCNNode(geometry: fillPlane)
            fillNode.position    = SCNVector3(0, 0, fillZ)
            fillNode.renderingOrder = -1
            scene.rootNode.addChildNode(fillNode)
        }

        for (index, entry) in layers.enumerated() {
            let image = layerImages[index]
            guard image.size.width > 0 else { continue }

            // Full-frame plane dimensions at this Z depth
            let distance    = cameraZ - entry.z
            let planeHeight = 2.0 * distance * tanHalfFov * overscanFactor
            let planeWidth  = planeHeight * origAspect

            let plane = SCNPlane(width: planeWidth, height: planeHeight)
            let mat = SCNMaterial()
            mat.diffuse.contents    = image
            mat.isDoubleSided       = true
            mat.blendMode           = .alpha
            mat.writesToDepthBuffer = false
            plane.materials = [mat]

            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(0, 0, entry.z)
            node.renderingOrder = index
            scene.rootNode.addChildNode(node)
        }

        // Full-brightness ambient so photo layers render without tint
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 1000
        scene.rootNode.addChildNode(ambient)

        return scene
    }

    /// 3D model scene — loads an external model file, centers and scales it,
    /// and rotates it per-frame based on head tracking.
    private func makeModelScene(fileURL: URL) -> SCNScene {
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
        let targetSize: Float = 12.0
        let scale = maxExtent > 0 ? targetSize / Float(maxExtent) : 1.0

        content.position = SCNVector3(-center.x, -center.y, -center.z)

        let wrapper = SCNNode()
        wrapper.addChildNode(content)
        wrapper.scale = SCNVector3(scale, scale, scale)
        wrapper.position = SCNVector3(0, 0, -5)   // slightly behind the window plane

        let scene = SCNScene()
        scene.rootNode.addChildNode(wrapper)
        modelNode = wrapper
        modelBaseScale = scale

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

    private func updatePowerState() {
        if shouldRun {
            headTracker.start()
            sceneView.isPlaying = true
        } else {
            sceneView.isPlaying = false
            headTracker.stop()
        }
    }

    // MARK: - Head Tracking

    private func setupHeadTracking() {
        updatePowerState()
    }

    fileprivate func updateCamera(offset: HeadTracker.HeadOffset) {
        let eyeX = Float(basePosition.x) + offset.x * lateralScale
        let eyeY = Float(basePosition.y) + offset.y * verticalScale
        let eyeZ = Float(basePosition.z) - (offset.z - 1.0) * depthScale

        cameraNode.position = SCNVector3(CGFloat(eyeX), CGFloat(eyeY), CGFloat(eyeZ))

        // Off-axis projection: the virtual screen is a fixed rectangle at screenZ.
        // The frustum is skewed so the screen edges act as a stationary window frame
        // while the viewpoint (eye) moves.  This produces physically-correct
        // depth-dependent parallax — the hallmark of the "window" illusion.
        let dist = eyeZ - screenZ
        guard dist > nearClip else { return }

        let halfW = screenHalfH * viewAspect
        let s     = nearClip / dist          // near-plane / eye-to-screen distance

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
            let curvedX = copysign(pow(abs(offset.x), 1.5), offset.x)
            let curvedY = copysign(pow(abs(offset.y), 1.5), offset.y)
            model.eulerAngles = SCNVector3(
                curvedY * modelMaxRotX,
               -curvedX * modelMaxRotY,
                0
            )

            // Scale model based on depth — closer = bigger, further = smaller.
            // Clamp to avoid extreme sizes.
            let depthScale = min(max(offset.z, 0.5), 2.0)
            let s = modelBaseScale * depthScale
            model.scale = SCNVector3(s, s, s)
        }
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

// MARK: - SCNSceneRendererDelegate

extension SceneViewController: SCNSceneRendererDelegate {
    /// Called by SceneKit once per frame, right before rendering.
    /// Pulling the latest head offset here instead of via async dispatch
    /// ensures every frame uses the freshest available data with zero scheduling jitter.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        updateCamera(offset: headTracker.predictedOffset(atTime: time))
    }
}
