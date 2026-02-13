import NotifyCore
import XCTest

final class UnitUtilityTests: XCTestCase {
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

  func test_U010_safePathComponentSanitizesUnsafeCharacters() {
    XCTAssertEqual(safePathComponent("../../hi there"), "default")
    XCTAssertEqual(safePathComponent("."), "default")
    XCTAssertEqual(safePathComponent(".."), "default")
    XCTAssertEqual(safePathComponent("sender..id"), "default")
    XCTAssertEqual(safePathComponent("sender/app\\path"), "sender_app_path")
    XCTAssertEqual(safePathComponent(""), "default")
  }

  func test_U011_safeBundleIDComponentSanitizesAndTrims() {
    XCTAssertEqual(safeBundleIDComponent(".com example.sender."), "com-example.sender")
    XCTAssertEqual(safeBundleIDComponent("***"), "sender")
  }

  func test_U012_helperBundleIDUsesBaseAndNeverEqualsSenderBundleID() {
    let senderID = "com.example.sender"
    let isolatedID = helperBundleID(baseBundleID: "com.test.notify", senderBundleID: senderID)

    XCTAssertNotEqual(isolatedID, senderID)
    XCTAssertTrue(isolatedID.hasPrefix("com.test.notify.spoof."))
  }

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

  func test_U016_buildRelaunchArgumentsRemovesInternalFlagsAndAddsOrigin() {
    let rewritten = buildRelaunchArguments(
      from: [
        "-message", "x",
        "-spoofed-run",
        "-origin-exec", "/tmp/old",
        "-fallback-run",
        "-sender-mode", "auto"
      ],
      originExecutablePath: "/tmp/current"
    )

    XCTAssertEqual(rewritten, [
      "-message", "x",
      "-sender-mode", "auto",
      "-spoofed-run",
      "-origin-exec", "/tmp/current"
    ])
  }
}
