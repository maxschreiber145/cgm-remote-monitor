import Foundation
import CoreLocation

struct BeamRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double

    // Signal metrics
    let rsrp: Double?       // Reference Signal Received Power (dBm)
    let rsrq: Double?       // Reference Signal Received Quality (dB)
    let sinr: Double?       // Signal-to-Interference-plus-Noise Ratio (dB)
    let rawSignalStrength: Double? // Generic RSSI fallback (dBm)

    // Satellite identification
    let satelliteName: String
    let radioAccessTechnology: String
    let carrierName: String?
    let bandInfo: String?    // e.g. "n53" for Globalstar NTN

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Best available power reading in dBm
    var beamPower: Double? {
        rsrp ?? rawSignalStrength
    }

    /// Human-readable signal quality
    var signalQuality: SignalQuality {
        guard let power = beamPower else { return .unknown }
        switch power {
        case -80...0:    return .excellent
        case -100..<(-80): return .good
        case -110..<(-100): return .fair
        case -120..<(-110): return .weak
        default:         return .noSignal
        }
    }

    var formattedTimestamp: String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: timestamp)
    }

    var formattedCoordinate: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    var formattedAltitude: String {
        String(format: "%.0f m", altitude)
    }

    var formattedBeamPower: String {
        guard let power = beamPower else { return "—" }
        return String(format: "%.1f dBm", power)
    }
}

enum SignalQuality: String, Codable, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case weak = "Weak"
    case noSignal = "No Signal"
    case unknown = "Unknown"

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good:      return "mint"
        case .fair:      return "yellow"
        case .weak:      return "orange"
        case .noSignal:  return "red"
        case .unknown:   return "gray"
        }
    }
}
