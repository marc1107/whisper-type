import XCTest
@testable import WhisperType

// MARK: - OllamaService initial state

final class OllamaServiceInitialStateTests: XCTestCase {

    /// A freshly-created OllamaService must start in a known, inert state before any
    /// network probe has run.
    @MainActor
    func testOllamaServiceInitialState() {
        let service = OllamaService()
        XCTAssertFalse(service.isInstalled, "isInstalled must start false")
        XCTAssertFalse(service.isPulling, "isPulling must start false")
        XCTAssertEqual(service.pullProgress, 0, accuracy: 0.001, "pullProgress must start at 0")
        XCTAssertTrue(service.availableModels.isEmpty, "availableModels must start empty")
    }
}

// MARK: - OllamaService detection

final class OllamaServiceDetectionTests: XCTestCase {

    /// Pointing the service at port 1 (privileged, never listening) must set
    /// isInstalled to false. The service's 1-second timeout guarantees this
    /// completes well within the 5-second overall test budget.
    @MainActor
    func testOllamaServiceDetectsNotInstalled() async {
        let service = OllamaService(baseURL: URL(string: "http://127.0.0.1:1")!)
        await service.detect()
        XCTAssertFalse(service.isInstalled,
                       "detect() against a closed port must set isInstalled = false")
    }
}

// MARK: - OllamaService pull progress parser

/// `parseProgress(from:)` is `nonisolated` but lives on a `@MainActor` type, so
/// the test class is annotated `@MainActor` to satisfy the isolation requirement
/// when calling the method through a stored instance.
@MainActor
final class OllamaPullProgressParserTests: XCTestCase {

    private let service = OllamaService()

    /// A line reporting completed=50 out of total=100 must parse to 0.5.
    func testPullProgressParsesHalfway() throws {
        let line = #"{"status":"pulling","completed":50,"total":100}"#
        let result = try XCTUnwrap(service.parseProgress(from: line),
                                   "completed/total = 50/100 must not be nil")
        XCTAssertEqual(result, 0.5, accuracy: 0.001,
                       "completed/total = 50/100 must equal 0.5")
    }

    /// A pulling-manifest line with completed=0 must parse to 0.0 rather than nil.
    func testPullProgressParsesZeroWhenCompletedIsZero() throws {
        let line = #"{"status":"pulling manifest","completed":0,"total":100}"#
        let result = try XCTUnwrap(service.parseProgress(from: line),
                                   "completed=0 out of 100 must not be nil")
        XCTAssertEqual(result, 0.0, accuracy: 0.001,
                       "completed=0 must yield 0.0, not nil or NaN")
    }

    /// A success status line that carries no progress values must return nil.
    func testPullProgressReturnsNilForSuccessStatus() {
        let line = #"{"status":"success"}"#
        let result = service.parseProgress(from: line)
        XCTAssertNil(result, "A success line with no completed/total must return nil")
    }

    /// Non-JSON input must not crash and must return nil.
    func testPullProgressReturnsNilForNonJSON() {
        let result = service.parseProgress(from: "not json")
        XCTAssertNil(result, "Non-JSON input must return nil without crashing")
    }

    /// A line with total=0 must not divide by zero; return nil to avoid Infinity/NaN.
    func testPullProgressReturnsNilWhenTotalIsZero() {
        let line = #"{"status":"pulling","completed":0,"total":0}"#
        let result = service.parseProgress(from: line)
        XCTAssertNil(result, "total=0 must return nil to avoid division by zero")
    }
}
