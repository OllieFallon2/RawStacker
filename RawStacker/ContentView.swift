import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    
    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
            
            VStack {
                // 1. TOP BAR
                HStack {
                    Text("RAW").font(.caption).bold().padding(6)
                        .background(camera.isRawSupported ? Color.yellow : Color.gray)
                        .foregroundColor(.black).cornerRadius(5)
                    Spacer()
                    Toggle(isOn: $camera.isStackingEnabled) {
                        Text("Stack").font(.subheadline).bold().foregroundColor(.white)
                    }
                    .toggleStyle(.button).tint(.orange).padding(6)
                    .background(Color.black.opacity(0.4)).cornerRadius(8)
                }.padding()
                
                Spacer()
                
                // 2. PRO CONTROLS MENU
                if !camera.isProcessing {
                    VStack(spacing: 12) {
                        if camera.isStackingEnabled {
                            HStack {
                                Text("Frames: \(camera.stackCount)").font(.headline)
                                Spacer()
                                Stepper("", value: $camera.stackCount, in: 2...30).labelsHidden()
                                    .background(Color.white.opacity(0.2)).cornerRadius(8)
                            }
                            Picker("Format", selection: $camera.saveAsJPEG) {
                                Text("TIFF").tag(false)
                                Text("JPEG").tag(true)
                            }.pickerStyle(.segmented)
                            Divider().background(Color.white.opacity(0.3))
                        }

                        Toggle("Manual Exposure", isOn: $camera.isManualMode)
                            .onChange(of: camera.isManualMode) { camera.applyManualSettings() }
                            .font(.subheadline).bold()
                        
                        if camera.isManualMode {
                            VStack(spacing: 15) {
                                controlSlider(label: "ISO", value: $camera.currentISO, range: camera.minISO...camera.maxISO, display: "\(Int(camera.currentISO))")
                                controlSlider(label: "Shutter", value: $camera.currentShutterSpeed, range: camera.minDuration...0.5, display: formatShutterSpeed(camera.currentShutterSpeed))
                            }
                        }

                        if camera.isStackingEnabled {
                            HStack(spacing: 20) {
                                Label(camera.estimatedSizeMB, systemImage: "sdcard.fill")
                                Label(camera.estimatedTimeSecconds, systemImage: "stopwatch.fill")
                            }.font(.caption2).foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding().background(BlurView(style: .systemUltraThinMaterialDark))
                    .cornerRadius(16).padding(.horizontal).padding(.bottom, 20)
                }
                
                // 3. SHUTTER
                Button(action: { camera.handleCapture() }) {
                    Circle()
                        .fill(camera.isProcessing ? Color.gray : (camera.isStackingEnabled ? Color.orange : Color.white))
                        .frame(width: 75, height: 75)
                        .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 4))
                        .shadow(radius: 10)
                }.disabled(camera.isProcessing).padding(.bottom, 40)
            }
            
            if camera.isProcessing {
                ProcessingOverlay()
            }
        }
        .onAppear { camera.startSession() }
    }

    private func controlSlider(label: String, value: Binding<Float>, range: ClosedRange<Float>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label); Spacer(); Text(display).bold() }
            Slider(value: value, in: range).onChange(of: value.wrappedValue) { camera.applyManualSettings() }
        }.font(.caption)
    }

    private func controlSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label); Spacer(); Text(display).bold() }
            Slider(value: value, in: range).onChange(of: value.wrappedValue) { camera.applyManualSettings() }
        }.font(.caption)
    }
}

private func formatShutterSpeed(_ duration: Double) -> String {
    guard duration > 0.0001 else { return "1/max s" }
    return duration < 1.0 ? "1/\(Int(1.0 / duration))s" : String(format: "%.1fs", duration)
}

struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 15) {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.5)
                Text("Aligning & Stacking...").foregroundColor(.white).font(.headline)
                Text("Please keep phone still").font(.subheadline).foregroundColor(.white.opacity(0.7))
            }.padding(30).background(BlurView(style: .systemUltraThinMaterialDark)).cornerRadius(20)
        }
    }
}

// MARK: - UI Helpers

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.frame
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
