import AppKit
import Foundation

/// Controls how sender spoofing should be handled during notification delivery.
public enum SenderMode: String, CaseIterable, Sendable {
  case auto
  case off
  case required
}

/// Represents parsed command-line arguments for a notification run.
public struct NotifyArgs: Equatable, Sendable {
  public var title = "Notification"
  public var subtitle: String?
  public var message: String?
  public var sound: String?
  public var group: String?
  public var execute: String?
  public var activate: String?
  public var remove: String?
  public var senderBundleID: String?
  public var senderAppPath: String?
  public var originExecPath: String?
  public var senderMode: SenderMode = .off
  public var spoofedRun = false
  public var fallbackRun = false
  public var timeout: TimeInterval = 90
  public var generation: String?

  /// Creates a default argument container with baseline runtime values.
  public init() {}
}

/// Describes parser failures that should be surfaced to the caller.
public enum ArgParseError: Error, Equatable {
  case helpRequested
  case missingValue(String)
  case invalidTimeout
  case invalidSenderMode(String)
  case unknownFlag(String)
  case missingMessage
}

/// Parses command-line tokens into a validated ``NotifyArgs`` value.
public struct ArgumentParser {
  /// Creates a parser instance.
  public init() {}

  /// Parses argument tokens with a temporary parser instance.
  ///
  /// - Parameter argv: Command-line tokens without the executable name.
  /// - Returns: A validated ``NotifyArgs`` value.
  /// - Throws: ``ArgParseError`` when tokens are invalid or incomplete.
  public static func parse(_ argv: [String]) throws -> NotifyArgs {
    try ArgumentParser().parse(argv)
  }

  /// Parses argument tokens into a validated arguments model.
  ///
  /// - Parameter argv: Command-line tokens without the executable name.
  /// - Returns: A validated ``NotifyArgs`` value.
  /// - Throws: ``ArgParseError`` when tokens are invalid or incomplete.
  public func parse(_ argv: [String]) throws -> NotifyArgs {
    var args = NotifyArgs()
    var values = argv

    while !values.isEmpty {
      let flag = values.removeFirst()
      switch flag {
      case "-help", "--help":
        throw ArgParseError.helpRequested
      case "-title":
        args.title = try takeValue(flag, from: &values)
      case "-subtitle":
        args.subtitle = try takeValue(flag, from: &values)
      case "-message":
        args.message = try takeValue(flag, from: &values)
      case "-sound":
        args.sound = try takeValue(flag, from: &values)
      case "-group":
        args.group = try takeValue(flag, from: &values)
      case "-execute":
        args.execute = try takeValue(flag, from: &values)
      case "-activate":
        args.activate = try takeValue(flag, from: &values)
      case "-remove":
        args.remove = try takeValue(flag, from: &values)
      case "-sender-bundle-id":
        args.senderBundleID = try takeValue(flag, from: &values)
      case "-sender-app-path":
        args.senderAppPath = try takeValue(flag, from: &values)
      case "-origin-exec":
        args.originExecPath = try takeValue(flag, from: &values)
      case "-sender-mode":
        let modeValue = try takeValue(flag, from: &values).lowercased()
        guard let mode = SenderMode(rawValue: modeValue) else {
          throw ArgParseError.invalidSenderMode(modeValue)
        }
        args.senderMode = mode
      case "-spoofed-run":
        args.spoofedRun = true
      case "-fallback-run":
        args.fallbackRun = true
      case "-timeout":
        let raw = try takeValue(flag, from: &values)
        guard let timeout = TimeInterval(raw), timeout > 0 else {
          throw ArgParseError.invalidTimeout
        }
        args.timeout = timeout
      case "-generation":
        args.generation = try takeValue(flag, from: &values)
      default:
        throw ArgParseError.unknownFlag(flag)
      }
    }

    if args.remove == nil && args.message == nil {
      throw ArgParseError.missingMessage
    }

    return args
  }

  /// Consumes the next value token for a flag.
  ///
  /// - Parameters:
  ///   - flag: The current option token.
  ///   - argv: Remaining argument tokens.
  /// - Returns: The value associated with the provided flag.
  /// - Throws: ``ArgParseError/missingValue(_:)`` when no value remains.
  private func takeValue(_ flag: String, from argv: inout [String]) throws -> String {
    guard !argv.isEmpty else {
      throw ArgParseError.missingValue(flag)
    }
    return argv.removeFirst()
  }
}

