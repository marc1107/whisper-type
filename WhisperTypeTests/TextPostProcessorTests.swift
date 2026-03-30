import XCTest
@testable import WhisperType

final class TextPostProcessorTests: XCTestCase {
    let processor = TextPostProcessor()

    // MARK: - German filler words

    func testRemovesGermanFillers() {
        XCTAssertEqual(processor.process("Ähm ich denke äh das ist gut"), "Ich denke das ist gut")
    }

    func testRemovesOhm() {
        XCTAssertEqual(processor.process("Öhm ja das stimmt"), "Ja das stimmt")
    }

    func testRemovesHmm() {
        XCTAssertEqual(processor.process("Hmm das ist interessant"), "Das ist interessant")
    }

    // MARK: - English filler words

    func testRemovesEnglishFillers() {
        XCTAssertEqual(processor.process("Uhm I think uh this is good"), "I think this is good")
    }

    func testRemovesYouKnow() {
        XCTAssertEqual(processor.process("It is you know really good"), "It is really good")
    }

    // MARK: - Whitespace cleanup

    func testCollapsesDoubleSpaces() {
        XCTAssertEqual(processor.process("Hello  world"), "Hello world")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(processor.process("  Hello world  "), "Hello world")
    }

    // MARK: - Capitalization

    func testCapitalizesFirstLetter() {
        XCTAssertEqual(processor.process("hello world"), "Hello world")
    }

    // MARK: - Preserves meaningful words

    func testPreservesLikeAsVerb() {
        XCTAssertEqual(processor.process("I like this"), "I like this")
    }

    // MARK: - Custom filler words

    func testCustomFillerWords() {
        let p = TextPostProcessor(customFillerWords: ["basically"])
        XCTAssertEqual(p.process("It is basically done"), "It is done")
    }

    // MARK: - Empty/nil

    func testEmptyString() {
        XCTAssertEqual(processor.process(""), "")
    }

    func testOnlyFillers() {
        XCTAssertEqual(processor.process("ähm äh öhm"), "")
    }

    // MARK: - Disabled filter

    func testDisabledFilter() {
        let p = TextPostProcessor(enabled: false)
        XCTAssertEqual(p.process("Ähm ich denke"), "Ähm ich denke")
    }
}
