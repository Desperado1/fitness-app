import Foundation
import SwiftUI

/// The one control in voice mode. Three offset, blurred circles drift and
/// swell around a solid core; `level` scales them, so the shape tracks
/// whoever is talking — the client while listening, the coach while
/// speaking. That continuous deformation is the difference between a
/// screen that is waiting and one that is listening.
///
/// Motion comes from `TimelineView`, so there is no animation state to keep
/// in sync with the phase: the orb is a pure function of phase and level.
struct VoiceOrb: View {
    let phase: VoicePhase
    /// Live loudness, 0–1. Already smoothed by `VoiceSession`.
    var level: Double = 0
    /// Diameter of the solid core; everything else is derived from it, so
    /// one orb serves both the compact and the full-screen use.
    var size: CGFloat = 64
    var action: () -> Void

    /// Three is deliberate. `TimelineView` redraws every frame and blur is
    /// the expensive part, so more layers buy texture at a real frame cost.
    private static let blobCount = 3

    var body: some View {
        Button(action: action) {
            ZStack {
                halo
                core
            }
            .frame(width: size * 1.9, height: size * 1.9)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("voiceOrb")
    }

    private var halo: some View {
        // 30fps rather than display rate: blur is the expensive part and
        // nobody can see the difference on a drifting blob. Paused at idle,
        // which is both the honest state (nothing is happening yet, exactly
        // like Siri before you tap) and what keeps a redraw-every-frame view
        // from sitting under the UI tests' wait-for-idle.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: phase == .idle)) { context in
            let time = CGFloat(context.date.timeIntervalSinceReferenceDate)
            let energy: CGFloat = phase == .idle ? 0.12 : 0.3 + CGFloat(level) * 0.7
            let drift = size * 0.1 * (0.4 + energy)

            ZStack {
                ForEach(0..<Self.blobCount, id: \.self) { index in
                    let offset = CGFloat(index) * 2 * .pi / CGFloat(Self.blobCount)
                    Circle()
                        .fill(tint.opacity(0.3))
                        .frame(width: size, height: size)
                        .scaleEffect(1 + energy * (0.2 + 0.16 * sin(time * 1.7 + offset)))
                        .offset(
                            x: cos(time * 0.9 + offset) * drift,
                            y: sin(time * 1.1 + offset) * drift
                        )
                }
            }
            .blur(radius: size * 0.09)
        }
    }

    private var core: some View {
        ZStack {
            Circle()
                .fill(tint)
                .frame(width: size, height: size)

            if phase == .thinking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.appBackground)
                    .scaleEffect(max(1, size / 64))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(Color.appBackground)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
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
        case .speaking: return "Your coach is speaking — tap to cut in"
        }
    }
}

extension VoicePhase {
    /// One line under the orb telling the client what to do. Voice mode has
    /// no other affordances, so this is the whole instruction surface.
    var hint: String {
        switch self {
        case .idle: return "Tap to talk"
        case .listening: return "Listening — just stop when you're done"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking — tap to cut in"
        }
    }
}
