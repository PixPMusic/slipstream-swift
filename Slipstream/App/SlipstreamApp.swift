import SwiftUI

@main struct SlipstreamApp: App {
    #if os(iOS)
    @State private var model = AppModel.shared
    #else
    @State private var model = AppModel()
    #endif
    var body: some Scene {
        WindowGroup {
            ContentView().environment(model)
                .tint(.blue)
                .task {
                    await model.restoreSession()
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
