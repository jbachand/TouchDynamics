import SwiftUI
import TouchDynamics

/// A comment list like the one the SDK was specified against: each row gets
/// its own effect, and scrolling is untouched.
struct CommentsDemo: View {
    @EnvironmentObject private var tuning: TuningStore
    @State private var liked: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Comment.samples) { comment in
                        CommentRow(comment: comment, isLiked: liked.contains(comment.id)) {
                            toggle(comment)
                        }
                        .modifier(ConditionalTouchDynamics(enabled: tuning.effectsEnabled, configuration: tuning.configuration))
                        .onTapGesture { toggle(comment) }
                    }
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func toggle(_ comment: Comment) {
        if liked.contains(comment.id) { liked.remove(comment.id) } else { liked.insert(comment.id) }
    }
}

struct CommentRow: View {
    let comment: Comment
    let isLiked: Bool
    let onLike: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
                .overlay(Text(String(comment.author.prefix(1)).uppercased()).font(.caption.bold()).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author).font(.subheadline.weight(.semibold))
                    Text("\(comment.minutesAgo)m").font(.caption).foregroundStyle(.secondary)
                }
                Text(comment.text).font(.subheadline)
                HStack(spacing: 16) {
                    Text("Reply").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text("\(comment.likes + (isLiked ? 1 : 0)) likes").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("likes")
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Button(action: onLike) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(isLiked ? .red : .secondary)
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Applies `touchDynamics` only when enabled (UI-test baseline support).
struct ConditionalTouchDynamics: ViewModifier {
    let enabled: Bool
    let configuration: TouchDynamicsConfiguration

    func body(content: Content) -> some View {
        if enabled {
            content.touchDynamics(configuration)
        } else {
            content
        }
    }
}
