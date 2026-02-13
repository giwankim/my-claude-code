import NotifyCore
import XCTest

final class UnitArgParserTests: XCTestCase {
  func test_U001_parseRejectsUnknownFlag() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-bogus"])) { error in
      XCTAssertEqual(error as? ArgParseError, .unknownFlag("-bogus"))
    }
  }

  func test_U002_parseRejectsInvalidSenderMode() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-message", "x", "-sender-mode", "bogus"])) { error in
      XCTAssertEqual(error as? ArgParseError, .invalidSenderMode("bogus"))
    }
  }

  func test_U003_parseRequiresMessageUnlessRemoveIsPresent() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-title", "x"])) { error in
      XCTAssertEqual(error as? ArgParseError, .missingMessage)
    }
  }

  func test_U004_parseAllowsRemoveWithoutMessage() throws {
    let parsed = try ArgumentParser.parse(["-remove", "claude-code"])
    XCTAssertEqual(parsed.remove, "claude-code")
    XCTAssertNil(parsed.message)
  }

  func test_U005_parseRejectsMissingFlagValue() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-title"])) { error in
      XCTAssertEqual(error as? ArgParseError, .missingValue("-title"))
    }
  }

  func test_U006_parseRejectsInvalidTimeout() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-message", "x", "-timeout", "0"])) { error in
      XCTAssertEqual(error as? ArgParseError, .invalidTimeout)
    }
  }

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

  func test_U008_parseHelpRaisesHelpRequested() {
    XCTAssertThrowsError(try ArgumentParser.parse(["-help"])) { error in
      XCTAssertEqual(error as? ArgParseError, .helpRequested)
    }
  }
}
