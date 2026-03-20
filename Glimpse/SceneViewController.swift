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
        // Procedural scenes (always available)
        availableScenes.append(SceneEntry(id: "space", displayName: "Space", builder: makeSpaceScene))

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

        // Default to first parallax scene if available, otherwise first scene
        if let idx = availableScenes.firstIndex(where: { $0.id != "space" }) {
            currentIndex = idx
        }
    }

    func cycleScene() {
        let next = (currentIndex + 1) % availableScenes.count
        switchToScene(index: next)
    }

    func switchToScene(index: Int) {
        guard index < availableScenes.count else { return }
        currentIndex = index

        // Release the previous scene and its textures before building the new one.
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

    /// Procedural deep-space scene — no external assets needed.
    private func makeSpaceScene() -> SCNScene {
        let scene = SCNScene()

        // --- Starfield ---
        // One shared geometry + one GPU vertex buffer for all 800 stars.
        // segmentCount=4 gives 32 triangles vs the default 2,304 — invisible at this size.
        // Size variation is applied via per-node scale instead of separate geometry objects.
        let sharedStar = SCNSphere(radius: 0.07)
        sharedStar.segmentCount = 4
        sharedStar.firstMaterial?.diffuse.contents  = NSColor.white
        sharedStar.firstMaterial?.emission.contents = NSColor.white

        for _ in 0..<800 {
            let star = SCNNode(geometry: sharedStar)
            let s = CGFloat.random(in: 0.3...1.5)
            star.scale    = SCNVector3(s, s, s)
            star.position = SCNVector3(
                Float.random(in: -120...120),
                Float.random(in: -80...80),
                Float.random(in: -200...0)
            )
            scene.rootNode.addChildNode(star)
        }

        // --- Large glowing planet ---
        let planet = SCNSphere(radius: 14)
        let planetMat = SCNMaterial()
        planetMat.diffuse.contents  = NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.7, alpha: 1)
        planetMat.emission.contents = NSColor(calibratedRed: 0.0, green: 0.05, blue: 0.2, alpha: 1)
        planetMat.specular.contents = NSColor.white
        planet.materials = [planetMat]
        let planetNode = SCNNode(geometry: planet)
        planetNode.position = SCNVector3(18, -6, -60)
        let rotate = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 60))
        planetNode.runAction(rotate)
        scene.rootNode.addChildNode(planetNode)

        // --- Rings around the planet ---
        let ring = SCNTorus(ringRadius: 20, pipeRadius: 0.5)
        let ringMat = SCNMaterial()
        ringMat.diffuse.contents  = NSColor(calibratedRed: 0.8, green: 0.7, blue: 0.5, alpha: 0.7)
        ringMat.isDoubleSided = true
        ring.materials = [ringMat]
        let ringNode = SCNNode(geometry: ring)
        ringNode.position = planetNode.position
        ringNode.eulerAngles = SCNVector3(Float.pi / 6, 0, 0)
        scene.rootNode.addChildNode(ringNode)

        // --- Nearby rocky asteroid ---
        let rock = SCNSphere(radius: 1.2)
        rock.segmentCount = 6
        let rockMat = SCNMaterial()
        rockMat.diffuse.contents = NSColor(calibratedWhite: 0.35, alpha: 1)
        rock.materials = [rockMat]
        let rockNode = SCNNode(geometry: rock)
        rockNode.position = SCNVector3(-8, 3, 0)
        let rockOrbit = SCNAction.repeatForever(SCNAction.rotateBy(x: 0.3, y: 1, z: 0.1, duration: 8))
        rockNode.runAction(rockOrbit)
        scene.rootNode.addChildNode(rockNode)

        // --- Ambient + directional light ---
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 200
        ambient.light?.color = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.2, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 800
        sun.light?.color = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.8, alpha: 1)
        sun.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(sun)

        return scene
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
