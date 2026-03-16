import Foundation
import CoreMedia
import SwiftUI
import UIKit
import Combine

class PlantPresenter: ObservableObject, CameraServiceDelegate {
    @Published var topResult: IdentificationResult?
    @Published var otherResults: [IdentificationResult] = []
    @Published var isIdentifying = false
    @Published var modelLoadErrorMessage: String?
    @Published var debugImage: UIImage?
    @Published var debugResults: [IdentificationResult] = []
    @Published private(set) var isModelReady: Bool = false
    
    private var classifier: PlantClassifier?
    private var isModelLoading = false
    let cameraService = CameraService()
    
    // Throttling for classification
    private var lastIdentificationTime = Date.distantPast
    private let identificationInterval: TimeInterval = 0.5 // Run inference every 0.5s
    
    init() {
        self.cameraService.delegate = self
    }

    func loadModelIfNeeded() {
        guard !isModelReady, !isModelLoading else { return }
        isModelLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let model = try PlantClassifier()
                DispatchQueue.main.async {
                    self.classifier = model
                    self.isModelReady = true
                    self.isModelLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.modelLoadErrorMessage = "Failed to load ML model: \(error.localizedDescription)"
                    self.classifier = nil
                    self.isModelReady = false
                    self.isModelLoading = false
                }
            }
        }
    }
    
    func cameraService(_ service: CameraService, didOutput sampleBuffer: CMSampleBuffer) {
        guard Date().timeIntervalSince(lastIdentificationTime) > identificationInterval else { return }
        lastIdentificationTime = Date()
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let classifier = classifier else { return }
        
        DispatchQueue.main.async {
            self.isIdentifying = true
        }
        
        classifier.classify(pixelBuffer: pixelBuffer) { [weak self] results in
            self?.isIdentifying = false
            guard let topResult = results.first else { return }
            
            self?.topResult = topResult
            self?.otherResults = Array(results.dropFirst())
        }
    }
    
    func searchOnBing() {
        guard let name = topResult?.label else { return }
        openSearch(query: name, engine: .bing)
    }
    
    func searchOnGoogle() {
        guard let name = topResult?.label else { return }
        openSearch(query: name, engine: .google)
    }

    func debugClassify(image: UIImage) {
        guard let classifier else { return }
        debugImage = image
        debugResults = []
        classifier.classify(uiImage: image) { [weak self] results in
            self?.debugResults = results
        }
    }
    
    private enum SearchEngine {
        case bing, google
    }
    
    private func openSearch(query: String, engine: SearchEngine) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString: String
        switch engine {
        case .bing:
            urlString = "https://www.bing.com/search?q=\(encodedQuery)"
        case .google:
            urlString = "https://www.google.com/search?q=\(encodedQuery)"
        }
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
