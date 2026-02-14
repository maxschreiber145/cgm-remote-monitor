import SwiftUI

struct RecordView: View {

    @EnvironmentObject var store: RecordStore
    @EnvironmentObject var location: LocationService
    @EnvironmentObject var signal: SignalService

    @State private var isRecording = false
    @State private var lastRecordTime: Date?
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Current readings panel
                currentReadingsPanel
                    .padding()

                Spacer()

                // Record button
                recordButton
                    .padding(.bottom, 40)

                // Last recorded info
                if let last = lastRecordTime {
                    Text("Last recorded \(last, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle("SatBeam")
            .onAppear {
                location.requestPermission()
            }
        }
    }

    // MARK: - Current Readings

    private var currentReadingsPanel: some View {
        VStack(spacing: 16) {

            // Connection type + latency display
            VStack(spacing: 4) {
                Text("CONNECTION")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tracking(2)

                HStack(spacing: 8) {
                    connectionIcon
                    Text(signal.connectionType.rawValue)
                        .font(.system(size: 32, weight: .thin, design: .monospaced))
                }

                if let reading = signal.currentReading, let ms = reading.latencyMs {
                    Text(String(format: "%.0f ms", ms))
                        .font(.system(size: 20, weight: .light, design: .monospaced))
                        .foregroundStyle(colorForLatency(ms))
                }
            }

            Divider()

            // Satellite + location info
            HStack(spacing: 24) {
                infoColumn(label: "SATELLITE", value: signal.currentReading?.satelliteName ?? "—")
                infoColumn(label: "RAT", value: signal.currentReading?.radioAccessTechnology ?? "—")
            }

            HStack(spacing: 24) {
                infoColumn(label: "LOCATION", value: location.formattedCoordinate)
                infoColumn(label: "ALTITUDE", value: location.formattedAltitude)
            }

            HStack(spacing: 24) {
                infoColumn(label: "CARRIER", value: signal.currentReading?.carrierName ?? "—")
                if let band = signal.currentReading?.bandInfo {
                    infoColumn(label: "BAND", value: band)
                } else {
                    Spacer()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var connectionIcon: some View {
        switch signal.connectionType {
        case .satellite:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.green)
        case .cellular:
            Image(systemName: "cellularbars")
                .foregroundStyle(.blue)
        case .wifi:
            Image(systemName: "wifi")
                .foregroundStyle(.blue)
        case .none:
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.red)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func infoColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(1.5)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button(action: recordMeasurement) {
            ZStack {
                Circle()
                    .stroke(lineWidth: 2)
                    .foregroundStyle(.red.opacity(0.3))
                    .scaleEffect(pulseScale)

                Circle()
                    .fill(.red)
                    .frame(width: 80, height: 80)
                    .overlay(
                        VStack(spacing: 2) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 20))
                            Text("REC")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(.white)
                    )
                    .shadow(color: .red.opacity(0.4), radius: isRecording ? 20 : 8)
            }
            .frame(width: 100, height: 100)
        }
        .buttonStyle(.plain)
        .disabled(isRecording)
        .sensoryFeedback(.impact(weight: .heavy), trigger: lastRecordTime)
    }

    // MARK: - Actions

    private func recordMeasurement() {
        isRecording = true

        // Visual feedback
        withAnimation(.easeOut(duration: 0.3)) {
            pulseScale = 1.4
        }
        withAnimation(.easeIn(duration: 0.2).delay(0.3)) {
            pulseScale = 1.0
        }

        Task {
            let reading = await signal.capture()

            let record = BeamRecord(
                id: UUID(),
                timestamp: Date(),
                latitude: location.latitude,
                longitude: location.longitude,
                altitude: location.altitude,
                connectionType: reading.connectionType,
                latencyMs: reading.latencyMs,
                satelliteName: reading.satelliteName,
                radioAccessTechnology: reading.radioAccessTechnology,
                carrierName: reading.carrierName,
                bandInfo: reading.bandInfo
            )

            await MainActor.run {
                store.add(record)
                lastRecordTime = Date()
                isRecording = false
            }
        }
    }

    private func colorForLatency(_ ms: Double) -> Color {
        switch ms {
        case 0..<50:    return .green
        case 50..<100:  return .mint
        case 100..<300: return .yellow
        case 300..<1000: return .orange
        default:        return .red
        }
    }
}
