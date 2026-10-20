import XCTest
@testable import CoreKit

final class BackupCodecTests: XCTestCase {
    func testFullSnapshotRoundTripsExactly() throws {
        var snapshot = SampleData.bodyFatGoal(today: day("2026-10-21"))
        snapshot.blocks = ScheduleEngine.materialise(rules: snapshot.blockRules, existing: [], from: day("2026-10-21"), days: 14,
                                                     settings: snapshot.settings, systems: snapshot.systems)
        let decoded = try BackupCodec.decode(BackupCodec.encode(snapshot, exportedAt: at("2026-10-21", "19:00")))
        XCTAssertEqual(decoded, snapshot)
    }

    func testEnvelopeFields() throws {
        let data = BackupCodec.encode(.empty, exportedAt: at("2026-10-21", "19:00"), appVersion: "1.0 (7)")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["format"] as? String, "lockin-backup")
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["appVersion"] as? String, "1.0 (7)")
        XCTAssertNotNil(object["exportedAt"] as? String)
        XCTAssertNotNil(object["data"])
    }

    func testRejectsNewerVersionAndForeignFiles() {
        let newer = #"{"format":"lockin-backup","schemaVersion":2,"exportedAt":"2026-10-19T19:00:00Z","appVersion":"2","data":{}}"#
        XCTAssertThrowsError(try BackupCodec.decode(Data(newer.utf8))) {
            XCTAssertEqual($0 as? BackupError, .newerVersion(2))
            XCTAssertEqual(($0 as? BackupError)?.message, "This backup is from a newer version of the app.")
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data(#"{"format":"other","schemaVersion":1}"#.utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try BackupCodec.decode(Data("not json".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
    }
}
