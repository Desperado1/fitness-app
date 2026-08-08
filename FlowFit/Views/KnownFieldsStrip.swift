import SwiftUI

/// Live view of what the check-in conversation has established. Unknown
/// fields stay dim, so it doubles as a progress indicator.
///
/// Shared by both check-in surfaces, and it is not decoration on either. A
/// bare orb with no feedback is unnerving — you cannot tell whether it heard
/// "no shoulder pain" or "shoulder pain". Watching fields land is the trust
/// mechanism, and it is what makes a misheard answer visible immediately and
/// correctable by hand.
struct KnownFieldsStrip: View {
    let checkIn: DailyCheckIn
    let knownFields: Set<CheckInField>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CheckInField.allCases, id: \.self) { field in
                    if let label = label(for: field) {
                        Chip(
                            label: label,
                            systemImage: symbol(for: field),
                            selected: knownFields.contains(field)
                        )
                        .accessibilityIdentifier("intakeChip-\(field.rawValue)")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .animation(.easeOut(duration: 0.2), value: knownFields)
        }
        .sensoryFeedback(.success, trigger: knownFields)
    }

    private func label(for field: CheckInField) -> String? {
        let known = knownFields.contains(field)
        switch field {
        case .energy:
            return known ? checkIn.energy.displayName : "Energy"
        case .venue:
            return known ? checkIn.venue.displayName : "Where"
        case .minutes:
            return known ? "\(checkIn.minutesAvailable) min" : "Time"
        case .style:
            return known ? (checkIn.preferredStyle?.displayName ?? "Coach's choice") : "Style"
        case .soreness:
            // Only worth a chip once there's something to show.
            return known ? checkIn.sorenessOrPain : nil
        case .mood:
            return nil
        }
    }

    private func symbol(for field: CheckInField) -> String {
        switch field {
        case .energy: return "bolt"
        case .venue: return checkIn.venue.symbol
        case .minutes: return "clock"
        case .style: return checkIn.preferredStyle?.symbol ?? "sparkles"
        case .soreness: return "bandage"
        case .mood: return "face.smiling"
        }
    }
}
