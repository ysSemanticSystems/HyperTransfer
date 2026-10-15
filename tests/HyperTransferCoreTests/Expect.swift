import Foundation

enum Expect {
    nonisolated(unsafe) static var failures: [String] = []

    static func fail(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        failures.append("\(file):\(line) \(message)")
    }
}

func XCTAssertTrue(_ condition: Bool, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if !condition { Expect.fail(message.isEmpty ? "expected true" : message, file: file, line: line) }
}

func XCTAssertFalse(_ condition: Bool, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if condition { Expect.fail(message.isEmpty ? "expected false" : message, file: file, line: line) }
}

func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if actual != expected {
        Expect.fail("\(actual) != \(expected) \(message)", file: file, line: line)
    }
}

func XCTAssertNotEqual<T: Equatable>(_ actual: T, _ forbidden: T, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if actual == forbidden {
        Expect.fail("both were \(actual) \(message)", file: file, line: line)
    }
}

func XCTAssertGreaterThan<T: Comparable>(_ actual: T, _ lower: T, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if actual <= lower { Expect.fail("\(actual) is not > \(lower) \(message)", file: file, line: line) }
}

func XCTAssertGreaterThanOrEqual<T: Comparable>(_ actual: T, _ lower: T, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if actual < lower { Expect.fail("\(actual) is not >= \(lower) \(message)", file: file, line: line) }
}

func XCTAssertNil(_ value: Any?, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if value != nil { Expect.fail(message.isEmpty ? "expected nil" : message, file: file, line: line) }
}

func XCTAssertNotNil(_ value: Any?, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) {
    if value == nil { Expect.fail(message.isEmpty ? "expected a value" : message, file: file, line: line) }
}

func XCTAssertThrowsError<T>(
    _ expression: @autoclosure () throws -> T,
    _ message: String = "",
    file: StaticString = #fileID,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) {
    do {
        _ = try expression()
        Expect.fail(message.isEmpty ? "expected an error" : message, file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

func XCTFail(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
    Expect.fail(message, file: file, line: line)
}

func attempt(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
    } catch {
        Expect.fail("\(name) threw \(error)")
    }
}
