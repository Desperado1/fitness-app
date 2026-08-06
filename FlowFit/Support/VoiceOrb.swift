import SwiftUI

/// The one control in voice mode. It shows which phase the loop is in
/// without any text, so the client can glance rather than read — and tap
/// it to drop out of voice mode entirely.
struct VoiceOrb: View {
    let phase: VoicePhase
    var action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Breathing halo while listening, so a live microphone is
                // never ambiguous.
                Circle()
                    .fill(tint.opacity(0.25))
                    .frame(width: 84, height: 84)
                    .scaleEffect(pulse && phase.isPulsing ? 1.18 : 0.92)
                    .opacity(phase.isPulsing ? 1 : 0)

                Circle()
                    .fill(tint)
                    .frame(width: 64, height: 64)

                if case .thinking = phase {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.appBackground)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.appBackground)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("voiceOrb")
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .animation(.easeOut(duration: 0.2), value: phase.isPulsing)
    }

    private var symbol: String {
        switch phase {
        case .idle: return "mic.fill"
        case .listening: return "waveform"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    private var tint: Color {
        switch phase {
        case .idle: return Color.appIconInactive
        case .listening, .thinking, .speaking: return Color.appAccent
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle: return "Start talking to your coach"
        case .listening: return "Listening"
        case .thinking: return "Your coach is thinking"
        case .speaking: return "Your coach is speaking"
        }
    }
}

extension VoicePhase {
    /// Listening and speaking both animate; idle and thinking don't (the
    /// thinking state has its own spinner).
    var isPulsing: Bool {
        switch self {
        case .listening, .speaking: return true
        case .idle, .thinking: return false
        }
    }

    /// One line under the orb telling the client what to do. Voice mode has
    /// no other affordances, so this is the whole instruction surface.
    var hint: String {
        switch self {
        case .idle: return "Tap to talk"
        case .listening: return "Listening — just stop when you're done"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        }
    }
}
