import XCTest
@testable import WhisperType

// MARK: - ProgressThrottle

/// The throttle gate that fronts `ModelManager`'s KVO observer must drop
/// most ticks but never the final 100 % tick. Verified directly against the
/// `ProgressThrottle` helper so the test is deterministic and fast.
final class ProgressThrottleTests: XCTestCase {

    /// 100 synthetic ticks 1 ms apart span 99 ms — one interval (100 ms) of
    /// gating means at most two emits (the very first call and possibly one
    /// more if the boundary is crossed). The assertion is generous to avoid
    /// timing-edge flakes.
    func testEmitsAtMostOncePerInterval() {
        let throttle = ProgressThrottle(interval: 0.1)
        let base = Date()
        var emitCount = 0
        for index in 0..<100 {
            let now = base.addingTimeInterval(Double(index) * 0.001)
            if throttle.shouldEmit(now: now, isFinal: false) {
                emitCount += 1
            }
        }
        XCTAssertLessThanOrEqual(emitCount, 2,
                                 "100 ticks across 99 ms must produce ≤2 emits")
        XCTAssertGreaterThanOrEqual(emitCount, 1,
                                    "First tick must always emit")
    }

    /// `isFinal: true` bypasses the rate gate so the UI never gets stuck
    /// showing 99 % when the download actually completed.
    func testFinalTickAlwaysEmits() {
        let throttle = ProgressThrottle(interval: 1.0)
        let base = Date()
        XCTAssertTrue(throttle.shouldEmit(now: base, isFinal: true))
        // Immediately after, with the rate gate fully closed, isFinal still wins.
        XCTAssertTrue(throttle.shouldEmit(now: base.addingTimeInterval(0.001), isFinal: true))
    }

    /// Ticks spread more than one interval apart should all emit.
    func testTicksAcrossManyIntervalsAllEmit() {
        let throttle = ProgressThrottle(interval: 0.1)
        let base = Date()
        var emitCount = 0
        for index in 0..<5 {
            let now = base.addingTimeInterval(Double(index) * 0.2) // 200 ms apart
            if throttle.shouldEmit(now: now, isFinal: false) {
                emitCount += 1
            }
        }
        XCTAssertEqual(emitCount, 5)
    }
}

// MARK: - ModelManager initial state

final class ModelManagerInitialStateTests: XCTestCase {
    /// Regression: `downloadProgress` starts at 0 and `isDownloading` starts
    /// false, ensuring the UI never shows a stale progress bar on launch.
    @MainActor
    func testInitialState() {
        let manager = ModelManager()
        XCTAssertEqual(manager.downloadProgress, 0.0, accuracy: 0.001,
                       "downloadProgress must start at 0")
        XCTAssertFalse(manager.isDownloading,
                       "isDownloading must start false")
    }
}
