import SwiftUI

private typealias BookmarkPromptState<Value> = SwiftUI.State<Value>

struct BookmarkNamePrompt: View {
    let model: PlayerModel
    @BookmarkPromptState private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.12).contentShape(Rectangle())
                HStack(spacing: 14) {
                    Image(systemName: "bubble.and.pencil")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.8))
                        .accessibilityHidden(true)
                    TextField("Name this bookmark", text: $name)
                        .textFieldStyle(.plain).font(.system(size: 14))
                        .foregroundStyle(.white)
                        .focused($focused)
                        .onSubmit { model.finishBookmarkNaming(name) }
                        .accessibilityLabel("Name this bookmark")
                    Button { model.finishBookmarkNaming(name) } label: {
                        Text("Add").font(.system(size: 13, weight: .semibold))
                            .frame(minWidth: 48, minHeight: 26)
                    }
                    .buttonStyle(.borderedProminent).tint(.blue).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Add bookmark name")
                }
                .padding(12)
                .frame(width: min(520, max(0, geometry.size.width - 40)))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                .environment(\.colorScheme, .light)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear { focused = true }
        .onExitCommand { model.finishBookmarkNaming(nil) }
    }
}
