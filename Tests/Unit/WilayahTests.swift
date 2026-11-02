import Foundation
import Testing
@testable import Rentro

struct WilayahTests {
    @Test func pathAndFiles() {
        #expect(Wilayah.path("51.03.01.1001") == ["51", "51.03", "51.03.01", "51.03.01.1001"])
        #expect(Wilayah.path("").isEmpty)
        #expect(Wilayah.file(childrenOf: nil) == "provinsi.json")
        #expect(Wilayah.file(childrenOf: "51") == "kabupaten/51.json")
        #expect(Wilayah.file(childrenOf: "51.03") == "kecamatan/51.03.json")
        #expect(Wilayah.file(childrenOf: "51.03.01") == "desa/51.03.01.json")
    }

    @Test func decodesRowsWithAndWithoutPostalCode() throws {
        let items = try Wilayah.decode(Data(#"[["51.03.01.1001","Tuban","80361"],["51","Bali"]]"#.utf8))
        #expect(items == [Wilayah.Item(kode: "51.03.01.1001", nama: "Tuban", kodePos: "80361"), Wilayah.Item(kode: "51", nama: "Bali")])
    }
}