/// Holds the parsed contents of a PID file: process ID and optional generation token.
public struct PidFileContent: Equatable, Sendable {
  public var pid: Int32
  public var generation: String?

  /// Creates a PID file content value.
  public init(pid: Int32, generation: String? = nil) {
    self.pid = pid
    self.generation = generation
  }
}

/// Formats a PID and optional generation token for writing to a PID file.
///
/// - Parameters:
///   - pid: The process identifier to record.
///   - generation: Optional generation token for supersession detection.
/// - Returns: Formatted string suitable for writing to the PID file.
public func formatPidFileContent(pid: Int32, generation: String?) -> String {
  if let generation {
    return "\(pid)\n\(generation)\n"
  }
  return "\(pid)\n"
}

/// Parses PID file content text into a structured value.
///
/// - Parameter text: Raw PID file content string.
/// - Returns: Parsed content, or `nil` when the PID is missing or invalid.
public func parsePidFileContent(_ text: String) -> PidFileContent? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }

  let lines = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
  guard let pidString = lines.first,
        let pid = Int32(pidString),
        pid > 0 else {
    return nil
  }

  let generation: String?
  if lines.count > 1 {
    let gen = String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines)
    generation = gen.isEmpty ? nil : gen
  } else {
    generation = nil
  }

  return PidFileContent(pid: pid, generation: generation)
}

/// Determines whether this process has been superseded by a newer notification instance.
///
/// - Parameters:
///   - ownGeneration: The generation token this process was launched with.
///   - fileGeneration: The generation token currently in the PID file.
/// - Returns: `true` when both generations are present and differ.
public func isSuperseded(ownGeneration: String?, fileGeneration: String?) -> Bool {
  guard let own = ownGeneration, let file = fileGeneration else { return false }
  return own != file
}

/// Normalizes optional string input by trimming whitespace and dropping empties.
///
/// - Parameter value: A potentially empty optional string.
/// - Returns: A trimmed non-empty string or `nil`.
public func normalizeOption(_ value: String?) -> String? {
  guard let value else { return nil }
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

/// Determines whether sender spoofing should run for the current arguments.
///
/// - Parameter args: Parsed runtime arguments.
/// - Returns: `true` when spoofing mode is enabled and sender identity exists.
public func senderSpoofEnabled(args: NotifyArgs) -> Bool {
  args.senderMode != .off
    && (normalizeOption(args.senderBundleID) != nil || normalizeOption(args.senderAppPath) != nil)
}

/// Produces a filesystem-safe path component for sender-specific directories.
///
/// - Parameter value: Raw sender identifier text.
/// - Returns: A sanitized path component or `"default"` when unsafe.
public func safePathComponent(_ value: String) -> String {
  let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
  let withoutSeparators = value
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "\\", with: "_")
  let converted = withoutSeparators.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
  let sanitized = String(converted)
  guard !sanitized.isEmpty else { return "default" }
  if sanitized == "." || sanitized == ".." || sanitized.contains("..") {
    return "default"
  }
  return sanitized
}

/// Produces a bundle-identifier-safe token for helper bundle identifiers.
///
/// - Parameter value: Raw bundle identifier component text.
/// - Returns: A sanitized token or `"sender"` when no safe characters remain.
public func safeBundleIDComponent(_ value: String) -> String {
  let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
  let converted = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
  let sanitized = String(converted).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
  return sanitized.isEmpty ? "sender" : sanitized
}

/// Builds the helper application bundle identifier used for spoofed relaunches.
///
/// - Parameters:
///   - baseBundleID: Optional base bundle identifier for this tool.
///   - senderBundleID: Sender bundle identifier used to scope helper identity.
/// - Returns: A spoof helper bundle identifier that does not reuse sender identity.
public func helperBundleID(baseBundleID: String?, senderBundleID: String) -> String {
  let base = normalizeOption(baseBundleID) ?? "com.gwk.claude-notify"
  return "\(base).spoof.\(safeBundleIDComponent(senderBundleID))"
}

