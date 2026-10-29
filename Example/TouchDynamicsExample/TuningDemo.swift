import SwiftUI
import TouchDynamics

/// Interactive effect tuning with a live preview card.
struct TuningDemo: View {
    @EnvironmentObject private var tuning: TuningStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PreviewCard()
                        .touchDynamics(tuning.configuration, clipShape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Preset") {
                    Picker("Preset", selection: $tuning.preset) {
                        ForEach(TuningStore.Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Illumination") {
                    Toggle("Enabled", isOn: $tuning.configuration.illumination.isEnabled)
                    LabeledSlider("Intensity", value: tuning.illuminationIntensity, in: 0...0.6, format: "%.2f")
                    LabeledSlider("Radius", value: tuning.illuminationRadius, in: 20...300, format: "%.0f pt")
                    LabeledSlider("Falloff", value: tuning.illuminationFalloff, in: 0.1...1, format: "%.2f")
                    Picker("Tracking", selection: trackingBinding) {
                        Text("Follow").tag(0)
                        Text("Anchored").tag(1)
                    }
                    Picker("Compositing", selection: $tuning.configuration.illumination.compositing) {
                        Text("Adaptive").tag(EffectCompositing.adaptive)
                        Text("Normal").tag(EffectCompositing.normal)
                        Text("Multiply").tag(EffectCompositing.multiply)
                        Text("Screen").tag(EffectCompositing.screen)
                    }
                    Picker("Placement", selection: $tuning.configuration.illumination.placement) {
                        Text("Automatic").tag(EffectPlacement.automatic)
                        Text("Above").tag(EffectPlacement.aboveContent)
                        Text("Beneath").tag(EffectPlacement.beneathContent)
                    }
                }

                Section("Ripple") {
                    Toggle("Enabled", isOn: $tuning.configuration.ripple.isEnabled)
                    LabeledSlider("Duration", value: tuning.rippleDuration, in: 0.15...0.8, format: "%.2f s")
                    LabeledSlider("Wavefront width", value: tuning.rippleWidth, in: 4...80, format: "%.0f pt")
                    LabeledSlider("Decay λ", value: tuning.rippleDecay, in: 0.5...6, format: "%.1f")
                    Picker("Profile", selection: $tuning.configuration.ripple.profile) {
                        Text("Combined").tag(RippleProfile.combined)
                        Text("Soft gradient").tag(RippleProfile.softGradient)
                        Text("Wavefront").tag(RippleProfile.wavefront)
                    }
                    Picker("Origin", selection: $tuning.configuration.ripple.origin) {
                        Text("Release").tag(RippleOrigin.releaseLocation)
                        Text("Initial touch").tag(RippleOrigin.initialLocation)
                    }
                }

                Section("Elasticity") {
                    Toggle("Enabled", isOn: $tuning.configuration.elasticity.isEnabled)
                    LabeledSlider("Strength", value: tuning.elasticityStrength, in: 0...0.1, format: "%.3f")
                    LabeledSlider("Tension", value: tuning.elasticityTension, in: 0...0.4, format: "%.2f")
                    LabeledSlider("Damping ζ", value: tuning.elasticityDamping, in: 0.1...1.5, format: "%.2f")
                    LabeledSlider("Stiffness", value: tuning.elasticityStiffness, in: 50...1000, format: "%.0f")
                    Picker("Mode", selection: $tuning.configuration.elasticity.mode) {
                        Text("Anchored scale").tag(DeformationMode.anchoredScale)
                        Text("Uniform scale").tag(DeformationMode.uniformScale)
                        Text("Shear").tag(DeformationMode.shear)
                    }
                    Picker("Response", selection: $tuning.configuration.elasticity.response) {
                        Text("Compress").tag(PressResponse.compress)
                        Text("Expand").tag(PressResponse.expand)
                    }
                }

                Section("Gesture") {
                    Picker("Drag", selection: $tuning.configuration.gesture.dragBehavior) {
                        Text("Follow").tag(DragBehavior.follow)
                        Text("Dissipate").tag(DragBehavior.dissipate)
                    }
                    Picker("Release after drag", selection: $tuning.configuration.gesture.releaseAfterDrag) {
                        Text("Ripple").tag(ReleaseBehavior.ripple)
                        Text("Dissipate").tag(ReleaseBehavior.dissipate)
                    }
                    Picker("Scroll takeover", selection: $tuning.configuration.gesture.scrollTakeover) {
                        Text("Maintain").tag(ScrollTakeoverBehavior.maintain)
                        Text("Dissipate").tag(ScrollTakeoverBehavior.dissipate)
                        Text("Suppress").tag(ScrollTakeoverBehavior.suppress)
                    }
                    Picker("Release after scroll", selection: $tuning.configuration.gesture.releaseAfterScroll) {
                        Text("Dissipate").tag(ReleaseBehavior.dissipate)
                        Text("Ripple").tag(ReleaseBehavior.ripple)
                    }
                }

                Section("Rendering") {
                    Picker("Renderer", selection: $tuning.configuration.rendering.renderer) {
                        Text("Automatic").tag(RendererSelection.automatic)
                        Text("Core Animation").tag(RendererSelection.coreAnimation)
                        Text("Metal").tag(RendererSelection.metal)
                    }
                    Picker("Frame rate", selection: $tuning.configuration.rendering.preferredFrameRate) {
                        Text("Maximum").tag(FrameRatePreference.maximum)
                        Text("60 Hz").tag(FrameRatePreference.standard)
                    }
                }

                Section("Accessibility") {
                    Toggle("Respect Reduce Motion", isOn: $tuning.configuration.accessibility.respectsReduceMotion)
                    Toggle("Respect Reduce Transparency", isOn: $tuning.configuration.accessibility.respectsReduceTransparency)
                    Toggle("No deformation under VoiceOver", isOn: $tuning.configuration.accessibility.disablesDeformationForVoiceOver)
                    LabeledContent("Reduce Motion now", value: UIAccessibility.isReduceMotionEnabled ? "On" : "Off")
                }
            }
            .navigationTitle("Tuning")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var trackingBinding: Binding<Int> {
        Binding(
            get: { tuning.configuration.illumination.tracking == .anchored ? 1 : 0 },
            set: { tuning.configuration.illumination.tracking = $0 == 1 ? .anchored : .follow }
        )
    }
}

struct LabeledSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let format: String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: String) {
        self.title = title
        self.value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}

struct PreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live preview").font(.headline)
            Text("Press anywhere on this card. Drag to feel the tension, hold for the long-press emphasis, and lift to see the ripple leave from under your finger.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(.secondarySystemBackground), Color(.tertiarySystemBackground)], startPoint: .top, endPoint: .bottom))
        )
    }
}
