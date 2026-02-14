import SwiftUI
import MapKit

struct RecordDetailView: View {

    let record: BeamRecord

    var body: some View {
        List {
            // Map
            Section {
                Map {
                    Marker(record.satelliteName, coordinate: record.coordinate)
                        .tint(qualityColor)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            // Connection
            Section("Connection") {
                metricRow("Type", value: record.connectionType.rawValue)
                metricRow("Latency", value: record.formattedLatency)
                metricRow("Quality", value: record.signalQuality.rawValue, color: qualityColor)
            }

            // Satellite info
            Section("Satellite") {
                metricRow("Name", value: record.satelliteName)
                metricRow("RAT", value: record.radioAccessTechnology)
                if let carrier = record.carrierName {
                    metricRow("Carrier", value: carrier)
                }
                if let band = record.bandInfo {
                    metricRow("Band", value: band)
                }
            }

            // Location
            Section("Location") {
                metricRow("Latitude", value: String(format: "%.6f", record.latitude))
                metricRow("Longitude", value: String(format: "%.6f", record.longitude))
                metricRow("Altitude", value: record.formattedAltitude)
            }

            // Timestamp
            Section("Time") {
                metricRow("Recorded", value: record.formattedTimestamp)
                metricRow("ID", value: String(record.id.uuidString.prefix(8)))
            }
        }
        .navigationTitle(record.formattedLatency)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metricRow(_ label: String, value: String, color: Color? = nil) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(color ?? .primary)
        }
    }

    private var qualityColor: Color {
        switch record.signalQuality {
        case .excellent: return .green
        case .good:      return .mint
        case .fair:      return .yellow
        case .weak:      return .orange
        case .noSignal:  return .red
        case .unknown:   return .gray
        }
    }
}
