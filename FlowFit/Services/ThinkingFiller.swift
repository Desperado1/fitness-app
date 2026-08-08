import Foundation

/// The short thing the coach says while the model is still answering.
///
/// A four-second gap with a spinner reads as a busy app; the same gap with
/// "got it, one sec" reads as someone thinking. It is the cheapest way to
/// buy back the round trip without touching latency at all.
struct ThinkingFiller {
    /// Deliberately short and non-committal. Anything longer collides with
    /// the real reply when it lands, and anything that pretends to have
    /// understood ("that sounds rough") is a guess — the model hasn't
    /// answered yet.
    static let phrases = [
        "Got it.",
        "Right.",
        "Mm-hm.",
        "Okay.",
        "Gotcha.",
        "Sure.",
        "Okay, one sec.",
        "Right, let me think.",
    ]

    private var lastIndex: Int?

    mutating func next() -> String {
        var index = Int.random(in: 0..<Self.phrases.count)
        if index == lastIndex {
            // Stepped rather than re-rolled: a re-roll can land on the same
            // phrase again, and hearing one twice running is the clearest
            // tell that these are canned.
            index = (index + 1) % Self.phrases.count
        }
        lastIndex = index
        return Self.phrases[index]
    }
}
