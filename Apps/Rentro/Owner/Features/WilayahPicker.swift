import SwiftUI

/// Indonesian regions (Kepmendagri No. 300.2.2-2430 Tahun 2025) from the nusawilayah data package, served by jsDelivr.
/// File layout and row format: https://github.com/cuikww/nusawilayah/blob/main/docs/SPEC.md
enum Wilayah {
    static let baseURL = URL(string: "https://cdn.jsdelivr.net/npm/@nusawilayah/data@2025.2/dist/")!
    static let levels = 4

    struct Item: Hashable, Identifiable {
        let kode, nama: String
        var kodePos: String?
        var id: String { kode }
    }

    /// "51.03.01.1001" → ["51", "51.03", "51.03.01", "51.03.01.1001"]; "" → [].
    static func path(_ kode: String) -> [String] {
        let parts = kode.split(separator: ".")
        return parts.indices.map { parts[...$0].joined(separator: ".") }
    }

    /// File holding the children of `parent`: provinsi.json, then kabupaten/, kecamatan/, desa/ per parent kode.
    static func file(childrenOf parent: String?) -> String {
        guard let parent else { return "provinsi.json" }
        return ["kabupaten", "kecamatan", "desa"][path(parent).count - 1] + "/\(parent).json"
    }

    /// Rows are [kode, nama] or, for desa, [kode, nama, kodePos].
    static func decode(_ data: Data) throws -> [Item] {
        try JSONDecoder().decode([[String]].self, from: data).map { Item(kode: $0[0], nama: $0[1], kodePos: $0.count > 2 ? $0[2] : nil) }
    }

    /// URLSession's shared cache keeps the files, so reopening the picker works offline after the first load.
    static func children(of parent: String?) async throws -> [Item] {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: file(childrenOf: parent)))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decode(data)
    }
}

/// Province → regency/city → district → village, plus the village's postal code. `kode` is the village kode, or "" until
/// a village is chosen.
struct WilayahPicker: View {
    @Binding var kode: String
    @State private var options = Array(repeating: [Wilayah.Item](), count: Wilayah.levels)
    @State private var selected = Array(repeating: "", count: Wilayah.levels)
    @State private var failed = false
    private let titles: [LocalizedStringKey] = ["Province", "Regency/City", "District", "Village"]

    var body: some View {
        Group { fields }.task { await load() }
    }

    @ViewBuilder private var fields: some View {
        ForEach(0..<Wilayah.levels, id: \.self) { level in
            RentroFormField(label: titles[level]) {
                Picker(titles[level], selection: selection(level)) {
                    Text("Choose").tag("")
                    ForEach(options[level]) { Text($0.nama).tag($0.kode) }
                }
                .labelsHidden().tint(.textPrimary)
                .disabled(options[level].isEmpty)
                .accessibilityIdentifier("rentro.wilayah.\(level)")
            }
        }
        if failed {
            Button("Couldn't load regions. Try again") { Task { await load() } }.frame(minHeight: 44)
        } else if let kodePos = options[3].first(where: { $0.kode == selected[3] })?.kodePos {
            RentroFormField(label: "Postal code") { Text(kodePos).foregroundStyle(Color.textSecondary) }
        }
    }

    private func selection(_ level: Int) -> Binding<String> {
        Binding(get: { selected[level] }, set: { value in
            selected[level] = value
            for below in level + 1..<Wilayah.levels { selected[below] = ""; options[below] = [] }
            kode = level == Wilayah.levels - 1 ? value : ""
            if !value.isEmpty, level < Wilayah.levels - 1 { Task { await fill(level + 1, parent: value) } }
        })
    }

    /// Loads the provinces, then each level on the saved kode's path, so an existing address opens filled in.
    private func load() async {
        failed = false
        let path = Wilayah.path(kode)
        await fill(0, parent: nil)
        for (level, value) in path.enumerated() where !failed {
            selected[level] = value
            if level < Wilayah.levels - 1 { await fill(level + 1, parent: value) }
        }
    }

    private func fill(_ level: Int, parent: String?) async {
        do {
            let items = try await Wilayah.children(of: parent)
            // Ignore a late answer for a parent that is no longer selected.
            if level == 0 || selected[level - 1] == parent { options[level] = items }
        } catch { failed = true }
    }
}
