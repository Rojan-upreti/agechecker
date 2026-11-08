import SwiftUI

struct ScanBackView: View {
    let model: AppModel
    @State private var scanner = BarcodeScanner()
    @State private var errorMessage: String?
    @State private var isTorchOn = false

    var body: some View {
        ZStack {
            AgeMarkPalette.cream.ignoresSafeArea()

            VStack(spacing: 20) {
                ScanCameraHeader(
                    step: model.fastMode ? "Back only" : "2 of 2",
                    title: "Scan ID Back",
                    isTorchOn: isTorchOn,
                    toggleTorch: {
                        isTorchOn.toggle()
                        scanner.setTorch(isTorchOn)
                    },
                    cancel: { model.screen = .home }
                )

                Spacer(minLength: 8)

                CameraFrame {
                    CameraPreview(session: scanner.session)
                }

                VStack(spacing: 8) {
                    Text("Place the barcode inside the frame")
                        .font(.title3.bold())
                        .foregroundStyle(AgeMarkPalette.navy)
                    Text(model.fastMode
                         ? "Center the PDF417 barcode. It scans automatically."
                         : "Flip the ID over, center the PDF417 barcode, and hold steady.")
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

                Spacer()

                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.black)
                    Text("Waiting for barcode")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.black.opacity(0.65))
                .padding(.horizontal, 18)
                .frame(minHeight: 52)
                .background(AgeMarkPalette.navy.opacity(0.06), in: Capsule())

                Text("Scans automatically • Nothing is uploaded")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.black.opacity(0.48))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            scanner.onCode = { model.barcodeCaptured($0) }
            scanner.onError = { errorMessage = $0 }
            scanner.start()
        }
        .onDisappear {
            scanner.stop()
        }
    }
}
