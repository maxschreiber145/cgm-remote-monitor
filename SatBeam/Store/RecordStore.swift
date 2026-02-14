import Foundation
import Combine

final class RecordStore: ObservableObject {

    @Published private(set) var records: [BeamRecord] = []

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("satbeam_log.json")
        load()
    }

    // MARK: - CRUD

    func add(_ record: BeamRecord) {
        records.insert(record, at: 0) // newest first
        save()
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    func deleteAll() {
        records.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[RecordStore] Save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            records = try JSONDecoder().decode([BeamRecord].self, from: data)
        } catch {
            print("[RecordStore] Load failed: \(error)")
        }
    }

    // MARK: - Export

    /// Export all records as CSV for analysis.
    func exportCSV() -> String {
        var csv = "timestamp,latitude,longitude,altitude,rsrp_dBm,rsrq_dB,sinr_dB,rssi_dBm,satellite,rat,carrier,band,quality\n"

        for r in records {
            let row = [
                r.formattedTimestamp,
                String(r.latitude),
                String(r.longitude),
                String(r.altitude),
                r.rsrp.map(String.init) ?? "",
                r.rsrq.map(String.init) ?? "",
                r.sinr.map(String.init) ?? "",
                r.rawSignalStrength.map(String.init) ?? "",
                r.satelliteName,
                r.radioAccessTechnology,
                r.carrierName ?? "",
                r.bandInfo ?? "",
                r.signalQuality.rawValue
            ].joined(separator: ",")
            csv += row + "\n"
        }

        return csv
    }

    /// Write CSV to a temp file and return the URL for sharing.
    func exportCSVFile() -> URL? {
        let csv = exportCSV()
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("satbeam_export.csv")
        do {
            try csv.write(to: tmpURL, atomically: true, encoding: .utf8)
            return tmpURL
        } catch {
            print("[RecordStore] CSV export failed: \(error)")
            return nil
        }
    }
}
