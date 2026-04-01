import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            
            ZStack {
                // 1. The Hard-Wired Camera Feed
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                
                // 2. Adaptive UI
                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
                
                if camera.isProcessing {
                    ProcessingOverlay()
                }
            }
        }
        .onAppear { camera.startSession() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Layouts
    
    private var portraitLayout: some View {
        VStack(spacing: 0) {
            topBar.padding(.top, 10)
            Spacer()
            if !camera.isProcessing {
                controlsMenu
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
            }
            shutterButton.padding(.bottom, 50)
        }
    }

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            VStack {
                topBar
                    .padding(.top, 10)
                Spacer()
            }
            .frame(width: 200)
            
            Spacer()
            
            if !camera.isProcessing {
                controlsMenu
                    .frame(width: 360)
                    .padding(.vertical, 40)
                    .contentShape(Rectangle())
            }
            shutterButton
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Subviews
    
    private var topBar: some View {
        HStack(spacing: 12) {
            Text("RAW").font(.system(size: 10, weight: .black)).padding(6)
                .background(camera.isRawSupported ? Color.yellow : Color.gray)
                .foregroundColor(.black).cornerRadius(5)
            Spacer()
            Button { camera.isStackingEnabled.toggle() } label: {
                Text("Stack").font(.system(size: 13, weight: .bold))
                    .foregroundColor(camera.isStackingEnabled ? .black : .white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(camera.isStackingEnabled ? Color.orange : Color.white.opacity(0.15))
                    .clipShape(Capsule())
            }.buttonStyle(.plain).fixedSize()
        }
        .padding(12).liquidGlass(cornerRadius: 16).padding(.horizontal)
    }

    private var controlsMenu: some View {
            VStack(spacing: 20) {
                if camera.isStackingEnabled {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Frames: \(camera.stackCount)").font(.headline)
                            Spacer()
                            Stepper("", value: $camera.stackCount, in: 2...30)
                                .labelsHidden()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }
                        Picker("Format", selection: $camera.saveAsJPEG) {
                            Text("TIFF").tag(false); Text("JPEG").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Divider().background(Color.white.opacity(0.1))
                }

                Toggle("Manual Exposure", isOn: $camera.isManualMode)
                    .onChange(of: camera.isManualMode) { camera.applyManualSettings() }
                    .font(.subheadline).bold()
                    .toggleStyle(SwitchToggleStyle(tint: .orange))

                if camera.isManualMode {
                    VStack(spacing: 25) {
                        controlSlider(label: "ISO", value: $camera.currentISO, range: camera.minISO...camera.maxISO, display: "\(Int(camera.currentISO))")
                        controlSlider(label: "Shutter", value: $camera.currentShutterSpeed, range: camera.minDuration...0.5, display: formatShutterSpeed(camera.currentShutterSpeed))
                    }
                }
            }
            .padding(24)
            .liquidGlass(cornerRadius: 32)
        }

    private var shutterButton: some View {
        Button(action: { camera.handleCapture() }) {
            ZStack {
                Circle().fill(camera.isProcessing ? .gray : (camera.isStackingEnabled ? .orange : .white)).frame(width: 76, height: 76)
                Circle().stroke(.white.opacity(0.4), lineWidth: 3).frame(width: 88, height: 88)
            }
        }.buttonStyle(.plain).shadow(color: .black.opacity(0.3), radius: 12)
    }

    private func controlSlider(label: String, value: Binding<Float>, range: ClosedRange<Float>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(label); Spacer(); Text(display).monospacedDigit().bold() }
            Slider(value: value, in: range)
                .tint(.orange)
                .onChange(of: value.wrappedValue) {
                    camera.applyManualSettings()
                }
        }.font(.caption)
    }

    private func controlSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(label); Spacer(); Text(display).monospacedDigit().bold() }
            Slider(value: value, in: range)
                .tint(.orange)
                .onChange(of: value.wrappedValue) {
                    camera.applyManualSettings()
                }
        }.font(.caption)
    }
}

// MARK: - Hard-Wired Rotation Fix

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.setupSession(session)
        return view
    }
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {}
}

class VideoPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    func setupSession(_ session: AVCaptureSession) {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        self.previewLayer = layer
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = self.bounds
        if let connection = previewLayer?.connection, let scene = self.window?.windowScene {
            let angle: CGFloat = {
                switch scene.interfaceOrientation {
                case .landscapeLeft: return 180
                case .landscapeRight: return 0
                case .portraitUpsideDown: return 270
                default: return 90
                }
            }()
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
        CATransaction.commit()
    }
}

// MARK: - UI Modifiers

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                BlurView(style: .systemUltraThinMaterialDark)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .clear, .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }
}

extension View { func liquidGlass(cornerRadius: CGFloat = 16) -> some View { self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius)) } }

struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 20) { ProgressView().tint(.white).scaleEffect(1.5); Text("Stacking...").font(.headline) }
            .padding(40).liquidGlass(cornerRadius: 24)
        }
    }
}

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView(effect: UIBlurEffect(style: style)) }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

private func formatShutterSpeed(_ duration: Double) -> String { duration < 1.0 ? "1/\(Int(1.0 / duration))s" : String(format: "%.1fs", duration) }