/// Extracts ordered icon filename candidates from an app `Info.plist` dictionary.
///
/// - Parameter info: Parsed plist dictionary for an application bundle.
/// - Returns: Deduplicated icon filenames normalized to `.icns`.
public func iconCandidates(info: [String: Any]) -> [String] {
  /// Normalizes icon values to explicit `.icns` filenames.
  func normalizeIconName(_ name: String) -> String {
    name.contains(".") ? name : "\(name).icns"
  }

  var out: [String] = []

  if let iconFile = info["CFBundleIconFile"] as? String {
    out.append(normalizeIconName(iconFile))
  }

  if let icons = info["CFBundleIcons"] as? [String: Any],
     let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
     let files = primary["CFBundleIconFiles"] as? [String] {
    for item in files.reversed() {
      out.append(normalizeIconName(item))
    }
  }

  var seen = Set<String>()
  return out.filter { seen.insert($0).inserted }
}

private let flagsWithValues: Set<String> = [
  "-title", "-subtitle", "-message", "-sound", "-group", "-execute",
  "-activate", "-remove", "-timeout", "-sender-mode", "-sender-bundle-id",
  "-sender-app-path", "-origin-exec", "-generation"
]

private let internalMarkerFlags: Set<String> = [
  "-spoofed-run", "-fallback-run"
]

/// Rewrites CLI arguments while dropping selected internal flags.
///
/// - Parameters:
///   - argv: Original process arguments without executable name.
///   - dropStandaloneFlags: Flags removed without consuming trailing values.
///   - dropValueFlags: Value flags removed with their value when present.
///   - preserveDanglingValueFlags: Whether value flags missing a value should be preserved.
/// - Returns: Rewritten argument array.
private func rewriteArguments(
  from argv: [String],
  dropStandaloneFlags: Set<String> = internalMarkerFlags,
  dropValueFlags: Set<String>,
  preserveDanglingValueFlags: Bool
) -> [String] {
  var out: [String] = []
  var index = 0

  while index < argv.count {
    let flag = argv[index]
    if dropStandaloneFlags.contains(flag) {
      index += 1
      continue
    }

    guard flagsWithValues.contains(flag) else {
      out.append(flag)
      index += 1
      continue
    }

    let hasValue = index + 1 < argv.count
    if dropValueFlags.contains(flag) {
      index += hasValue ? 2 : 1
      continue
    }

    if hasValue {
      out.append(flag)
      out.append(argv[index + 1])
      index += 2
      continue
    }

    if preserveDanglingValueFlags {
      out.append(flag)
    }
    index += 1
  }

  return out
}

/// Rewrites arguments for non-spoof fallback execution.
///
/// - Parameter argv: Original process arguments without executable name.
/// - Returns: Arguments with spoof-only options removed and fallback markers applied.
public func buildFallbackArguments(from argv: [String]) -> [String] {
  var out = rewriteArguments(
    from: argv,
    dropValueFlags: ["-sender-mode", "-sender-bundle-id", "-sender-app-path", "-origin-exec", "-generation"],
    preserveDanglingValueFlags: false
  )

  out.append(contentsOf: ["-sender-mode", "off", "-fallback-run"])
  return out
}

/// Rewrites arguments for retrying spoof without isolated helper bundle ID.
///
/// - Parameter argv: Original process arguments without executable name.
/// - Returns: Arguments with relaunch-only options removed.
public func buildRetrySpoofArguments(from argv: [String]) -> [String] {
  rewriteArguments(
    from: argv,
    dropValueFlags: ["-origin-exec"],
    preserveDanglingValueFlags: false
  )
}

/// Rewrites arguments for helper-app relaunch while preserving user-facing flags.
///
/// - Parameters:
///   - argv: Original process arguments without executable name.
///   - originExecutablePath: Path to the original executable for fallback/retry runs.
///   - generation: Optional generation token to inject (used when generation came from env, not CLI).
/// - Returns: Relaunch arguments containing internal relaunch markers.
public func buildRelaunchArguments(from argv: [String], originExecutablePath: String?, generation: String? = nil) -> [String] {
  var out = rewriteArguments(
    from: argv,
    dropValueFlags: ["-origin-exec", "-generation"],
    preserveDanglingValueFlags: true
  )

  out.append("-spoofed-run")
  if let origin = normalizeOption(originExecutablePath) {
    out.append(contentsOf: ["-origin-exec", origin])
  }
  if let gen = normalizeOption(generation) {
    out.append(contentsOf: ["-generation", gen])
  }
  return out
}

/// Describes sender spoofing failures encountered during lookup or helper preparation.
public enum SenderSpoofError: LocalizedError {
  case missingSenderBundleID
  case senderAppNotFound(String)
  case senderAppPathInvalid(String)
  case unreadableSenderInfoPlist(String)
  case missingExecutablePath
  case helperDirectoryUnavailable
  case failedToSignHelper(String)

