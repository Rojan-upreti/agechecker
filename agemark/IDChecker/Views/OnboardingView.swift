import SwiftUI

enum OnboardingStep: Int {
    case welcome
    case scanMode
    case ageThreshold
}

struct AgeMarkSplashView: View {
    @State private var logoScale = 0.72
    @State private var logoOpacity = 0.15
    @State private var glowOpacity = 0.0
    @State private var particlesExpanded = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? AgeMarkPalette.teal.opacity(0.7) : AgeMarkPalette.navy.opacity(0.14))
                    .frame(width: CGFloat(6 + index % 4 * 3))
                    .offset(
                        x: particlesExpanded ? cos(Double(index) * .pi / 6) * 190 : 0,
                        y: particlesExpanded ? sin(Double(index) * .pi / 6) * 190 : 0
                    )
                    .opacity(particlesExpanded ? 0 : 0.9)
                    .animation(.easeOut(duration: 2.2).delay(Double(index) * 0.035), value: particlesExpanded)
            }

            Circle()
                .fill(AgeMarkPalette.teal.opacity(0.17))
                .frame(width: 310, height: 310)
                .blur(radius: 32)
                .opacity(glowOpacity)

            VStack(spacing: 22) {
                Image("AgeMarkLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 230, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 48))
                    .shadow(color: AgeMarkPalette.teal.opacity(0.28), radius: 28)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                Text("AgeMark")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.black)
                    .opacity(logoOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.72)) {
                logoScale = 1
                logoOpacity = 1
                glowOpacity = 1
            }
            particlesExpanded = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AgeMark")
    }
}

struct OnboardingView: View {
    let initialFastMode: Bool
    let initialThreshold: Int
    let onComplete: (Bool, Int) -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var fastMode: Bool
    @State private var threshold: Int
    @State private var animateBackground = false

    init(initialFastMode: Bool, initialThreshold: Int, onComplete: @escaping (Bool, Int) -> Void) {
        self.initialFastMode = initialFastMode
        self.initialThreshold = initialThreshold
        self.onComplete = onComplete
        _fastMode = State(initialValue: initialFastMode)
        _threshold = State(initialValue: initialThreshold)
    }

    var body: some View {
        ZStack {
            AnimatedWelcomeBackground(isAnimating: animateBackground)
            VStack(spacing: 26) {
                OnboardingBrandHeader()
                Spacer()
                switch step {
                case .welcome:
                    WelcomeStep {
                        withAnimation(.snappy) { step = .scanMode }
                    }
                case .scanMode:
                    ScanModeStep(fastMode: $fastMode) {
                        withAnimation(.snappy) { step = .ageThreshold }
                    }
                case .ageThreshold:
                    AgeThresholdStep(threshold: $threshold) {
                        onComplete(fastMode, threshold)
                    }
                }
                Spacer()
                OnboardingProgress(step: step)
            }
            .padding(24)
        }
        .onAppear { animateBackground = true }
        .preferredColorScheme(.dark)
    }
}

private struct AnimatedWelcomeBackground: View {
    let isAnimating: Bool

    var body: some View {
        ZStack {
            AgeMarkPalette.navy.ignoresSafeArea()
            Circle()
                .fill(AgeMarkPalette.teal.opacity(0.28))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: isAnimating ? 145 : -150, y: isAnimating ? -260 : -80)
                .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: isAnimating)
            Circle()
                .fill(Color.blue.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: isAnimating ? -150 : 120, y: isAnimating ? 300 : 120)
                .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: isAnimating)
            LinearGradient(
                colors: [.clear, AgeMarkPalette.teal.opacity(0.08), .clear],
                startPoint: isAnimating ? .topLeading : .bottomTrailing,
                endPoint: isAnimating ? .bottomTrailing : .topLeading
            )
            .animation(.linear(duration: 4).repeatForever(autoreverses: true), value: isAnimating)
            .ignoresSafeArea()
        }
    }
}

private struct OnboardingBrandHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("AgeMarkLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("AgeMark")
                .font(.title.bold())
            Spacer()
        }
    }
}

private struct WelcomeStep: View {
    let continueAction: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Text("Welcome to AgeMark")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Fast, private, on-device age verification for responsible businesses.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Set Up AgeMark", action: continueAction)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 60)
                .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.teal))
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

private struct ScanModeStep: View {
    @Binding var fastMode: Bool
    let continueAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("How should IDs be checked?")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            ChoiceCard(
                title: "Back Barcode Only",
                subtitle: "Fast 1–2 second PDF417 scan for high-volume service.",
                systemImage: "barcode.viewfinder",
                isSelected: fastMode
            ) { fastMode = true }
            ChoiceCard(
                title: "Both Sides",
                subtitle: "Capture the front, read the back barcode, and compare key fields.",
                systemImage: "rectangle.on.rectangle.angled",
                isSelected: !fastMode
            ) { fastMode = false }
            Button("Continue", action: continueAction)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 60)
                .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.teal))
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

private struct AgeThresholdStep: View {
    @Binding var threshold: Int
    let completeAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("What age should AgeMark verify?")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("You can change this later in Settings.")
                .foregroundStyle(.secondary)
            ChoiceCard(
                title: "21 or Older",
                subtitle: "Standard US alcohol-service age check.",
                systemImage: "21.circle.fill",
                isSelected: threshold == 21
            ) { threshold = 21 }
            ChoiceCard(
                title: "28 or Older",
                subtitle: "Custom higher age threshold for your venue policy.",
                systemImage: "checkmark.shield.fill",
                isSelected: threshold == 28
            ) { threshold = 28 }
            Button("Finish Setup", action: completeAction)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 60)
                .buttonStyle(PrimaryButtonStyle(color: AgeMarkPalette.teal))
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

private struct ChoiceCard: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(isSelected ? .white : AgeMarkPalette.teal)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(isSelected ? .black.opacity(0.72) : .secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }
            .foregroundStyle(isSelected ? .black : .white)
            .padding(18)
            .background(isSelected ? AgeMarkPalette.teal : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingProgress: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= step.rawValue ? AgeMarkPalette.teal : Color.white.opacity(0.2))
                    .frame(width: index == step.rawValue ? 30 : 10, height: 8)
            }
        }
        .animation(.snappy, value: step)
        .accessibilityLabel("Setup step \(step.rawValue + 1) of 3")
    }
}
