import Foundation
import CoreLocation

struct BeamRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double

    // Connectivity
    let connectionType: ConnectionType
    let latencyMs: Double?          // round-trip HTTP ping in milliseconds

    // Satellite identification
    let satelliteName: String
    let radioAccessTechnology: String
    let carrierName: String?
    let bandInfo: String?           // e.g. "n53" for Globalstar NTN

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Signal quality derived from latency when on satellite,
    /// or connection type otherwise.
    var signalQuality: SignalQuality {
        guard let ms = latencyMs else { return .unknown }
        switch connectionType {
        case .satellite:
            // Satellite latency thresholds (LEO, ~1400 km altitude)
            switch ms {
            case 0..<800:    return .excellent
            case 800..<1200: return .good
            case 1200..<1800: return .fair
            case 1800..<3000: return .weak
            default:          return .noSignal
            }
        case .cellular:
            switch ms {
            case 0..<50:    return .excellent
            case 50..<100:  return .good
            case 100..<200: return .fair
            case 200..<500: return .weak
            default:        return .noSignal
            }
        case .wifi:
            switch ms {
            case 0..<20:   return .excellent
            case 20..<50:  return .good
            case 50..<100: return .fair
            case 100..<300: return .weak
            default:        return .noSignal
            }
        default:
            return ms < 500 ? .fair : .weak
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

    var formattedLatency: String {
        guard let ms = latencyMs else { return "—" }
        if ms < 1000 {
            return String(format: "%.0f ms", ms)
        }
        return String(format: "%.1f s", ms / 1000)
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
