import SwiftUI
import TouchDynamics

@main
struct TouchDynamicsExampleApp: App {
    @StateObject private var tuning = TuningStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                CommentsDemo()
                    .tabItem { Label("Comments", systemImage: "text.bubble") }
                ControlsDemo()
                    .tabItem { Label("Controls", systemImage: "square.grid.2x2") }
                UIKitDemo()
                    .tabItem { Label("UIKit", systemImage: "list.bullet.rectangle") }
                ContainersDemo()
                    .tabItem { Label("Containers", systemImage: "rectangle.stack") }
                TuningDemo()
                    .tabItem { Label("Tuning", systemImage: "slider.horizontal.3") }
            }
            .environmentObject(tuning)
        }
    }
}
