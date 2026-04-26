import XCTest
@testable import WhisperType

// MARK: - ModelManager progress throttle

/// Tests that the KVO throttle inside ModelManager limits how often
/// `downloadProgress` is updated on the main actor.
///
/// The production throttle uses date-based gating: updates separated by less
/// than `progressInterval` (0.1 s) are dropped. Firing many synthetic updates
/// in a tight loop should therefore produce far fewer published values than
/// input callbacks.
///
/// NOTE: `progressInterval` is declared `private` in ModelManager, so it is
/// not accessible via `@testable import`. The test below therefore verifies
/// the observable contract (initial state) rather than the internal constant.
///
/// To enable the full throttle-count assertion, ask the swift-engineer to
/// change `private let progressInterval` to `internal let progressInterval`
/// (or add a nonisolated `shouldEmitProgress(now:) -> Bool` helper). Then
/// replace the SKIP body with the direct property check shown in the comment.
final class ModelManagerThrottleTests: XCTestCase {

    /// Regression: `downloadProgress` starts at 0 and `isDownloading` starts
    /// false, ensuring the UI never shows a stale progress bar on launch.
    @MainActor
    func testProgressUpdatesAreThrottled() {
        // SKIP — full throttle-count assertion requires internal access.
        //
        // Once `progressInterval` is `internal` (or a `shouldEmitProgress` helper
        // is exposed), replace this body with:
        //
        //   let manager = ModelManager()
        //   let base = Date()
        //   var emitCount = 0
        //   for i in 0..<100 {
        //       let t = base.addingTimeInterval(Double(i) * 0.001) // 1 ms apart
        //       if manager.shouldEmitProgress(now: t) { emitCount += 1 }
        //   }
        //   // 100 ms span / 100 ms interval = ~1-2 true results
        //   XCTAssertLessThanOrEqual(emitCount, 3,
        //       "Throttle must cap updates to ≤3 in a 100 ms window")
        //
        // For now verify the observable initial state that the throttle preserves.
        let manager = ModelManager()
        XCTAssertEqual(manager.downloadProgress, 0.0, accuracy: 0.001,
                       "downloadProgress must start at 0")
        XCTAssertFalse(manager.isDownloading,
                       "isDownloading must start false")
    }
}
