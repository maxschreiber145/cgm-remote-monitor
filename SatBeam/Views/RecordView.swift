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

            // Signal strength display
            VStack(spacing: 4) {
                Text("BEAM POWER")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tracking(2)

                if let reading = signal.currentReading, let power = reading.rsrp ?? reading.rawSignalStrength {
                    Text(String(format: "%.1f dBm", power))
                        .font(.system(size: 48, weight: .thin, design: .monospaced))
                        .foregroundStyle(colorForPower(power))
                } else {
                    Text("— dBm")
                        .font(.system(size: 48, weight: .thin, design: .monospaced))
                        .foregroundStyle(.secondary)
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

            if let band = signal.currentReading?.bandInfo {
                HStack(spacing: 24) {
                    infoColumn(label: "BAND", value: band)
                    Spacer()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                // Outer pulse ring
                Circle()
                    .stroke(lineWidth: 2)
                    .foregroundStyle(.red.opacity(0.3))
                    .scaleEffect(pulseScale)

                // Main button
                Circle()
                    .fill(.red)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Text("REC")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: .red.opacity(0.4), radius: isRecording ? 20 : 8)
            }
            .frame(width: 100, height: 100)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .heavy), trigger: lastRecordTime)
    }

    // MARK: - Actions

    private func recordMeasurement() {
        // Visual feedback
        withAnimation(.easeOut(duration: 0.3)) {
            pulseScale = 1.4
        }
        withAnimation(.easeIn(duration: 0.2).delay(0.3)) {
            pulseScale = 1.0
        }

        // Capture
        let reading = signal.capture()

        let record = BeamRecord(
            id: UUID(),
            timestamp: Date(),
            latitude: location.latitude,
            longitude: location.longitude,
            altitude: location.altitude,
            rsrp: reading.rsrp,
            rsrq: reading.rsrq,
            sinr: reading.sinr,
            rawSignalStrength: reading.rawSignalStrength,
            satelliteName: reading.satelliteName,
            radioAccessTechnology: reading.radioAccessTechnology,
            carrierName: reading.carrierName,
            bandInfo: reading.bandInfo
        )

        store.add(record)
        lastRecordTime = Date()
    }

    private func colorForPower(_ power: Double) -> Color {
        switch power {
        case -80...0:      return .green
        case -100..<(-80): return .mint
        case -110..<(-100): return .yellow
        case -120..<(-110): return .orange
        default:           return .red
        }
    }
}
