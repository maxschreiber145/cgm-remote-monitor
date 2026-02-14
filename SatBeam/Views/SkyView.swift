import SwiftUI
import CoreLocation

/// A sky-view compass that shows the general direction of Globalstar satellites.
///
/// Globalstar orbits at ~1414 km altitude, 52 deg inclination, 8 orbital planes.
/// Rather than full SGP4 propagation (which needs TLE updates from the internet),
/// this view shows the optimal sky region for satellite visibility based on
/// the user's latitude. Globalstar satellites are most likely visible in the
/// band of sky corresponding to their 52-degree inclination orbit.
struct SkyView: View {

    @EnvironmentObject var location: LocationService

    @State private var heading: Double = 0
    private let headingProvider = HeadingProvider()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                // Sky dome
                ZStack {
                    // Background circle (sky)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.blue.opacity(0.15), .blue.opacity(0.05)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 140
                            )
                        )
                        .frame(width: 280, height: 280)

                    // Elevation rings
                    ForEach([30, 60, 90], id: \.self) { deg in
                        Circle()
                            .stroke(.secondary.opacity(0.2), lineWidth: 1)
                            .frame(
                                width: CGFloat(280 * (90 - deg)) / 90.0,
                                height: CGFloat(280 * (90 - deg)) / 90.0
                            )
                    }

                    // Cardinal directions (rotate opposite to heading so they stay fixed)
                    ForEach(cardinalDirections, id: \.label) { dir in
                        Text(dir.label)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .offset(y: -150)
                            .rotationEffect(.degrees(dir.angle - heading))
                    }

                    // Satellite visibility band
                    satelliteBand
                        .rotationEffect(.degrees(-heading))

                    // Crosshair at center (zenith)
                    crosshair
                }
                .frame(width: 300, height: 300)

                // Info below the compass
                VStack(spacing: 8) {
                    Text("SATELLITE VISIBILITY")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .tracking(2)

                    Text(visibilityDescription)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 20) {
                        infoChip(label: "LAT", value: String(format: "%.1f", location.latitude))
                        infoChip(label: "INCL", value: "52.0")
                        infoChip(label: "ALT", value: "1414 km")
                    }
                    .padding(.top, 4)
                }

                Spacer()

                Text("Point your phone toward the highlighted sky region.\nGlobalstar LEO orbits at 52\u{00B0} inclination.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
            }
            .padding()
            .navigationTitle("Sky")
            .onAppear {
                headingProvider.start { newHeading in
                    withAnimation(.linear(duration: 0.1)) {
                        heading = newHeading
                    }
                }
            }
            .onDisappear {
                headingProvider.stop()
            }
        }
    }

    // MARK: - Satellite Band

    /// Shows the band of sky where Globalstar satellites are most likely visible.
    /// For a user at latitude L, LEO satellites at inclination I pass through
    /// a band of sky roughly centered on the meridian at elevation angles
    /// that depend on the geometry.
    private var satelliteBand: some View {
        let lat = location.latitude
        let bestElevation = bestSatelliteElevation(userLat: lat)

        // Convert elevation to radius on the sky circle
        // Zenith = center, horizon = edge
        let radiusFraction = (90 - bestElevation) / 90.0
        let radius = 140 * radiusFraction

        return ZStack {
            // Glow band showing the satellite orbit track
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [.green.opacity(0.6), .green.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 30
                )
                .frame(width: radius * 2, height: radius * 0.6)
                .rotationEffect(.degrees(bestSatelliteAzimuthTilt(userLat: lat)))

            // Dot showing the highest-probability satellite position
            Circle()
                .fill(.green)
                .frame(width: 12, height: 12)
                .shadow(color: .green.opacity(0.8), radius: 6)
                .offset(y: -CGFloat(radius * 0.3))
        }
    }

    private var crosshair: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.5), lineWidth: 1)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 1, height: 16)
            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 16, height: 1)
        }
    }

    // MARK: - Calculations

    /// Best satellite elevation angle for a given user latitude.
    /// Globalstar at 52 deg inclination, 1414 km altitude.
    private func bestSatelliteElevation(userLat: Double) -> Double {
        let absLat = abs(userLat)
        let inclination = 52.0

        if absLat <= inclination {
            // User is within the inclination band — satellites pass nearly overhead
            // Best elevation decreases as you move toward the equator from 52 deg
            let overhead = max(90 - abs(absLat - inclination), 30)
            return min(overhead, 85)
        } else {
            // User is poleward of the inclination — satellites only reach lower elevations
            let gap = absLat - inclination
            return max(90 - gap * 2, 10)
        }
    }

    /// Tilt angle for the satellite band ellipse.
    private func bestSatelliteAzimuthTilt(userLat: Double) -> Double {
        // In the northern hemisphere, LEO orbits appear to tilt southward
        // In southern hemisphere, they tilt northward
        if userLat > 0 {
            return 20  // slight southern tilt
        } else if userLat < 0 {
            return -20
        }
        return 0
    }

    private var visibilityDescription: String {
        let lat = abs(location.latitude)
        if lat < 5 {
            return "Near equator — satellites visible in both N and S sky"
        } else if lat <= 52 {
            return "Good coverage — satellites pass nearly overhead"
        } else if lat <= 70 {
            return "Moderate coverage — look toward the equator"
        } else {
            return "Limited coverage — satellites are low on the horizon"
        }
    }

    private func infoChip(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var cardinalDirections: [(label: String, angle: Double)] {
        [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
    }
}

// MARK: - Compass Heading Provider

/// Wraps CLLocationManager's heading updates for the sky view compass.
final class HeadingProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var onUpdate: ((Double) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func start(onUpdate: @escaping (Double) -> Void) {
        self.onUpdate = onUpdate
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingHeading()
        onUpdate = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            onUpdate?(newHeading.magneticHeading)
        }
    }
}
