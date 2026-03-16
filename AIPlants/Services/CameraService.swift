import AVFoundation
import CoreImage
import SwiftUI
import Combine

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didOutput sampleBuffer: CMSampleBuffer)
}

class CameraService: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published private(set) var isRunning: Bool = false
    weak var delegate: CameraServiceDelegate?
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false
    
    override init() {
        super.init()
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        requestPermissionIfNeeded()
    }
    
    func start() {
        sessionQueue.async {
            guard self.authorizationStatus == .authorized else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }
    
    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }
    
    private func requestPermissionIfNeeded() {
        switch authorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.authorizationStatus = granted ? .authorized : .denied
                }
            }
        default:
            break
        }
    }
    
    private func configureSession() {
        guard !isConfigured else { return }
        isConfigured = true
        
        session.beginConfiguration()
        session.sessionPreset = .high
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            session.commitConfiguration()
            return
        }
        session.addInput(videoInput)
        
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.output.queue", qos: .userInitiated))
        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)
        
        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        
        session.commitConfiguration()
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.cameraService(self, didOutput: sampleBuffer)
    }
}
