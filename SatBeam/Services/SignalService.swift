import Foundation
import CoreTelephony
import Network
import Combine

/// Reading captured from the satellite radio at a single point in time.
struct SignalReading {
    let rsrp: Double?
    let rsrq: Double?
    let sinr: Double?
    let rawSignalStrength: Double?
    let satelliteName: String
    let radioAccessTechnology: String
    let carrierName: String?
    let bandInfo: String?
}

/// Reads satellite signal metrics from the iPhone's baseband.
///
/// Strategy (layered, most-to-least reliable):
///   1. CoreTelephony public API — detect NTN RAT, carrier name
///   2. Process-level signal cache — parse last-known metrics from system logs
///   3. Private framework bridge — if available, call into CommCenter XPC
///
/// The service exposes a single `capture()` async call that returns whatever
/// the best available reading is at that moment.
final class SignalService: ObservableObject {

    @Published var currentReading: SignalReading?
    @Published var isMonitoring = false

    private let telephonyInfo = CTTelephonyNetworkInfo()
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "satbeam.signal", qos: .userInitiated)

    private var hasSatelliteInterface = false

    // Known NTN / satellite RAT identifiers
    // 3GPP Release 17 defines NTN. Apple may report these in future iOS versions.
    private let satelliteRATs: Set<String> = [
        "CTRadioAccessTechnologyNRNSA",  // could carry NTN on NR
        "CTRadioAccessTechnologyNR",
        "NTN",                           // hypothetical future value
        "CTRadioAccessTechnologySatellite"
    ]

    // MARK: - Public

    init() {
        startMonitoring()
    }

    deinit {
        pathMonitor.cancel()
    }

    /// Capture a single reading right now.
    func capture() -> SignalReading {
        let rat = detectRAT()
        let carrier = detectCarrier()
        let satellite = detectSatelliteName(rat: rat, carrier: carrier)
        let band = detectBand(rat: rat)
        let metrics = readSignalMetrics()

        let reading = SignalReading(
            rsrp: metrics.rsrp,
            rsrq: metrics.rsrq,
            sinr: metrics.sinr,
            rawSignalStrength: metrics.rssi,
            satelliteName: satellite,
            radioAccessTechnology: rat,
            carrierName: carrier,
            bandInfo: band
        )

        DispatchQueue.main.async {
            self.currentReading = reading
        }

        return reading
    }

    // MARK: - Layer 1: CoreTelephony (public API)

    private func detectRAT() -> String {
        // serviceCurrentRadioAccessTechnology returns [serviceId: RAT]
        // On iPhone 14+ with satellite, there may be a service for the NTN modem.
        guard let ratMap = telephonyInfo.serviceCurrentRadioAccessTechnology else {
            return "Unknown"
        }

        // Look for a satellite/NTN RAT first
        for (_, rat) in ratMap {
            if satelliteRATs.contains(rat) {
                return rat
            }
        }

        // Fall back to whatever RAT is active
        // Strip the "CTRadioAccessTechnology" prefix for readability
        if let first = ratMap.values.first {
            return first.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
        }

        return "Unknown"
    }

    private func detectCarrier() -> String? {
        guard let providers = telephonyInfo.serviceSubscriberCellularProviders else {
            return nil
        }
        // Globalstar satellite service might appear as a separate carrier
        for (_, carrier) in providers {
            if let name = carrier.carrierName {
                // Globalstar, Iridium, AST SpaceMobile, etc.
                if name.lowercased().contains("globalstar") ||
                   name.lowercased().contains("satellite") ||
                   name.lowercased().contains("spacemobile") {
                    return name
                }
            }
        }
        return providers.values.first?.carrierName
    }

    private func detectSatelliteName(rat: String, carrier: String?) -> String {
        // If we detected an NTN RAT or Globalstar carrier, we know the constellation.
        // Individual satellite ID (e.g. FM15) requires either:
        //   - Baseband logs (has satellite PRN/ID)
        //   - TLE-based prediction (which sat is overhead right now)
        if let c = carrier?.lowercased() {
            if c.contains("globalstar") { return "Globalstar" }
            if c.contains("iridium")    { return "Iridium" }
        }

        if satelliteRATs.contains(rat) {
            return "NTN Satellite"
        }

        // Fallback: predict from TLE data which Globalstar sat is overhead
        // This would use SGP4 propagation — placeholder for now
        return predictOverheadSatellite() ?? "Unknown"
    }

    private func detectBand(rat: String) -> String? {
        // Globalstar uses Band 53 (n53) for NTN
        // This is the only satellite band currently used by iPhone
        if rat.contains("NR") || satelliteRATs.contains(rat) {
            return "n53 (Globalstar L/S-band)"
        }
        return nil
    }

    // MARK: - Layer 2: Signal Metrics

    private struct RawMetrics {
        var rsrp: Double?
        var rsrq: Double?
        var sinr: Double?
        var rssi: Double?
    }

    private func readSignalMetrics() -> RawMetrics {
        var metrics = RawMetrics()

        // Approach A: Query system for signal strength
        // iOS does not expose dBm through public API for satellite.
        // We attempt to read from the baseband log cache.
        metrics = readFromBasebandCache() ?? metrics

        // Approach B: If we got nothing, try the sysctl interface
        if metrics.rsrp == nil && metrics.rssi == nil {
            metrics = readFromSysctl() ?? metrics
        }

        return metrics
    }

    /// Attempt to read cached baseband metrics from the system log directory.
    /// After any satellite session, the baseband writes radio metrics to:
    ///   /var/mobile/Library/Logs/CrashReporter/Baseband/
    /// This requires the app to have appropriate entitlements or run on
    /// a development device.
    private func readFromBasebandCache() -> RawMetrics? {
        // File paths where baseband may cache signal info
        let paths = [
            "/var/mobile/Library/Logs/CrashReporter/Baseband",
            "/var/mobile/Library/Logs/Baseband"
        ]

        for basePath in paths {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: basePath) else {
                continue
            }

            // Find most recent baseband log
            let sorted = files
                .filter { $0.hasSuffix(".log") || $0.hasSuffix(".plist") || $0.hasSuffix(".txt") }
                .sorted()

            guard let latest = sorted.last,
                  let data = FileManager.default.contents(atPath: "\(basePath)/\(latest)"),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            return parseBasebandLog(content)
        }

        return nil
    }

    /// Parse baseband log content for NTN signal metrics.
    private func parseBasebandLog(_ content: String) -> RawMetrics? {
        var metrics = RawMetrics()

        let patterns: [(key: WritableKeyPath<RawMetrics, Double?>, regex: String)] = [
            (\.rsrp, #"(?:NTN_)?RSRP[:\s=]+(-?\d+\.?\d*)"#),
            (\.rsrq, #"(?:NTN_)?RSRQ[:\s=]+(-?\d+\.?\d*)"#),
            (\.sinr, #"(?:NTN_)?SINR[:\s=]+(-?\d+\.?\d*)"#),
            (\.rssi, #"(?:NTN_)?RSSI[:\s=]+(-?\d+\.?\d*)"#),
        ]

        for (keyPath, pattern) in patterns {
            if let match = content.range(of: pattern, options: .regularExpression) {
                let matched = String(content[match])
                // Extract the numeric value
                if let numRange = matched.range(of: #"-?\d+\.?\d*$"#, options: .regularExpression) {
                    metrics[keyPath: keyPath] = Double(matched[numRange])
                }
            }
        }

        guard metrics.rsrp != nil || metrics.rssi != nil else { return nil }
        return metrics
    }

    /// Fallback: try sysctl or IOKit for radio metrics.
    /// This is a best-effort attempt — most values are sandboxed on stock iOS.
    private func readFromSysctl() -> RawMetrics? {
        // On stock iOS, this returns nil. On jailbroken or entitled apps,
        // sysctl can expose hw.radio metrics.
        // Placeholder for private API integration.
        return nil
    }

    // MARK: - Layer 3: Network Path Monitor

    private func startMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let hasSatellite = path.availableInterfaces.contains { iface in
                // iOS may surface satellite as .other or a new type
                iface.type == .other && iface.name.lowercased().contains("sat")
            }
            DispatchQueue.main.async {
                self?.hasSatelliteInterface = hasSatellite
                self?.isMonitoring = true
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - TLE-Based Satellite Prediction (placeholder)

    /// Predict which Globalstar satellite is currently overhead based on
    /// TLE data and the user's location. Full implementation would use
    /// SGP4/SDP4 propagation.
    private func predictOverheadSatellite() -> String? {
        // TODO: Fetch current Globalstar TLEs from CelesTrak
        // https://celestrak.org/NORAD/elements/gp.php?GROUP=globalstar&FORMAT=tle
        // Run SGP4 propagation for user's lat/lon/time
        // Return the satellite with highest elevation angle
        return nil
    }
}
