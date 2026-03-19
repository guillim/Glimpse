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

    override func loadView() {
        self.view = sceneView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupHeadTracking()
    }

    // MARK: - Scene

    private func setupScene() {
        let scene = makeSpaceScene()
        sceneView.scene = scene
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 60
        sceneView.rendersContinuously = true

        // Camera
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 70
        cameraNode.camera?.zFar = 500
        cameraNode.position = basePosition
        scene.rootNode.addChildNode(cameraNode)
    }

    /// Procedural deep-space scene — no external assets needed.
    private func makeSpaceScene() -> SCNScene {
        let scene = SCNScene()

        // --- Starfield ---
        let starCount = 800
        for _ in 0..<starCount {
            let star = SCNNode(geometry: SCNSphere(radius: CGFloat.random(in: 0.02...0.12)))
            star.geometry?.firstMaterial?.diffuse.contents = NSColor.white
            star.geometry?.firstMaterial?.emission.contents = NSColor.white
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
        // Slow rotation
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
        rock.segmentCount = 6   // low-poly look
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

    // MARK: - Head Tracking

    private func setupHeadTracking() {
        headTracker.onHeadOffset = { [weak self] offset in
            self?.updateCamera(offset: offset)
        }
        headTracker.start()
    }

    private func updateCamera(offset: HeadTracker.HeadOffset) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.0   // already smoothed in HeadTracker

        cameraNode.position = SCNVector3(
            basePosition.x + CGFloat(offset.x * lateralScale),
            basePosition.y + CGFloat(offset.y * verticalScale),
            basePosition.z - CGFloat((offset.z - 1.0) * depthScale)
        )

        // Keep the camera always looking at the scene center
        let lookAt = SCNLookAtConstraint(target: nil)   // nil = world origin
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]

        SCNTransaction.commit()
    }
}
