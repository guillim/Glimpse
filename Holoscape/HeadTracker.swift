import AVFoundation
import Vision
import CoreImage
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

    var onHeadOffset: ((HeadOffset) -> Void)?

    // Smoothing
    private var smoothed = HeadOffset(x: 0, y: 0, z: 1)
    private let alpha: Float = 0.15   // low-pass filter strength

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.holoscape.headtracker", qos: .userInteractive)
    private let sequenceHandler = VNSequenceRequestHandler()

    // Baseline face bounding-box width (set on first detection)
    private var baselineFaceWidth: Float?

    override init() {
        super.init()
        setupCapture()
    }

    func start() { queue.async { self.session.startRunning() } }
    func stop()  { session.stopRunning() }

    // MARK: - Private

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
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceLandmarksRequest()
        try? sequenceHandler.perform([request], on: pixelBuffer, orientation: .leftMirrored)

        guard let observation = request.results?.first else { return }

        let box = observation.boundingBox   // normalized 0-1, origin bottom-left

        // Face center in -1…1 (x: left=negative, y: up=positive)
        let cx = Float(box.midX) * 2 - 1
        let cy = Float(box.midY) * 2 - 1  // Vision y=0 is bottom

        // Depth proxy: compare face width to baseline
        let faceWidth = Float(box.width)
        if baselineFaceWidth == nil { baselineFaceWidth = faceWidth }
        let depth = faceWidth / (baselineFaceWidth ?? faceWidth)

        // Low-pass smooth
        smoothed.x = smoothed.x + alpha * (cx - smoothed.x)
        smoothed.y = smoothed.y + alpha * (cy - smoothed.y)
        smoothed.z = smoothed.z + alpha * (depth - smoothed.z)

        DispatchQueue.main.async { [smoothed] in
            self.onHeadOffset?(smoothed)
        }
    }
}
