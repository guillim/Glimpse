import AVFoundation
import CoreMotion
import Vision
import CoreImage
import QuartzCore

/// Publishes normalized head offset in [-1, 1] for X and Y axes,
/// and a rough depth estimate on Z.
///
/// Input sources (in priority order):
/// 1. CMHeadphoneMotionManager (AirPods Pro/Max) — sub-ms latency, zero jitter
/// 2. AVCaptureSession + Vision face detection — universal fallback
///
/// Design priorities (see README):
/// 1. Smoothness — no frame jumps, ever
/// 2. Latency — as low as possible without sacrificing smoothness
final class HeadTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    struct HeadOffset {
        /// Horizontal offset: -1 = far left, +1 = far right
        var x: Float
        /// Vertical offset: -1 = far down, +1 = far up
        var y: Float
        /// Depth proxy: 1.0 = baseline distance, >1 = closer, <1 = further
        var z: Float
    }

    /// Whether AirPods/Beats head tracking is active.
    var isUsingHeadphones: Bool {
        offsetLock.lock()
        defer { offsetLock.unlock() }
        return _isUsingHeadphones
    }

    /// Latest Kalman-filtered head offset. Thread-safe: readable from any thread.
    var latestOffset: HeadOffset {
        offsetLock.lock()
        defer { offsetLock.unlock() }
        return _latestOffset
    }

    /// Extrapolates the head position to `renderTime` using the Kalman velocity estimate,
    /// so every rendered frame uses a prediction of where the head *will be* rather than
    /// where it *was* at the last camera frame.
    func predictedOffset(atTime renderTime: Double) -> HeadOffset {
        offsetLock.lock()
        let offset      = _latestOffset
        let velocity    = _latestVelocity
        let lastTime    = _lastMeasurementTime
        let headphones  = _isUsingHeadphones
        offsetLock.unlock()

        guard let last = lastTime else { return offset }
        let dt = Float(min(renderTime - last, 0.1))
        guard dt > 0 else { return offset }

        // Headphone tracking is so low-latency that prediction adds more
        // overshoot risk than benefit. Only predict for camera tracking.
        guard !headphones else { return offset }

        // Dampen velocity to reduce overshoot when the head stops or reverses.
        let baseDamp: Float = 0.6

        // Fade out prediction when the last measurement is getting stale.
        let staleness = Float(renderTime - last)
        let staleFade = max(1.0 - staleness * 5.0, 0.0)
        let damp = baseDamp * staleFade

        return HeadOffset(
            x: offset.x + velocity.x * damp * dt,
            y: offset.y + velocity.y * damp * dt,
            z: offset.z + velocity.z * damp * dt
        )
    }

    // MARK: - Private state (shared)

    private let offsetLock          = NSLock()
    private var _latestOffset       = HeadOffset(x: 0, y: 0, z: 1)
    private var _latestVelocity     = HeadOffset(x: 0, y: 0, z: 0)
    private var _lastMeasurementTime: Double?
    private var _isUsingHeadphones  = false

    // MARK: - Headphone motion (source 1)

    private var headphoneManager: AnyObject?  // CMHeadphoneMotionManager (macOS 14+)
    private let headphoneQueue = OperationQueue()

    // Map gyroscope angles to [-1, 1] range.
    // Typical head turn: ±30° yaw, ±20° pitch.
    private let yawScale: Float   = 1.0 / (30.0 * .pi / 180.0)   // ±30° → ±1
    private let pitchScale: Float = 1.0 / (20.0 * .pi / 180.0)   // ±20° → ±1

    // Reference attitude captured on start — all motion is relative to this.
    private var referenceYaw: Double?
    private var referencePitch: Double?

    // Lightweight Kalman for headphone input — much less smoothing needed
    // since the gyroscope signal is already clean.
    private var hpKfX = KalmanFilter1D(processNoise: 0.05, measurementNoise: 0.01)
    private var hpKfY = KalmanFilter1D(processNoise: 0.05, measurementNoise: 0.01)
    private var hpLastTime: Double?

    // MARK: - Camera tracking (source 2)

    // Kalman filters — 3:1 ratio: moderate smoothing that suppresses
    // single-frame detection spikes. Render-side EMA handles visual smoothness.
    private var kfX = KalmanFilter1D(processNoise: 0.015, measurementNoise: 0.045)
    private var kfY = KalmanFilter1D(processNoise: 0.015, measurementNoise: 0.045)
    private var kfZ = KalmanFilter1D(processNoise: 0.008, measurementNoise: 0.05)

    private let session             = AVCaptureSession()
    private let cameraQueue         = DispatchQueue(label: "com.glimpse.camera", qos: .userInteractive)

    private var baselineFaceWidth: Float?
    private var lastTimestamp: Double?
    private var frameCounter: Int = 0

    // Pre-computed downscale transform (640×480 → 160×120)
    private let scaleTransform = CGAffineTransform(scaleX: 0.25, y: 0.25)

    // MARK: - Init

    override init() {
        headphoneQueue.name = "com.glimpse.headphone"
        headphoneQueue.maxConcurrentOperationCount = 1
        headphoneQueue.qualityOfService = .userInteractive
        super.init()
        setupCapture()
        setupHeadphoneMotion()
    }

    func start() {
        // Always start camera — it provides depth (Z) even when headphones are active.
        cameraQueue.async {
            self.lastTimestamp = nil
            self.frameCounter = 0
            self.session.startRunning()
        }
        startHeadphoneMotion()
    }

    func stop() {
        session.stopRunning()
        stopHeadphoneMotion()
        baselineFaceWidth = nil
    }

    // MARK: - Headphone motion setup

    private func setupHeadphoneMotion() {
        guard #available(macOS 14.0, *) else { return }
        let manager = CMHeadphoneMotionManager()
        guard manager.isDeviceMotionAvailable else {
            print("[HeadTracker] Headphone motion not available")
            return
        }
        headphoneManager = manager
        print("[HeadTracker] Headphone motion available")
    }

    private func startHeadphoneMotion() {
        guard #available(macOS 14.0, *) else { return }
        guard let manager = headphoneManager as? CMHeadphoneMotionManager,
              !manager.isDeviceMotionActive else { return }

        referenceYaw   = nil
        referencePitch = nil
        hpLastTime     = nil
        hpKfX = KalmanFilter1D(processNoise: 0.05, measurementNoise: 0.01)
        hpKfY = KalmanFilter1D(processNoise: 0.05, measurementNoise: 0.01)

        manager.startDeviceMotionUpdates(to: headphoneQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            self.handleHeadphoneMotion(motion)
        }
    }

    private func stopHeadphoneMotion() {
        if #available(macOS 14.0, *) {
            (headphoneManager as? CMHeadphoneMotionManager)?.stopDeviceMotionUpdates()
        }
        offsetLock.lock()
        _isUsingHeadphones = false
        offsetLock.unlock()
    }

    private func handleHeadphoneMotion(_ motion: CMDeviceMotion) {
        let yaw   = motion.attitude.yaw
        let pitch = motion.attitude.pitch

        // Capture reference pose on first sample.
        if referenceYaw == nil {
            referenceYaw   = yaw
            referencePitch = pitch
        }

        let relYaw   = Float(yaw   - (referenceYaw   ?? 0))
        let relPitch = Float(pitch - (referencePitch ?? 0))

        // Map to [-1, 1] and clamp
        let rawX = max(-1, min(1, relYaw   * yawScale))
        let rawY = max(-1, min(1, relPitch * pitchScale))

        // Lightweight Kalman — gyro signal is clean, just removes micro-noise
        let now = CACurrentMediaTime()
        let dt: Float
        if let last = hpLastTime {
            dt = Float(now - last)
        } else {
            dt = 1.0 / 100.0
        }
        hpLastTime = now

        let filteredX = hpKfX.update(measurement: rawX, dt: dt)
        let filteredY = hpKfY.update(measurement: rawY, dt: dt)

        offsetLock.lock()
        _latestOffset        = HeadOffset(x: filteredX, y: filteredY, z: _latestOffset.z)
        _latestVelocity      = HeadOffset(x: hpKfX.v,   y: hpKfY.v,  z: _latestVelocity.z)
        _lastMeasurementTime = now
        _isUsingHeadphones   = true
        offsetLock.unlock()
    }

    // MARK: - Camera capture setup

    private func setupCapture() {
        session.sessionPreset = .vga640x480

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            print("[HeadTracker] No camera available")
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: cameraQueue)

        if session.canAddInput(input)   { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }

        trySet60fps(on: device)
    }

    private func trySet60fps(on device: AVCaptureDevice) {
        let capable = device.formats.filter {
            $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 59.0 }
        }.sorted {
            let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return (a.width * a.height) < (b.width * b.height)
        }

        guard let format = capable.first else {
            print("[HeadTracker] 60 fps not supported, staying at 30 fps")
            return
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
            device.unlockForConfiguration()
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            print("[HeadTracker] Camera configured for 60 fps at \(dims.width)×\(dims.height)")
        } catch {
            print("[HeadTracker] Could not configure 60 fps: \(error)")
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Process every other frame — at 30fps camera this gives 15Hz detection.
        // The render-side EMA interpolates smoothly between measurements.
        frameCounter += 1
        guard frameCounter % 2 == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let dt: Float
        if let last = lastTimestamp, timestamp > last {
            dt = Float(timestamp - last)
        } else {
            dt = 1.0 / 30.0
        }
        lastTimestamp = timestamp

        // Face detection on the raw pixel buffer — Vision normalises coordinates to [0,1].
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .upMirrored)
        try? handler.perform([request])

        guard let face = request.results?.first else { return }

        let box = face.boundingBox
        let cx = Float(box.midX) * 2 - 1
        let cy = Float(box.midY) * 2 - 1

        let faceWidth = Float(box.width)
        if baselineFaceWidth == nil { baselineFaceWidth = faceWidth }
        let depth = faceWidth / (baselineFaceWidth ?? faceWidth)

        let filteredX = kfX.update(measurement: cx,    dt: dt)
        let filteredY = kfY.update(measurement: cy,    dt: dt)
        let filteredZ = kfZ.update(measurement: depth, dt: dt)

        let hostTime = CACurrentMediaTime()

        offsetLock.lock()
        // When headphones are active, only update Z (depth) from camera.
        // X/Y come from the gyroscope which is far more precise.
        if _isUsingHeadphones {
            _latestOffset.z  = filteredZ
            _latestVelocity.z = kfZ.v
        } else {
            _latestOffset   = HeadOffset(x: filteredX, y: filteredY, z: filteredZ)
            _latestVelocity = HeadOffset(x: kfX.v, y: kfY.v, z: kfZ.v)
            _lastMeasurementTime = hostTime
        }
        offsetLock.unlock()
    }
}

