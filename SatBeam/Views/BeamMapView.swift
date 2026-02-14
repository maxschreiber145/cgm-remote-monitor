import SwiftUI
import MapKit

struct BeamMapView: View {

    @EnvironmentObject var store: RecordStore
    @EnvironmentObject var location: LocationService

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                if store.records.isEmpty {
                    emptyState
                } else {
                    mapContent
                }
            }
            .navigationTitle("Map")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No data to map")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Record measurements to see them plotted here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var mapContent: some View {
        Map(position: $position) {
            // Current location
            if location.horizontalAccuracy >= 0 {
                UserAnnotation()
            }

            // All recorded measurements as color-coded markers
            ForEach(store.records) { record in
                Annotation(
                    record.formattedLatency,
                    coordinate: record.coordinate
                ) {
                    beamDot(for: record)
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .bottom) {
            legend
                .padding(.bottom, 8)
        }
    }

    private func beamDot(for record: BeamRecord) -> some View {
        ZStack {
            Circle()
                .fill(qualityColor(record.signalQuality).opacity(0.3))
                .frame(width: 28, height: 28)
            Circle()
                .fill(qualityColor(record.signalQuality))
                .frame(width: 14, height: 14)
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: 14, height: 14)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(SignalQuality.allCases.filter { $0 != .unknown }, id: \.self) { q in
                HStack(spacing: 4) {
                    Circle()
                        .fill(qualityColor(q))
                        .frame(width: 8, height: 8)
                    Text(q.rawValue)
                        .font(.system(size: 9))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func qualityColor(_ quality: SignalQuality) -> Color {
        switch quality {
        case .excellent: return .green
        case .good:      return .mint
        case .fair:      return .yellow
        case .weak:      return .orange
        case .noSignal:  return .red
        case .unknown:   return .gray
        }
    }
}
