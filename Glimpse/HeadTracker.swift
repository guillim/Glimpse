import AVFoundation
import Vision
import CoreImage
import QuartzCore   // CACurrentMediaTime — same clock domain as SceneKit render time
import simd

/// Publishes normalized head offset in [-1, 1] for X and Y axes,
/// and a rough depth estimate on Z.
final class HeadTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    struct HeadOffset {
        /// Horizontal offset: -1 = far left, +1 = far right
        var x: Float
        /// Vertical offset: -1 = far down, +1 = far up
        var y: Float
        /// Depth proxy: 1.0 = baseline distance, >1 = closer, <1 = further
        var z: Float
    }

    /// Latest Kalman-filtered head offset. Thread-safe: readable from any thread.
    var latestOffset: HeadOffset {
        offsetLock.lock()
        defer { offsetLock.unlock() }
        return _latestOffset
    }

    /// Extrapolates the head position to `renderTime` using the Kalman velocity estimate,
    /// so every rendered frame uses a prediction of where the head *will be* rather than
    /// where it *was* at the last camera frame. Clamped to 100 ms max extrapolation.
    func predictedOffset(atTime renderTime: Double) -> HeadOffset {
        offsetLock.lock()
        let offset      = _latestOffset
        let velocity    = _latestVelocity
        let lastTime    = _lastMeasurementTime
        offsetLock.unlock()

        guard let last = lastTime else { return offset }
        let dt = Float(min(renderTime - last, 0.15))
        guard dt > 0 else { return offset }

        // Dampen velocity to reduce overshoot when the head stops or reverses.
        // 0.7 = predict 70% of the full velocity — enough to cut latency
        // without the camera visibly overshooting the target.
        let baseDamp: Float = 0.9

        // Fade out prediction when the last measurement is getting stale
        // (e.g. face lost for a few frames). This prevents the camera from
        // drifting along a stale velocity vector and then snapping back.
        let staleness = Float(renderTime - last)          // seconds since last real measurement
        let staleFade = max(1.0 - staleness * 5.0, 0.0)  // linear fade over 200 ms → 0
        let damp = baseDamp * staleFade

        return HeadOffset(
            x: offset.x + velocity.x * damp * dt,
            y: offset.y + velocity.y * damp * dt,
            z: offset.z + velocity.z * damp * dt
        )
    }

    // MARK: - Private state

    // Kalman filters — one per axis
    private var kfX = KalmanFilter1D(processNoise: 0.02, measurementNoise: 0.02)
    private var kfY = KalmanFilter1D(processNoise: 0.02, measurementNoise: 0.02)
    private var kfZ = KalmanFilter1D(processNoise: 0.02, measurementNoise: 0.02)

    private let offsetLock          = NSLock()
    private var _latestOffset       = HeadOffset(x: 0, y: 0, z: 1)
    private var _latestVelocity     = HeadOffset(x: 0, y: 0, z: 0)
    private var _lastMeasurementTime: Double?

    /// Maximum allowed jump per axis per second. Measurements that would move
    /// faster than this are clamped, preventing tracker-to-detector transitions
    /// from causing visible frame jumps.
    private let maxRateXY: Float = 1.8   // units/s in normalised [-1,1] space
    private let maxRateZ: Float  = 1.2   // depth units/s

    private let session             = AVCaptureSession()
    private let queue               = DispatchQueue(label: "com.glimpse.headtracker", qos: .userInteractive)
    private var sequenceHandler     = VNSequenceRequestHandler()

    private var baselineFaceWidth: Float?
    private var lastTimestamp: Double?

    // Tracking state (feature 2)
    private var trackingRequest: VNTrackObjectRequest?
    private var lastTrackedBox: CGRect?               // last good tracked position
    private var framesSinceDetect   = 0
    private let redetectInterval    = 120 // force full re-detect every 120 tracked frames

    // Confidence hysteresis: drop tracker only when it falls below the low
    // threshold, but require the high threshold to accept a new detection.
    // This prevents oscillating between tracker and detector near the boundary.
    private let confidenceLow: Float  = 0.2
    private let confidenceHigh: Float = 0.5

    // Pre-computed downscale transform (feature 3: 640×480 → 160×120)
    private let scaleTransform = CGAffineTransform(scaleX: 0.25, y: 0.25)

    // MARK: - Init

    override init() {
        super.init()
        setupCapture()
    }

    func start() {
        queue.async {
            self.lastTimestamp = nil   // prevent dt spike on first frame after a pause
            self.session.startRunning()
        }
    }
    func stop() {
        session.stopRunning()
        // Release the compiled Vision model and stale tracking state while idle.
        // Both are recreated lazily on the next start().
        sequenceHandler   = VNSequenceRequestHandler()
        trackingRequest   = nil
        baselineFaceWidth = nil   // depth baseline resets on resume — user may have moved
    }

    // MARK: - Capture setup

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
        output.setSampleBufferDelegate(self, queue: queue)

        if session.canAddInput(input)   { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }

        trySet60fps(on: device)
    }

    /// Attempts to configure the camera for 60 fps, choosing the lowest-resolution
    /// format that supports it (faster Vision processing, lower power).
    private func trySet60fps(on device: AVCaptureDevice) {
        let capable = device.formats.filter {
            $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 59.0 }
        }.sorted {
            let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return (a.width * a.height) < (b.width * b.height)
        }

        guard let format = capable.first else {
            print("[HeadTracker] 60 fps not supported by this camera, staying at 30 fps")
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
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Real elapsed time since last frame — feeds accurate dt to the Kalman filter
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let dt: Float
        if let last = lastTimestamp, timestamp > last {
            dt = Float(timestamp - last)
        } else {
            dt = 1.0 / 30.0
        }
        lastTimestamp = timestamp

        let fullImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Feature 2 — fast optical-flow tracking; full detection only when needed.
        // Pass both full and downscaled images: the fast tracker uses full-res for
        // better accuracy, while expensive face detection uses the downscaled version.
        guard let box = boundingBox(fullImage: fullImage) else { return }

        var cx = Float(box.midX) * 2 - 1
        var cy = Float(box.midY) * 2 - 1

        let faceWidth = Float(box.width)
        if baselineFaceWidth == nil { baselineFaceWidth = faceWidth }
        var depth = faceWidth / (baselineFaceWidth ?? faceWidth)

        // Outlier clamping: if a measurement jumps further than physically
        // plausible (e.g. tracker→detector hand-off), clamp the rate of change
        // so the camera glides to the new position instead of snapping.
        if dt > 0 {
            let maxDx = maxRateXY * dt
            let maxDy = maxRateXY * dt
            let maxDz = maxRateZ  * dt
            cx    = kfX.x + clamp(cx    - kfX.x, min: -maxDx, max: maxDx)
            cy    = kfY.x + clamp(cy    - kfY.x, min: -maxDy, max: maxDy)
            depth = kfZ.x + clamp(depth - kfZ.x, min: -maxDz, max: maxDz)
        }

        let filteredX = kfX.update(measurement: cx,    dt: dt)
        let filteredY = kfY.update(measurement: cy,    dt: dt)
        let filteredZ = kfZ.update(measurement: depth, dt: dt)

        // Use the host clock (same domain as SceneKit's render time) so that
        // predictedOffset(atTime:) computes an accurate extrapolation delta.
        let hostTime = CACurrentMediaTime()

        // Feature 1 — also store velocity so the render loop can extrapolate forward
        offsetLock.lock()
        _latestOffset        = HeadOffset(x: filteredX, y: filteredY, z: filteredZ)
        _latestVelocity      = HeadOffset(x: kfX.v,     y: kfY.v,     z: kfZ.v)
        _lastMeasurementTime = hostTime
        offsetLock.unlock()
    }

    // MARK: - Vision helpers

    /// Returns a face bounding box, using the fast optical-flow tracker on most frames
    /// and falling back to full `VNDetectFaceRectanglesRequest` when tracking is lost
    /// or the periodic re-detect interval is reached.
    private func boundingBox(fullImage: CIImage) -> CGRect? {
        let needsPeriodicRedetect = framesSinceDetect >= redetectInterval
        let needsDetect = trackingRequest == nil || needsPeriodicRedetect

        if let tracker = trackingRequest, !needsDetect || needsPeriodicRedetect {
            // Fast tracker runs on full-res — it's cheap (optical flow) and
            // benefits from higher detail for sub-pixel accuracy.
            try? sequenceHandler.perform([tracker], on: fullImage, orientation: .upMirrored)

            if let result = tracker.results?.first as? VNDetectedObjectObservation,
               result.confidence >= confidenceLow {
                framesSinceDetect += 1
                lastTrackedBox = result.boundingBox

                if needsPeriodicRedetect {
                    // Soft re-detect: seed a fresh tracker from the detector in the
                    // background, but return the *current tracked* position this frame
                    // to avoid any visible jump.
                    let scaledImage = fullImage.transformed(by: scaleTransform)
                    softRedetect(in: scaledImage)
                }

                return result.boundingBox
            }
            // Confidence dropped below low threshold — fall through to full detection
        }

        // Downscale only for the expensive face detection pass.
        let scaledImage = fullImage.transformed(by: scaleTransform)
        return detect(in: scaledImage)
    }

    /// Runs a full `VNDetectFaceRectanglesRequest` and seeds a new tracker on success.
    /// Used when tracking is completely lost.
    private func detect(in image: CIImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        try? sequenceHandler.perform([request], on: image, orientation: .upMirrored)

        guard let observation = request.results?.first,
              observation.confidence >= confidenceHigh else {
            trackingRequest   = nil
            lastTrackedBox    = nil
            framesSinceDetect = 0
            return nil
        }

        let tracker = VNTrackObjectRequest(detectedObjectObservation: observation)
        tracker.trackingLevel = .fast
        trackingRequest   = tracker
        framesSinceDetect = 0
        return observation.boundingBox
    }

    /// Periodic re-detect: seeds a fresh tracker from the detector without
    /// returning the detector's bounding box — the caller keeps using the
    /// current tracked position so there's no visible discontinuity.
    private func softRedetect(in image: CIImage) {
        let request = VNDetectFaceRectanglesRequest()
        try? sequenceHandler.perform([request], on: image, orientation: .upMirrored)

        guard let observation = request.results?.first else { return }

        let tracker = VNTrackObjectRequest(detectedObjectObservation: observation)
        tracker.trackingLevel = .fast
        trackingRequest   = tracker
        framesSinceDetect = 0
    }
}

