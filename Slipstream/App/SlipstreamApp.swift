import SwiftUI

@main struct SlipstreamApp: App {
    @State private var model = AppModel()
    @State private var startedSessionRestore = false
    var body: some Scene {
        WindowGroup {
            ContentView().environment(model)
                .tint(.blue)
                .task {
                    guard !startedSessionRestore else { return }
                    startedSessionRestore = true
                    await model.restore()
                }
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 580)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1220, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            #if DEBUG
            CommandMenu("Developer") {
                Toggle("Chat preview", isOn: $model.chatPreview)
            }
            #endif
        }
        #endif
    }
}
