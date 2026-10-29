import SwiftUI
import TouchDynamics

/// Sheets, navigation pushes (swipe back), nested horizontal scrolling inside
/// vertical scrolling, and a container-level surface.
struct ContainersDemo: View {
    @EnvironmentObject private var tuning: TuningStore
    @State private var showsSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button("Present a sheet") { showsSheet = true }
                        .buttonStyle(.borderedProminent)
                        .touchDynamics(tuning.configuration, clipShape: RoundedRectangle(cornerRadius: 8))

                    NavigationLink("Push a detail (swipe back works)") {
                        DetailScreen()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    .touchDynamics(tuning.configuration, clipShape: RoundedRectangle(cornerRadius: 12))

                    Text("Nested horizontal carousel").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<12) { i in
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(hue: Double(i) / 12, saturation: 0.45, brightness: 0.9))
                                    .frame(width: 140, height: 100)
                                    .overlay(Text("Tile \(i + 1)").font(.headline).foregroundStyle(.black.opacity(0.7)))
                                    .touchDynamics(tuning.configuration, clipShape: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    Text("Whole container as one surface").font(.headline)
                    VStack(spacing: 0) {
                        ForEach(0..<6) { i in
                            HStack {
                                Image(systemName: "circle.fill").font(.caption2).foregroundStyle(.tint)
                                Text("Row \(i + 1) shares the surface below").font(.subheadline)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            if i < 5 { Divider() }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .touchDynamics(.material, clipShape: RoundedRectangle(cornerRadius: 14))

                    Text("List").font(.headline)
                    List {
                        ForEach(Comment.samples.prefix(8)) { comment in
                            Text(comment.text)
                                .font(.subheadline)
                                .touchDynamics(tuning.configuration)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .frame(height: 420)
                    .scrollDisabled(false)
                }
                .padding()
            }
            .navigationTitle("Containers")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsSheet) {
                SheetScreen()
            }
        }
    }
}

struct SheetScreen: View {
    @EnvironmentObject private var tuning: TuningStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Comment.samples.prefix(20)) { comment in
                        CommentRow(comment: comment, isLiked: false) {}
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                            .touchDynamics(tuning.configuration, clipShape: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct DetailScreen: View {
    @EnvironmentObject private var tuning: TuningStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<10) { i in
                    Card(index: i)
                        .touchDynamics(tuning.configuration, clipShape: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding()
        }
        .navigationTitle("Detail")
    }
}
