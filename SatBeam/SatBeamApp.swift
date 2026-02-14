import SwiftUI

@main
struct SatBeamApp: App {

    @StateObject private var store = RecordStore()
    @StateObject private var location = LocationService()
    @StateObject private var signal = SignalService()

    var body: some Scene {
        WindowGroup {
            TabView {
                RecordView()
                    .tabItem {
                        Label("Record", systemImage: "antenna.radiowaves.left.and.right")
                    }

                LogView()
                    .tabItem {
                        Label("Log", systemImage: "list.bullet")
                    }

                BeamMapView()
                    .tabItem {
                        Label("Map", systemImage: "map")
                    }

                SkyView()
                    .tabItem {
                        Label("Sky", systemImage: "scope")
                    }
            }
            .environmentObject(store)
            .environmentObject(location)
            .environmentObject(signal)
        }
    }
}
