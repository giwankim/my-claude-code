import NotifyCore
import XCTest

/// Unit tests for helper utilities and argument rewrite functions.
final class UnitUtilityTests: XCTestCase {
  /// Verifies spoof enablement requires both mode and sender identity inputs.
  func test_U009_senderSpoofEnabledRequiresModeAndSenderIdentity() {
    var args = NotifyArgs()
    args.message = "x"
    args.senderMode = .off
    args.senderBundleID = "com.example.sender"
    XCTAssertFalse(senderSpoofEnabled(args: args))

    args.senderMode = .auto
    args.senderBundleID = nil
    args.senderAppPath = nil
    XCTAssertFalse(senderSpoofEnabled(args: args))

    args.senderBundleID = "com.example.sender"
    XCTAssertTrue(senderSpoofEnabled(args: args))
  }

  /// Verifies unsafe path components are sanitized or replaced with defaults.
  func test_U010_safePathComponentSanitizesUnsafeCharacters() {
    XCTAssertEqual(safePathComponent("../../hi there"), "default")
    XCTAssertEqual(safePathComponent("."), "default")
    XCTAssertEqual(safePathComponent(".."), "default")
    XCTAssertEqual(safePathComponent("sender..id"), "default")
    XCTAssertEqual(safePathComponent("sender/app\\path"), "sender_app_path")
    XCTAssertEqual(safePathComponent(""), "default")
  }

  /// Verifies bundle identifier sanitization strips invalid edge characters.
  func test_U011_safeBundleIDComponentSanitizesAndTrims() {
    XCTAssertEqual(safeBundleIDComponent(".com example.sender."), "com-example.sender")
    XCTAssertEqual(safeBundleIDComponent("***"), "sender")
  }

  /// Verifies isolated helper bundle IDs are derived and distinct from sender IDs.
  func test_U012_helperBundleIDUsesBaseAndNeverEqualsSenderBundleID() {
    let senderID = "com.example.sender"
    let isolatedID = helperBundleID(baseBundleID: "com.test.notify", senderBundleID: senderID)

    XCTAssertNotEqual(isolatedID, senderID)
    XCTAssertTrue(isolatedID.hasPrefix("com.test.notify.spoof."))
  }

  /// Verifies fallback rewrite removes spoof-specific flags and forces off mode.
  func test_U013_buildFallbackArgumentsStripsSenderSpecificFlags() {
    let rewritten = buildFallbackArguments(from: [
      "-message", "hello",
      "-sender-mode", "auto",
      "-sender-bundle-id", "com.example.sender",
      "-sender-app-path", "/tmp/sender.app",
      "-origin-exec", "/tmp/origin",
      "-spoofed-run",
      "-timeout", "5"
    ])

    XCTAssertEqual(rewritten, [
      "-message", "hello",
      "-timeout", "5",
      "-sender-mode", "off",
      "-fallback-run"
    ])
  }

  /// Verifies spoof retry rewrite keeps sender flags while dropping origin markers.
  func test_U014_buildRetrySpoofArgumentsRetainsSenderInputsButDropsOrigin() {
    let rewritten = buildRetrySpoofArguments(from: [
      "-message", "hello",
      "-sender-mode", "auto",
      "-sender-bundle-id", "com.example.sender",
      "-origin-exec", "/tmp/origin",
      "-spoofed-run"
    ])

    XCTAssertEqual(rewritten, [
      "-message", "hello",
      "-sender-mode", "auto",
      "-sender-bundle-id", "com.example.sender"
    ])
  }

  /// Verifies icon candidate extraction normalizes names and removes duplicates.
  func test_U015_iconCandidatesNormalizesAndDeduplicates() {
    let info: [String: Any] = [
      "CFBundleIconFile": "AppIcon",
      "CFBundleIcons": [
        "CFBundlePrimaryIcon": [
          "CFBundleIconFiles": ["AppIcon", "AltIcon", "AltIcon.icns"]
        ]
      ]
    ]

    XCTAssertEqual(iconCandidates(info: info), [
      "AppIcon.icns",
      "AltIcon.icns"
    ])
  }

  /// Verifies relaunch rewrite strips internal flags and appends fresh origin info.
  func test_U016_buildRelaunchArgumentsRemovesInternalFlagsAndAddsOrigin() {
    let rewritten = buildRelaunchArguments(
      from: [
        "-message", "-spoofed-run",
        "-spoofed-run",
        "-origin-exec", "/tmp/old",
        "-fallback-run",
        "-sender-mode", "auto"
      ],
      originExecutablePath: "/tmp/current"
    )

    XCTAssertEqual(rewritten, [
      "-message", "-spoofed-run",
      "-sender-mode", "auto",
      "-spoofed-run",
      "-origin-exec", "/tmp/current"
    ])
  }
}
