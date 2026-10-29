import SwiftUI
import TouchDynamics

/// The configuration every demo reads, editable from the Tuning tab.
@MainActor
final class TuningStore: ObservableObject {
    enum Preset: String, CaseIterable, Identifiable {
        case subtle, fluid, elastic, material, rippleOnly
        var id: String { rawValue }

        var configuration: TouchDynamicsConfiguration {
            switch self {
            case .subtle: return .subtle
            case .fluid: return .fluid
            case .elastic: return .elastic
            case .material: return .material
            case .rippleOnly: return .rippleOnly
            }
        }
    }

    @Published var preset: Preset = .fluid {
        didSet { configuration = preset.configuration }
    }
    @Published var configuration: TouchDynamicsConfiguration = .fluid

    var illuminationIntensity: Binding<Double> {
        Binding(
            get: { Double(self.configuration.illumination.intensity) },
            set: { self.configuration.illumination.intensity = CGFloat($0) }
        )
    }
    var illuminationRadius: Binding<Double> {
        Binding(
            get: { Double(self.configuration.illumination.radius) },
            set: { self.configuration.illumination.radius = CGFloat($0) }
        )
    }
    var illuminationFalloff: Binding<Double> {
        Binding(
            get: { Double(self.configuration.illumination.falloff) },
            set: { self.configuration.illumination.falloff = CGFloat($0) }
        )
    }
    var rippleDuration: Binding<Double> {
        Binding(
            get: { self.configuration.ripple.duration },
            set: { self.configuration.ripple.duration = $0 }
        )
    }
    var rippleWidth: Binding<Double> {
        Binding(
            get: { Double(self.configuration.ripple.wavefrontWidth) },
            set: { self.configuration.ripple.wavefrontWidth = CGFloat($0) }
        )
    }
    var rippleDecay: Binding<Double> {
        Binding(
            get: { self.configuration.ripple.decay },
            set: { self.configuration.ripple.decay = $0 }
        )
    }
    var elasticityStrength: Binding<Double> {
        Binding(
            get: { Double(self.configuration.elasticity.strength) },
            set: { self.configuration.elasticity.strength = CGFloat($0) }
        )
    }
    var elasticityTension: Binding<Double> {
        Binding(
            get: { Double(self.configuration.elasticity.tension) },
            set: { self.configuration.elasticity.tension = CGFloat($0) }
        )
    }
    var elasticityDamping: Binding<Double> {
        Binding(
            get: { self.configuration.elasticity.damping },
            set: { self.configuration.elasticity.damping = $0 }
        )
    }
    var elasticityStiffness: Binding<Double> {
        Binding(
            get: { self.configuration.elasticity.stiffness },
            set: { self.configuration.elasticity.stiffness = $0 }
        )
    }
}

struct Comment: Identifiable {
    let id = UUID()
    let author: String
    let text: String
    let likes: Int
    let minutesAgo: Int

    static let samples: [Comment] = {
        let authors = ["mira.k", "devon_r", "sol.ortega", "pixelpat", "nnamdi", "jules.ff", "kaya", "tomo", "ren_", "ivy.builds"]
        let texts = [
            "This is exactly the kind of micro-interaction that makes an app feel alive.",
            "The ripple should start where my finger is, not in the middle. Looks like it does 👌",
            "Does it still scroll fine? Trying it in a long list.",
            "Long press holds the glow. Nice touch.",
            "Can we get this on the buttons too?",
            "Subtle compression on press reads really well on dark mode.",
            "Swipe back still works, no gesture fights at all.",
            "Reduce Motion gives a static highlight, confirmed on my device.",
            "Rapid taps don't pile up, that was my worry.",
            "Elastic preset is a bit much for comments but great for cards.",
        ]
        return (0..<60).map { i in
            Comment(author: authors[i % authors.count], text: texts[i % texts.count], likes: (i * 37) % 240, minutesAgo: i * 3 + 1)
        }
    }()
}
