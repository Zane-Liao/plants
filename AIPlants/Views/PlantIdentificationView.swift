import SwiftUI
import Combine
import PhotosUI

struct PlantIdentificationView: View {
    @StateObject private var presenter = PlantPresenter()
    @State private var isShowingDebugPanel = false
    @State private var isShowingFilesPicker = false
    @State private var photoItem: PhotosPickerItem?
    
    var body: some View {
        ZStack {
            // Camera Background
            CameraPreviewView(session: presenter.cameraService.session)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            // UI Overlay
            VStack {
                Spacer()
                
                // Prediction Card (Liquid Glass Style)
                glassCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
        }
        .onDisappear { presenter.cameraService.stop() }
        .onChange(of: presenter.isModelReady) { _, ready in
            if ready {
                presenter.cameraService.start()
            } else {
                presenter.cameraService.stop()
            }
        }
        .task {
            // Defer heavy work until after first render.
            await Task.yield()
            try? await Task.sleep(nanoseconds: 250_000_000)
            presenter.loadModelIfNeeded()
        }
        .overlay(alignment: .topTrailing) {
            #if DEBUG || targetEnvironment(simulator)
            Button {
                isShowingDebugPanel = true
            } label: {
                Text("Debug")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.65))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                    )
            }
            .padding(.trailing, 16)
            .padding(.top, 12)
            #endif
        }
        #if DEBUG || targetEnvironment(simulator)
        .sheet(isPresented: $isShowingDebugPanel) {
            debugPanel
        }
        .sheet(isPresented: $isShowingFilesPicker) {
            DocumentImagePicker { image in
                presenter.debugClassify(image: image)
                isShowingFilesPicker = false
            }
        }
        #endif
    }
    
    private var glassCard: some View {
        VStack(spacing: 16) {
            if let error = presenter.modelLoadErrorMessage {
                Text(error)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
            if let topResult = presenter.topResult {
                HStack {
                    VStack(alignment: .leading) {
                        Text(topResult.label)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(String(format: "Confidence: %.1f%%", topResult.confidence * 100))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    if presenter.isIdentifying {
                        ProgressView()
                            .tint(.white)
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.3))
                
                // Search Buttons
                HStack(spacing: 12) {
                    searchButton(title: "Bing Search", engine: .bing)
                    searchButton(title: "Google Search", engine: .google)
                }
                
                // Secondary results
                if !presenter.otherResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Other possibilities:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.top, 4)
                        
                        ForEach(presenter.otherResults.prefix(2)) { result in
                            HStack {
                                Text(result.label)
                                Spacer()
                                Text(String(format: "%.0f%%", result.confidence * 100))
                            }
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                
            } else {
                Text("Searching for plants...")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
    }
    
    private func searchButton(title: String, engine: SearchEngineType) -> some View {
        Button {
            if engine == .bing {
                presenter.searchOnBing()
            } else {
                presenter.searchOnGoogle()
            }
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                )
        }
    }

    #if DEBUG || targetEnvironment(simulator)
    private var debugPanel: some View {
        NavigationView {
            VStack(spacing: 16) {
                if let img = presenter.debugImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                }

                VStack(spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text("Pick from Photos")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        isShowingFilesPicker = true
                    } label: {
                        Text("Pick from Files (Folder)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)

                if !presenter.debugResults.isEmpty {
                    List {
                        Section("Model Output") {
                            ForEach(presenter.debugResults) { r in
                                HStack {
                                    Text(r.label)
                                    Spacer()
                                    Text(String(format: "%.3f", r.confidence))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Spacer()
                    Text("Pick an image to run the model.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .navigationTitle("Developer Debug")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isShowingDebugPanel = false }
                }
            }
            .task(id: photoItem) {
                guard let photoItem else { return }
                if let data = try? await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    presenter.debugClassify(image: image)
                }
            }
        }
    }
    #endif
}

enum SearchEngineType {
    case bing, google
}

#Preview {
    PlantIdentificationView()
}
