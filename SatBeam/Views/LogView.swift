import SwiftUI

struct LogView: View {

    @EnvironmentObject var store: RecordStore

    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if store.records.isEmpty {
                    emptyState
                } else {
                    recordList
                }
            }
            .navigationTitle("Log")
            .toolbar {
                if !store.records.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Export") {
                            exportURL = store.exportCSVFile()
                            showExportSheet = exportURL != nil
                        }
                    }
                }
            }
            .confirmationDialog("Delete all records?", isPresented: $showDeleteConfirm) {
                Button("Delete All", role: .destructive) {
                    withAnimation { store.deleteAll() }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No recordings yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tap REC to capture a beam measurement")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Record List

    private var recordList: some View {
        List {
            // Summary header
            Section {
                HStack {
                    summaryItem(
                        title: "Recordings",
                        value: "\(store.records.count)"
                    )
                    Divider()
                    summaryItem(
                        title: "Avg Power",
                        value: averagePower
                    )
                    Divider()
                    summaryItem(
                        title: "Best",
                        value: bestPower
                    )
                }
                .padding(.vertical, 4)
            }

            // Records
            Section("Measurements") {
                ForEach(store.records) { record in
                    NavigationLink(destination: RecordDetailView(record: record)) {
                        RecordRow(record: record)
                    }
                }
                .onDelete { offsets in
                    withAnimation { store.delete(at: offsets) }
                }
            }
        }
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
    }

    private var averagePower: String {
        let powers = store.records.compactMap(\.beamPower)
        guard !powers.isEmpty else { return "—" }
        let avg = powers.reduce(0, +) / Double(powers.count)
        return String(format: "%.1f", avg)
    }

    private var bestPower: String {
        guard let best = store.records.compactMap(\.beamPower).max() else { return "—" }
        return String(format: "%.1f", best)
    }
}

// MARK: - Row

struct RecordRow: View {
    let record: BeamRecord

    var body: some View {
        HStack(spacing: 12) {
            // Signal quality indicator
            Circle()
                .fill(qualityColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(record.formattedBeamPower)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    Text(record.satelliteName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Text("\(record.formattedCoordinate)  \(record.formattedTimestamp)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
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

// MARK: - Share Sheet (UIKit bridge)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
