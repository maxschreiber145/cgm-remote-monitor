import Foundation
import CoreTelephony
import Network
import Combine

/// What type of network connection we detected.
enum ConnectionType: String, Codable {
    case satellite = "Satellite"
    case cellular  = "Cellular"
    case wifi      = "Wi-Fi"
    case none      = "None"
    case unknown   = "Unknown"
}

/// A single snapshot of signal / connectivity info.
struct SignalReading {
    let connectionType: ConnectionType
    let latencyMs: Double?          // round-trip to Apple's captive portal
    let satelliteName: String
    let radioAccessTechnology: String
    let carrierName: String?
    let bandInfo: String?
    let isSatellite: Bool
}

/// Reads connectivity info using only public iOS APIs.
///
/// What works in a sandboxed app:
///   - CoreTelephony: carrier name, radio access technology
///   - NWPathMonitor: connection type (wifi, cellular, satellite on iOS 18+)
///   - Latency probe: ping Apple's connectivity endpoint to measure RTT
///
/// What does NOT work (dropped from this version):
///   - Reading baseband logs (requires private entitlements)
///   - Sysctl radio metrics (sandboxed)
///   - CommCenter XPC (private framework)
final class SignalService: ObservableObject {

    @Published var currentReading: SignalReading?
    @Published var connectionType: ConnectionType = .unknown
    @Published var isMonitoring = false

    private let telephonyInfo = CTTelephonyNetworkInfo()
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "satbeam.signal", qos: .userInitiated)

    // NTN / satellite RAT strings that CoreTelephony might report
    private let satelliteRATs: Set<String> = [
        "CTRadioAccessTechnologyNRNSA",
        "CTRadioAccessTechnologyNR",
        "NTN",
        "CTRadioAccessTechnologySatellite"
    ]

    // MARK: - Lifecycle

    init() {
        startPathMonitor()
    }

    deinit {
        pathMonitor.cancel()
    }

    // MARK: - Public

    /// Take a measurement right now. Returns the reading and also publishes it.
    func capture() async -> SignalReading {
        let rat = detectRAT()
        let carrier = detectCarrier()
        let isSat = isSatelliteConnection(rat: rat, carrier: carrier)
        let satellite = detectSatelliteName(rat: rat, carrier: carrier)
        let band = detectBand(rat: rat, isSatellite: isSat)
        let latency = await measureLatency()

        let reading = SignalReading(
            connectionType: connectionType,
            latencyMs: latency,
            satelliteName: satellite,
            radioAccessTechnology: rat,
            carrierName: carrier,
            bandInfo: band,
            isSatellite: isSat
        )

        await MainActor.run {
            self.currentReading = reading
        }

        return reading
    }

    /// Synchronous capture for quick UI updates (no latency measurement).
    func captureQuick() -> SignalReading {
        let rat = detectRAT()
        let carrier = detectCarrier()
        let isSat = isSatelliteConnection(rat: rat, carrier: carrier)
        let satellite = detectSatelliteName(rat: rat, carrier: carrier)
        let band = detectBand(rat: rat, isSatellite: isSat)

        let reading = SignalReading(
            connectionType: connectionType,
            latencyMs: nil,
            satelliteName: satellite,
            radioAccessTechnology: rat,
            carrierName: carrier,
            bandInfo: band,
            isSatellite: isSat
        )

        DispatchQueue.main.async {
            self.currentReading = reading
        }

        return reading
    }

    // MARK: - CoreTelephony (public API — works in sandbox)

    private func detectRAT() -> String {
        guard let ratMap = telephonyInfo.serviceCurrentRadioAccessTechnology else {
            return "No Service"
        }

        // Look for NTN/satellite RAT
        for (_, rat) in ratMap {
            if satelliteRATs.contains(rat) {
                return rat.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
            }
        }

        // Return whatever RAT is active
        if let first = ratMap.values.first {
            return first.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
        }

        return "No Service"
    }

    private func detectCarrier() -> String? {
        guard let providers = telephonyInfo.serviceSubscriberCellularProviders else {
            return nil
        }

        // Check for satellite carriers
        for (_, carrier) in providers {
            if let name = carrier.carrierName {
                let lower = name.lowercased()
                if lower.contains("globalstar") ||
                   lower.contains("satellite") ||
                   lower.contains("spacemobile") {
                    return name
                }
            }
        }

        return providers.values.first?.carrierName
    }

    private func isSatelliteConnection(rat: String, carrier: String?) -> Bool {
        if satelliteRATs.contains("CTRadioAccessTechnology\(rat)") {
            return true
        }
        if let c = carrier?.lowercased() {
            return c.contains("globalstar") || c.contains("satellite")
        }
        // NWPathMonitor detection
        return connectionType == .satellite
    }

    private func detectSatelliteName(rat: String, carrier: String?) -> String {
        if let c = carrier?.lowercased() {
            if c.contains("globalstar") { return "Globalstar" }
            if c.contains("iridium")    { return "Iridium" }
        }
        if isSatelliteConnection(rat: rat, carrier: carrier) {
            return "NTN Satellite"
        }
        return connectionType == .satellite ? "Satellite" : "—"
    }

    private func detectBand(rat: String, isSatellite: Bool) -> String? {
        if isSatellite {
            return "n53 (Globalstar L/S)"
        }
        return nil
    }

    // MARK: - NWPathMonitor (public API — works in sandbox)

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let type: ConnectionType

            if path.status != .satisfied {
                type = .none
            } else if path.usesInterfaceType(.wifi) {
                type = .wifi
            } else if path.usesInterfaceType(.cellular) {
                // Check if any interface looks like satellite
                let hasSat = path.availableInterfaces.contains { iface in
                    iface.type == .other && iface.name.lowercased().contains("sat")
                }
                type = hasSat ? .satellite : .cellular
            } else {
                // .other could be satellite on iOS 18+
                let hasSat = path.availableInterfaces.contains { iface in
                    iface.name.lowercased().contains("sat")
                }
                type = hasSat ? .satellite : .unknown
            }

            DispatchQueue.main.async {
                self?.connectionType = type
                self?.isMonitoring = true
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - Latency Probe (works in sandbox)

    /// Measure round-trip latency to Apple's captive portal check.
    /// This is a good proxy for link quality:
    ///   - Wi-Fi: ~5-30 ms
    ///   - Cellular: ~30-100 ms
    ///   - Satellite: ~600-2500 ms (LEO Globalstar)
    private func measureLatency() async -> Double? {
        let url = URL(string: "https://captive.apple.com/hotspot-detect.html")!
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000 // ms

            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return elapsed
            }
            return elapsed // return even if status != 200
        } catch {
            return nil
        }
    }
}
