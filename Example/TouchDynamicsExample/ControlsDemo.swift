import SwiftUI
import TouchDynamics

/// Buttons, cards and toggles. Buttons keep firing; cards show clipping.
struct ControlsDemo: View {
    @EnvironmentObject private var tuning: TuningStore
    @State private var taps = 0
    @State private var isOn = true
    @State private var selection = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Buttons fire normally; the effect is purely visual.")
                        .font(.footnote).foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button("Tapped \(taps)×") { taps += 1 }
                            .buttonStyle(.borderedProminent)
                            .touchDynamics(tuning.configuration, clipShape: RoundedRectangle(cornerRadius: 8))
                        Button("Plain") { taps += 1 }
                            .buttonStyle(.bordered)
                            .touchDynamics(tuning.configuration, clipShape: RoundedRectangle(cornerRadius: 8))
                        Button {
                            taps += 1
                        } label: {
                            Image(systemName: "paperplane.fill").padding(10)
                        }
                        .background(Circle().fill(.tint))
                        .foregroundStyle(.white)
                        .touchDynamics(tuning.configuration, clipShape: Circle())
                    }

                    Text("Cards").font(.headline)
                    ForEach(0..<3) { i in
                        Card(index: i)
                            .touchDynamics(tuning.configuration, clipShape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    Text("Capsules").font(.headline)
                    HStack {
                        ForEach(["Following", "For you", "Live"], id: \.self) { title in
                            Text(title)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                                .touchDynamics(tuning.configuration, clipShape: Capsule())
                        }
                    }

                    Text("Form rows").font(.headline)
                    VStack(spacing: 0) {
                        Toggle("Notifications", isOn: $isOn)
                            .padding()
                            .touchDynamics(tuning.configuration)
                        Divider()
                        Picker("Mode", selection: $selection) {
                            Text("Light").tag(0)
                            Text("Dark").tag(1)
                            Text("Auto").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding()
                        .touchDynamics(tuning.configuration)
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                }
                .padding()
            }
            .navigationTitle("Controls")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct Card: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: ["sparkles", "waveform", "circle.hexagongrid"][index % 3])
                    .font(.title2)
                Spacer()
                Text("Card \(index + 1)").font(.caption).foregroundStyle(.secondary)
            }
            Text(["Illumination", "Release ripple", "Elastic deformation"][index % 3])
                .font(.title3.weight(.semibold))
            Text("Press, hold, drag and release. The ripple fills the card from where you let go; the card springs back without a layout pass.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(.secondarySystemBackground), Color(.tertiarySystemBackground)], startPoint: .top, endPoint: .bottom))
        )
    }
}