  public var errorDescription: String? {
    switch self {
    case .missingSenderBundleID:
      return "sender bundle id is required when sender app path is not provided"
    case .senderAppNotFound(let detail):
      return "sender app not found: \(detail)"
    case .senderAppPathInvalid(let path):
      return "sender app path is not a valid app bundle: \(path)"
    case .unreadableSenderInfoPlist(let path):
      return "unable to read sender Info.plist at \(path)"
    case .missingExecutablePath:
      return "unable to resolve current executable path"
    case .helperDirectoryUnavailable:
      return "unable to create spoof helper directory"
    case .failedToSignHelper(let detail):
      return "failed to sign spoof helper: \(detail)"
    }
  }
}

/// Captures sender app metadata used when preparing spoof helper bundles.
public struct SenderAppInfo {
  public let bundleID: String
  public let displayName: String
  public let appURL: URL
  public let iconFile: String?

  /// Creates a sender metadata container used by helper preparation.
  ///
  /// - Parameters:
  ///   - bundleID: Sender app bundle identifier.
  ///   - displayName: Display name for notifications and helper bundle metadata.
  ///   - appURL: URL of the sender app bundle.
  ///   - iconFile: Preferred icon filename inside sender bundle resources.
  public init(bundleID: String, displayName: String, appURL: URL, iconFile: String?) {
    self.bundleID = bundleID
    self.displayName = displayName
    self.appURL = appURL
    self.iconFile = iconFile
  }
}

/// Provides lookup dependencies for resolving sender app metadata.
public struct SenderResolver {
  public let bundleLookup: (String) -> URL?
  public let appRoots: [URL]
  public let fileManager: FileManager

  /// Creates a resolver from injected lookup and filesystem dependencies.
  ///
  /// - Parameters:
  ///   - bundleLookup: Resolves a bundle identifier to an app URL.
  ///   - appRoots: Root directories scanned when lookup returns no direct match.
  ///   - fileManager: Filesystem dependency used for scanning and validation.
  public init(
    bundleLookup: @escaping (String) -> URL?,
    appRoots: [URL],
    fileManager: FileManager = .default
  ) {
    self.bundleLookup = bundleLookup
    self.appRoots = appRoots
    self.fileManager = fileManager
  }

  /// Builds the default resolver backed by `NSWorkspace` and standard app roots.
  ///
  /// - Parameter fileManager: Filesystem dependency used for fallback root scanning.
  /// - Returns: A resolver configured for runtime use.
  public static func live(fileManager: FileManager = .default) -> SenderResolver {
    SenderResolver(
      bundleLookup: { bundleID in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
      },
      appRoots: [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
      ],
      fileManager: fileManager
    )
  }
}

/// Loads an application's `Info.plist` into a Swift dictionary.
///
/// - Parameter appURL: URL of the `.app` bundle.
/// - Returns: Parsed plist dictionary for the target app.
/// - Throws: ``SenderSpoofError/unreadableSenderInfoPlist(_:)`` when parsing fails.
public func readInfoPlist(appURL: URL) throws -> [String: Any] {
  let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
  guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
    throw SenderSpoofError.unreadableSenderInfoPlist(infoURL.path)
  }
  return dict
}

/// Resolves the preferred sender icon filename from bundle metadata/resources.
///
/// - Parameters:
///   - appURL: URL of the sender `.app` bundle.
///   - info: Parsed sender `Info.plist` dictionary.
///   - fileManager: Filesystem dependency used for file existence checks.
/// - Returns: The chosen `.icns` filename, or `nil` when no icon can be found.
public func resolveSenderIconFile(appURL: URL, info: [String: Any], fileManager: FileManager = .default) -> String? {
  let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)

  for candidate in iconCandidates(info: info) {
    let candidatePath = resourcesURL.appendingPathComponent(candidate).path
    if fileManager.fileExists(atPath: candidatePath) {
      return candidate
    }
  }

  guard let files = try? fileManager.contentsOfDirectory(atPath: resourcesURL.path) else {
    return nil
  }

  return files.sorted().first { $0.lowercased().hasSuffix(".icns") }
}

