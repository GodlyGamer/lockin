import Foundation
import CoreKit

/// Reads the signing profile's expiry date from `embedded.mobileprovision` (DESIGN.md §9.3).
///
/// The profile is a signed blob with a plain XML property list inside. This takes the bytes from `<?xml` to `</plist>`,
/// parses them with `PropertyListSerialization` and returns `ExpirationDate`. Any failure returns nil, which the app shows
/// as "Unknown" and treats as "no warning" ([VERIFY] on a Sideloadly-signed build; there is no profile in the simulator).
nonisolated struct ProvisioningSigningInfo: SigningInfoProviding {
    init() {}

    func expiryDate() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ProvisioningSigningInfo.expirationDate(inProfile: data)
    }

    /// The `ExpirationDate` inside the bytes of a provisioning profile, or nil.
    static func expirationDate(inProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: .backwards),
              start.lowerBound < end.upperBound else { return nil }
        let plistBytes = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistBytes, options: [], format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return dictionary["ExpirationDate"] as? Date
    }
}
