import SwiftUI

struct ScanFrontView: View {
    let model: AppModel
    @State private var camera = FrontCaptureService()
    @State private var isTorchOn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AgeMarkPalette.cream.ignoresSafeArea()

            VStack(spacing: 20) {
                ScanCameraHeader(
                    step: "1 of 2",
                    title: "Scan ID Front",
                    isTorchOn: isTorchOn,
                    toggleTorch: {
                        isTorchOn.toggle()
                        camera.setTorch(isTorchOn)
                    },
                    cancel: { model.cancelScan() }
                )

                Spacer(minLength: 8)

                CameraFrame {
                    CameraPreview(session: camera.session)
                }

                VStack(spacing: 8) {
                    Text("Place the front of the ID inside the frame")
                        .font(.title3.bold())
                        .foregroundStyle(AgeMarkPalette.navy)
                    Text("Keep all four edges visible and hold steady. AgeMark captures automatically, or you can use the shutter.")
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.62))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer(minLength: 8)

                Button {
                    camera.captureNow()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AgeMarkPalette.navy)
                            .frame(width: 76, height: 76)
                        Circle()
                            .stroke(.white, lineWidth: 3)
                            .frame(width: 64, height: 64)
                    }
                }
                .accessibilityLabel("Capture ID front")
                .accessibilityHint("Takes a photo of the ID inside the frame")

                Text("Nothing is uploaded or saved")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.black.opacity(0.48))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            camera.onCapture = { model.frontCaptured($0) }
            camera.onError = { errorMessage = $0 }
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
    }
}

struct ScanCameraHeader: View {
    let step: String
    let title: String
    let isTorchOn: Bool
    let toggleTorch: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 48, height: 48)
                    .background(AgeMarkPalette.navy.opacity(0.07), in: Circle())
            }
            .foregroundStyle(AgeMarkPalette.navy)
            .accessibilityLabel("Cancel scan")

            VStack(alignment: .leading, spacing: 2) {
                Text(step)
                    .font(.caption.bold())
                    .foregroundStyle(AgeMarkPalette.navy.opacity(0.5))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AgeMarkPalette.navy)
            }

            Spacer()

            Button(action: toggleTorch) {
                Image(systemName: isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.headline)
                    .frame(width: 48, height: 48)
                    .foregroundStyle(.white)
                    .background(isTorchOn ? AgeMarkPalette.amber : AgeMarkPalette.navy, in: Circle())
            }
            .accessibilityLabel(isTorchOn ? "Turn flash off" : "Turn flash on")
        }
    }
}

struct CameraFrame<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AgeMarkPalette.navy
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(maxWidth: 520)
        .aspectRatio(1.586, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(AgeMarkPalette.navy.opacity(0.88), lineWidth: 3)
        }
        .padding(.horizontal, 4)
        .shadow(color: .black.opacity(0.14), radius: 14, y: 7)
    }
}
