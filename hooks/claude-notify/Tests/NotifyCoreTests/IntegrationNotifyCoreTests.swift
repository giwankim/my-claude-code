import NotifyCore
import XCTest

/// Integration-style tests for sender resolution and helper preparation flows.
final class IntegrationNotifyCoreTests: XCTestCase {
  /// Verifies sender app lookup can resolve fixture apps by bundle identifier.
  func test_I001_resolveSenderAppURLFindsFixtureByBundleID() throws {
    let temp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temp) }

    let appURL = try makeFixtureApp(
      under: temp,
      appName: "SenderFixture.app",
      bundleID: "com.example.fixture",
      displayName: "Fixture Sender",
      iconName: "FixtureIcon"
    )

    var args = NotifyArgs()
    args.message = "x"
    args.senderMode = .auto
    args.senderBundleID = "com.example.fixture"

    let resolver = SenderResolver(
      bundleLookup: { _ in nil },
      appRoots: [temp],
      fileManager: .default
    )

    let resolved = try resolveSenderAppURL(args: args, resolver: resolver)
    XCTAssertEqual(resolved.resolvingSymlinksInPath().path, appURL.resolvingSymlinksInPath().path)
  }

  /// Verifies sender app info extraction reads display name and icon metadata.
  func test_I002_resolveSenderAppInfoReadsDisplayNameAndIcon() throws {
    let temp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temp) }

    _ = try makeFixtureApp(
      under: temp,
      appName: "SenderFixture.app",
      bundleID: "com.example.fixture",
      displayName: "Fixture Sender",
      iconName: "FixtureIcon"
    )

    var args = NotifyArgs()
    args.message = "x"
    args.senderMode = .auto
    args.senderBundleID = "com.example.fixture"

    let resolver = SenderResolver(
      bundleLookup: { _ in nil },
      appRoots: [temp],
      fileManager: .default
    )

    let info = try resolveSenderAppInfo(args: args, resolver: resolver)
    XCTAssertEqual(info.displayName, "Fixture Sender")
    XCTAssertEqual(info.iconFile, "FixtureIcon.icns")
  }

  /// Verifies helper preparation isolates bundle identifiers when requested.
  func test_I003_prepareSpoofHelperCreatesIsolatedBundleIdentifier() throws {
    let temp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temp) }

    let senderApp = try makeFixtureApp(
      under: temp,
      appName: "SenderFixture.app",
      bundleID: "com.example.sender",
      displayName: "Fixture Sender",
      iconName: "FixtureIcon"
    )
    let executable = try makeDummyExecutable(under: temp, name: "source-notify")

    let sender = SenderAppInfo(
      bundleID: "com.example.sender",
      displayName: "Fixture Sender",
      appURL: senderApp,
      iconFile: "FixtureIcon.icns"
    )

    let helperExecutable = try prepareSpoofHelper(
      sender: sender,
      sourceExecutablePath: executable.path,
      options: HelperPreparationOptions(
        isolateHelperBundleID: true,
        baseBundleID: "com.test.notify",
        baseDirectories: [temp.appendingPathComponent("helper", isDirectory: true)],
        fileManager: .default,
        signer: { _, _ in }
      )
    )

    let helperApp = helperExecutable
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let plist = try readInfoPlist(appURL: helperApp)
    let helperID = plist["CFBundleIdentifier"] as? String

    XCTAssertNotNil(helperID)
    XCTAssertNotEqual(helperID, sender.bundleID)
    XCTAssertTrue(helperID?.hasPrefix("com.test.notify.spoof.") == true)
  }

  /// Verifies helper preparation copies sender icon assets into helper resources.
  func test_I004_prepareSpoofHelperCopiesIconWhenPresent() throws {
    let temp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temp) }

    let senderApp = try makeFixtureApp(
      under: temp,
      appName: "SenderFixture.app",
      bundleID: "com.example.sender",
      displayName: "Fixture Sender",
      iconName: "FixtureIcon"
    )
    let executable = try makeDummyExecutable(under: temp, name: "source-notify")

    let sender = SenderAppInfo(
      bundleID: "com.example.sender",
      displayName: "Fixture Sender",
      appURL: senderApp,
      iconFile: "FixtureIcon.icns"
    )

    let helperExecutable = try prepareSpoofHelper(
      sender: sender,
      sourceExecutablePath: executable.path,
      options: HelperPreparationOptions(
        isolateHelperBundleID: false,
        baseBundleID: "com.test.notify",
        baseDirectories: [temp.appendingPathComponent("helper", isDirectory: true)],
        fileManager: .default,
        signer: { _, _ in }
      )
    )

    let helperResources = helperExecutable
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Resources", isDirectory: true)
      .appendingPathComponent("FixtureIcon.icns")

    XCTAssertTrue(FileManager.default.fileExists(atPath: helperResources.path))
  }

  /// Verifies relaunch argument rewriting removes internal markers consistently.
  func test_I005_buildRelaunchArgumentsStripsInternalFlags() {
    let args = buildRelaunchArguments(
      from: [
        "-message", "done",
        "-origin-exec", "/tmp/old",
        "-spoofed-run",
        "-fallback-run",
        "-sender-mode", "auto"
      ],
      originExecutablePath: "/tmp/new"
    )

    XCTAssertEqual(args, [
      "-message", "done",
      "-sender-mode", "auto",
      "-spoofed-run",
      "-origin-exec", "/tmp/new"
    ])
  }

  /// Creates a unique temporary directory for isolated integration fixtures.
  private func makeTempDir() throws -> URL {
    let base = FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("notifycore-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Creates a minimal `.app` fixture with plist metadata and icon resources.
  private func makeFixtureApp(
    under root: URL,
    appName: String,
    bundleID: String,
    displayName: String,
    iconName: String
  ) throws -> URL {
    let appURL = root.appendingPathComponent(appName, isDirectory: true)
    let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
    let resources = contents.appendingPathComponent("Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

    let plist: [String: Any] = [
      "CFBundleIdentifier": bundleID,
      "CFBundleDisplayName": displayName,
      "CFBundleIconFile": iconName
    ]
    try writeInfoPlist(plist, to: contents.appendingPathComponent("Info.plist"))

    let iconPath = resources.appendingPathComponent("\(iconName).icns")
    try Data("icon".utf8).write(to: iconPath)

    return appURL
  }

  /// Creates an executable shell fixture used as a helper source binary.
  private func makeDummyExecutable(under root: URL, name: String) throws -> URL {
    let file = root.appendingPathComponent(name)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    return file
  }
}