// MARK: - Helpers

/// Scalar clamp — avoids pulling in Foundation's `min`/`max` dance.
private func clamp(_ value: Float, min lo: Float, max hi: Float) -> Float {
    Swift.min(Swift.max(value, lo), hi)
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

    let processNoise: Float      // Q — uncertainty added to the model each step
    let measurementNoise: Float  // R — sensor variance

    init(processNoise: Float, measurementNoise: Float) {
        self.processNoise    = processNoise
        self.measurementNoise = measurementNoise
    }

    mutating func update(measurement z: Float, dt: Float) -> Float {
        // ── Predict ──────────────────────────────────────────────────────────
        let xp   = x + v * dt
        let vp   = v
        let p00p = p00 + dt * (p01 + p10) + dt * dt * p11 + processNoise
        let p01p = p01 + dt * p11
        let p10p = p10 + dt * p11
        let p11p = p11 + processNoise

        // ── Update (H = [1, 0]) ──────────────────────────────────────────────
        let s   = p00p + measurementNoise  // innovation variance  (H·P·Hᵀ + R)
        let k0  = p00p / s                 // Kalman gain — position row
        let k1  = p10p / s                 // Kalman gain — velocity row

        let inn = z - xp                   // innovation (residual)
        x = xp + k0 * inn
        v = vp + k1 * inn

        p00 = (1 - k0) * p00p
        p01 = (1 - k0) * p01p
        p10 = p10p - k1 * p00p
        p11 = p11p - k1 * p01p

        return x
    }
}
