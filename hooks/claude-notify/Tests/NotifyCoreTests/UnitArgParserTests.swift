import NotifyCore
import XCTest

/// Unit tests for command-line argument parsing behavior.
final class UnitArgParserTests: XCTestCase {
  /// Verifies unknown flags are rejected with the expected parser error.
  func test_U001_parseRejectsUnknownFlag() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-bogus"])) { error in
      XCTAssertEqual(error as? ArgParseError, .unknownFlag("-bogus"))
    }
  }

  /// Verifies invalid sender modes are rejected with a typed parser error.
  func test_U002_parseRejectsInvalidSenderMode() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-message", "x", "-sender-mode", "bogus"])) { error in
      XCTAssertEqual(error as? ArgParseError, .invalidSenderMode("bogus"))
    }
  }

  /// Verifies message is required unless remove mode is explicitly requested.
  func test_U003_parseRequiresMessageUnlessRemoveIsPresent() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-title", "x"])) { error in
      XCTAssertEqual(error as? ArgParseError, .missingMessage)
    }
  }

  /// Verifies remove mode can be parsed without requiring a message body.
  func test_U004_parseAllowsRemoveWithoutMessage() throws {
    let parsed = try ArgumentParser.parse(["-remove", "claude-code"])
    XCTAssertEqual(parsed.remove, "claude-code")
    XCTAssertNil(parsed.message)
  }

  /// Verifies missing flag values are detected and surfaced as parser errors.
  func test_U005_parseRejectsMissingFlagValue() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-title"])) { error in
      XCTAssertEqual(error as? ArgParseError, .missingValue("-title"))
    }
  }

  /// Verifies non-positive timeout values are rejected by the parser.
  func test_U006_parseRejectsInvalidTimeout() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-message", "x", "-timeout", "0"])) { error in
      XCTAssertEqual(error as? ArgParseError, .invalidTimeout)
    }
    XCTAssertThrowsError(try ArgumentParser.parse(["-message", "x", "-timeout", "-1"])) { error in
      XCTAssertEqual(error as? ArgParseError, .invalidTimeout)
    }
  }

  /// Verifies happy-path parsing maps all supported flags to model fields.
  func test_U007_parseBuildsExpectedArgsForHappyPath() throws {
    let parsed = try ArgumentParser.parse([
      "-title", "Claude",
      "-subtitle", "Session",
      "-message", "Done",
      "-sound", "default",
      "-group", "claude-code",
      "-execute", "echo hi",
      "-activate", "com.example.app",
      "-sender-mode", "auto",
      "-sender-bundle-id", "com.example.sender",
      "-timeout", "45"
    ])

    XCTAssertEqual(parsed.title, "Claude")
    XCTAssertEqual(parsed.subtitle, "Session")
    XCTAssertEqual(parsed.message, "Done")
    XCTAssertEqual(parsed.sound, "default")
    XCTAssertEqual(parsed.group, "claude-code")
    XCTAssertEqual(parsed.execute, "echo hi")
    XCTAssertEqual(parsed.activate, "com.example.app")
    XCTAssertEqual(parsed.senderMode, .auto)
    XCTAssertEqual(parsed.senderBundleID, "com.example.sender")
    XCTAssertEqual(parsed.timeout, 45)
  }

  /// Verifies explicit help flags short-circuit parsing with help request errors.
  func test_U008_parseHelpRaisesHelpRequested() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-help"])) { error in
      XCTAssertEqual(error as? ArgParseError, .helpRequested)
    }
  }

  /// Verifies -generation flag parses into the generation field.
  func test_U045_parseAcceptsGenerationFlag() throws {
    let parsed = try ArgumentParser.parse(["-message", "x", "-generation", "42_1709000000"])
    XCTAssertEqual(parsed.generation, "42_1709000000")
  }

  /// Verifies generation defaults to nil when flag is absent.
  func test_U046_parseDefaultsGenerationToNil() throws {
    let parsed = try ArgumentParser.parse(["-message", "x"])
    XCTAssertNil(parsed.generation)
  }
}