// MARK: - Kalman Filter

/// 1-D constant-velocity Kalman filter.
///
/// State vector: [position, velocity]
/// Observation:  position only (H = [1, 0])
///
/// Tuning:
///   processNoise     — raise to follow fast movements more aggressively (less smooth)
///   measurementNoise — raise to trust the sensor less (smoother, more lag)
private struct KalmanFilter1D {

    var x: Float = 0   // estimated position
    var v: Float = 0   // estimated velocity (exposed for extrapolation)

    // Covariance matrix P stored as four scalars (symmetric 2×2)
    var p00: Float = 1
    var p01: Float = 0
    var p10: Float = 0
    var p11: Float = 1

    let processNoise: Float
    let measurementNoise: Float

    init(processNoise: Float, measurementNoise: Float) {
        self.processNoise    = processNoise
        self.measurementNoise = measurementNoise
    }

    mutating func update(measurement z: Float, dt: Float) -> Float {
        let xp   = x + v * dt
        let vp   = v
        let p00p = p00 + dt * (p01 + p10) + dt * dt * p11 + processNoise
        let p01p = p01 + dt * p11
        let p10p = p10 + dt * p11
        let p11p = p11 + processNoise

        let s   = p00p + measurementNoise
        let k0  = p00p / s
        let k1  = p10p / s

        let inn = z - xp
        x = xp + k0 * inn
        v = vp + k1 * inn

        p00 = (1 - k0) * p00p
        p01 = (1 - k0) * p01p
        p10 = p10p - k1 * p00p
        p11 = p11p - k1 * p01p

        return x
    }
}