/// Resolves the sender application URL from explicit path or bundle identifier.
///
/// - Parameters:
///   - args: Parsed runtime arguments that include sender selection inputs.
///   - resolver: Lookup/scanning dependencies.
/// - Returns: URL of the matched sender `.app` bundle.
/// - Throws: ``SenderSpoofError`` when sender lookup cannot be completed.
public func resolveSenderAppURL(args: NotifyArgs, resolver: SenderResolver = .live()) throws -> URL {
  if let path = normalizeOption(args.senderAppPath) {
    let expanded = NSString(string: path).expandingTildeInPath
    var isDir = ObjCBool(false)
    guard resolver.fileManager.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
      throw SenderSpoofError.senderAppPathInvalid(expanded)
    }
    return URL(fileURLWithPath: expanded, isDirectory: true)
  }

  guard let bundleID = normalizeOption(args.senderBundleID) else {
    throw SenderSpoofError.missingSenderBundleID
  }

  if let url = resolver.bundleLookup(bundleID) {
    return url
  }

  for root in resolver.appRoots {
    guard let apps = try? resolver.fileManager.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      continue
    }

    for appURL in apps where appURL.pathExtension == "app" {
      guard let info = try? readInfoPlist(appURL: appURL) else {
        continue
      }
      if normalizeOption(info["CFBundleIdentifier"] as? String) == bundleID {
        return appURL
      }
    }
  }

  throw SenderSpoofError.senderAppNotFound("bundle id \(bundleID)")
}

/// Resolves sender metadata required to construct spoof helper bundles.
///
/// - Parameters:
///   - args: Parsed runtime arguments that include sender selection inputs.
///   - resolver: Lookup/scanning dependencies.
/// - Returns: Structured sender metadata used by helper preparation.
/// - Throws: ``SenderSpoofError`` when sender metadata cannot be resolved.
public func resolveSenderAppInfo(args: NotifyArgs, resolver: SenderResolver = .live()) throws -> SenderAppInfo {
  let appURL = try resolveSenderAppURL(args: args, resolver: resolver)
  let info = try readInfoPlist(appURL: appURL)

  let bundleID = normalizeOption(args.senderBundleID)
    ?? normalizeOption(info["CFBundleIdentifier"] as? String)
  guard let bundleID else {
    throw SenderSpoofError.missingSenderBundleID
  }

  let displayName = normalizeOption(info["CFBundleDisplayName"] as? String)
    ?? normalizeOption(info["CFBundleName"] as? String)
    ?? bundleID

  let iconFile = resolveSenderIconFile(appURL: appURL, info: info, fileManager: resolver.fileManager)
  return SenderAppInfo(bundleID: bundleID, displayName: displayName, appURL: appURL, iconFile: iconFile)
}

/// Writes a plist dictionary as XML at a target URL.
///
/// - Parameters:
///   - plist: Dictionary to serialize.
///   - url: Destination plist URL.
/// - Throws: Any serialization or file write error.
public func writeInfoPlist(_ plist: [String: Any], to url: URL) throws {
  let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
  try data.write(to: url, options: .atomic)
}

/// Performs ad-hoc code signing for a prepared helper app bundle.
///
/// - Parameters:
///   - helperAppURL: URL of the helper `.app` bundle.
///   - identifier: Bundle identifier to embed during signing.
/// - Throws: ``SenderSpoofError/failedToSignHelper(_:)`` when signing fails.
public func signHelperApp(helperAppURL: URL, identifier: String) throws {
  let task = Process()
  task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
  task.arguments = ["--force", "--deep", "--sign", "-", "--identifier", identifier, helperAppURL.path]

  let err = Pipe()
  task.standardError = err

  do {
    try task.run()
  } catch {
    throw SenderSpoofError.failedToSignHelper(error.localizedDescription)
  }
  let errData = err.fileHandleForReading.readDataToEndOfFile()
  task.waitUntilExit()

  guard task.terminationStatus == 0 else {
    let detail = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    throw SenderSpoofError.failedToSignHelper(detail ?? "codesign exited \(task.terminationStatus)")
  }
}

/// Controls filesystem and signing behavior for spoof helper preparation.
public struct HelperPreparationOptions {
  public var isolateHelperBundleID: Bool
  public var baseBundleID: String?
  public var baseDirectories: [URL]
  public var fileManager: FileManager
  public var signer: (URL, String) throws -> Void

