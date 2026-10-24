import SwiftUI

private typealias BookmarkPromptState<Value> = SwiftUI.State<Value>

struct BookmarkNamePrompt: View {
    let model: PlayerModel
    @BookmarkPromptState private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.12).contentShape(Rectangle())
            VStack(alignment: .leading, spacing: 12) {
                Text("Name Bookmark").font(.headline)
                TextField("Bookmark name", text: $name)
                    .textFieldStyle(.roundedBorder).focused($focused)
                    .onSubmit { model.finishBookmarkNaming(name) }
                    .accessibilityLabel("Bookmark name")
                HStack {
                    Text("Leave empty to keep the saved bookmark.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { model.finishBookmarkNaming(nil) }.keyboardShortcut(.cancelAction)
                    Button("Save") { model.finishBookmarkNaming(name) }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(18).frame(width: 360)
            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18)))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        }
        .onAppear { focused = true }
        .onExitCommand { model.finishBookmarkNaming(nil) }
    }
}