  /// Creates helper preparation options with overridable dependencies.
  ///
  /// - Parameters:
  ///   - isolateHelperBundleID: Whether helper bundle IDs should be isolated from sender IDs.
  ///   - baseBundleID: Optional base bundle ID used when isolation is enabled.
  ///   - baseDirectories: Candidate parent directories for helper output.
  ///   - fileManager: Filesystem dependency used during helper construction.
  ///   - signer: Signing function applied to the generated helper app.
  public init(
    isolateHelperBundleID: Bool = false,
    baseBundleID: String? = Bundle.main.bundleIdentifier,
    baseDirectories: [URL]? = nil,
    fileManager: FileManager = .default,
    signer: @escaping (URL, String) throws -> Void = signHelperApp
  ) {
    self.isolateHelperBundleID = isolateHelperBundleID
    self.baseBundleID = baseBundleID
    self.baseDirectories = baseDirectories ?? Self.defaultBaseDirectories(fileManager: fileManager)
    self.fileManager = fileManager
    self.signer = signer
  }

  /// Provides default helper output directories in cache-first order.
  ///
  /// - Parameter fileManager: Filesystem dependency used to resolve home paths.
  /// - Returns: Candidate directories used by helper preparation.
  public static func defaultBaseDirectories(fileManager: FileManager = .default) -> [URL] {
    [
      fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/claude-notify/sender", isDirectory: true),
      URL(fileURLWithPath: "/tmp/claude-notify/sender", isDirectory: true)
    ]
  }
}

/// Prepares a signed helper executable configured to post as the sender app.
///
/// - Parameters:
///   - sender: Sender app metadata used for helper branding and identifiers.
///   - sourceExecutablePath: Path of the claude-notify executable to copy.
///   - options: Filesystem/signing options for helper construction.
/// - Returns: URL of the generated helper executable inside the helper app bundle.
/// - Throws: ``SenderSpoofError`` or filesystem/signing errors when preparation fails.
public func prepareSpoofHelper(
  sender: SenderAppInfo,
  sourceExecutablePath: String,
  options: HelperPreparationOptions = HelperPreparationOptions()
) throws -> URL {
  let fm = options.fileManager
  guard fm.isExecutableFile(atPath: sourceExecutablePath) else {
    throw SenderSpoofError.missingExecutablePath
  }

  let spoofHelperBundleID = options.isolateHelperBundleID
    ? helperBundleID(baseBundleID: options.baseBundleID, senderBundleID: sender.bundleID)
    : sender.bundleID

  var lastError: Error?

  for base in options.baseDirectories {
    do {
      let helperBase = base.appendingPathComponent(safePathComponent(sender.bundleID), isDirectory: true)
      let helperApp = helperBase.appendingPathComponent("claude-notify.app", isDirectory: true)
      let contentsURL = helperApp.appendingPathComponent("Contents", isDirectory: true)
      let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
      let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
      let helperExecutable = macOSURL.appendingPathComponent("claude-notify")
      let helperInfoPlist = contentsURL.appendingPathComponent("Info.plist")
      let helperPkgInfo = contentsURL.appendingPathComponent("PkgInfo")

      try fm.createDirectory(at: macOSURL, withIntermediateDirectories: true)
      try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

      if fm.fileExists(atPath: helperExecutable.path) {
        try fm.removeItem(at: helperExecutable)
      }
      try fm.copyItem(atPath: sourceExecutablePath, toPath: helperExecutable.path)

      var plist: [String: Any] = [
        "CFBundleDisplayName": sender.displayName,
        "CFBundleExecutable": "claude-notify",
        "CFBundleIdentifier": spoofHelperBundleID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": sender.displayName,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSUIElement": true
      ]

      if let iconFile = sender.iconFile {
        let sourceIcon = sender.appURL.appendingPathComponent("Contents/Resources/\(iconFile)")
        let destIcon = resourcesURL.appendingPathComponent(iconFile)
        if fm.fileExists(atPath: sourceIcon.path) {
          if fm.fileExists(atPath: destIcon.path) {
            try fm.removeItem(at: destIcon)
          }
          try fm.copyItem(at: sourceIcon, to: destIcon)
          plist["CFBundleIconFile"] = iconFile
        }
      }

      try writeInfoPlist(plist, to: helperInfoPlist)
      try? "APPL????".write(to: helperPkgInfo, atomically: true, encoding: .utf8)
      try options.signer(helperApp, spoofHelperBundleID)
      return helperExecutable
    } catch {
      lastError = error
      continue
    }
  }

  if let lastError {
    throw lastError
  }
  throw SenderSpoofError.helperDirectoryUnavailable
}
