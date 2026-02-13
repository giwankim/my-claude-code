import AppKit
import Foundation

public enum SenderMode: String, CaseIterable, Sendable {
  case auto
  case off
  case required
}

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

  public init() {}
}

public enum ArgParseError: Error, Equatable {
  case helpRequested
  case missingValue(String)
  case invalidTimeout
  case invalidSenderMode(String)
  case unknownFlag(String)
  case missingMessage
}

public struct ArgumentParser {
  public init() {}

  public static func parse(_ argv: [String]) throws -> NotifyArgs {
    try ArgumentParser().parse(argv)
  }

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
      default:
        throw ArgParseError.unknownFlag(flag)
      }
    }

    if args.remove == nil && args.message == nil {
      throw ArgParseError.missingMessage
    }

    return args
  }

  private func takeValue(_ flag: String, from argv: inout [String]) throws -> String {
    guard !argv.isEmpty else {
      throw ArgParseError.missingValue(flag)
    }
    return argv.removeFirst()
  }
}

public func normalizeOption(_ value: String?) -> String? {
  guard let value else { return nil }
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

public func senderSpoofEnabled(args: NotifyArgs) -> Bool {
  args.senderMode != .off
    && (normalizeOption(args.senderBundleID) != nil || normalizeOption(args.senderAppPath) != nil)
}

public func safePathComponent(_ value: String) -> String {
  let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
  let converted = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
  let sanitized = String(converted)
  return sanitized.isEmpty ? "default" : sanitized
}

public func safeBundleIDComponent(_ value: String) -> String {
  let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
  let converted = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
  let sanitized = String(converted).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
  return sanitized.isEmpty ? "sender" : sanitized
}

public func helperBundleID(baseBundleID: String?, senderBundleID: String) -> String {
  let base = normalizeOption(baseBundleID) ?? "com.gwk.claude-notify"
  return "\(base).spoof.\(safeBundleIDComponent(senderBundleID))"
}

public func iconCandidates(info: [String: Any]) -> [String] {
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
  "-sender-app-path", "-origin-exec"
]

public func buildFallbackArguments(from argv: [String]) -> [String] {
  var out: [String] = []
  var index = 0

  while index < argv.count {
    let flag = argv[index]
    if flag == "-spoofed-run" || flag == "-fallback-run" {
      index += 1
      continue
    }
    if flagsWithValues.contains(flag) {
      if index + 1 < argv.count,
         flag != "-sender-mode",
         flag != "-sender-bundle-id",
         flag != "-sender-app-path",
         flag != "-origin-exec" {
        out.append(flag)
        out.append(argv[index + 1])
      }
      index += 2
      continue
    }
    out.append(flag)
    index += 1
  }

  out.append(contentsOf: ["-sender-mode", "off", "-fallback-run"])
  return out
}

public func buildRetrySpoofArguments(from argv: [String]) -> [String] {
  var out: [String] = []
  var index = 0

  while index < argv.count {
    let flag = argv[index]
    if flag == "-spoofed-run" || flag == "-fallback-run" {
      index += 1
      continue
    }
    if flagsWithValues.contains(flag) {
      if index + 1 < argv.count, flag != "-origin-exec" {
        out.append(flag)
        out.append(argv[index + 1])
      }
      index += 2
      continue
    }
    out.append(flag)
    index += 1
  }

  return out
}

public func buildRelaunchArguments(from argv: [String], originExecutablePath: String?) -> [String] {
  var out: [String] = []
  var index = 0

  while index < argv.count {
    let flag = argv[index]
    if flag == "-spoofed-run" || flag == "-fallback-run" {
      index += 1
      continue
    }
    if flag == "-origin-exec" {
      if index + 1 < argv.count {
        index += 2
      } else {
        index += 1
      }
      continue
    }
    out.append(flag)
    index += 1
  }

  out.append("-spoofed-run")
  if let origin = normalizeOption(originExecutablePath) {
    out.append(contentsOf: ["-origin-exec", origin])
  }
  return out
}

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

public struct SenderAppInfo {
  public let bundleID: String
  public let displayName: String
  public let appURL: URL
  public let iconFile: String?

  public init(bundleID: String, displayName: String, appURL: URL, iconFile: String?) {
    self.bundleID = bundleID
    self.displayName = displayName
    self.appURL = appURL
    self.iconFile = iconFile
  }
}

public struct SenderResolver {
  public let bundleLookup: (String) -> URL?
  public let appRoots: [URL]
  public let fileManager: FileManager

  public init(
    bundleLookup: @escaping (String) -> URL?,
    appRoots: [URL],
    fileManager: FileManager = .default
  ) {
    self.bundleLookup = bundleLookup
    self.appRoots = appRoots
    self.fileManager = fileManager
  }

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

public func readInfoPlist(appURL: URL) throws -> [String: Any] {
  let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
  guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
    throw SenderSpoofError.unreadableSenderInfoPlist(infoURL.path)
  }
  return dict
}

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

public func writeInfoPlist(_ plist: [String: Any], to url: URL) throws {
  let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
  try data.write(to: url, options: .atomic)
}

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
  task.waitUntilExit()

  guard task.terminationStatus == 0 else {
    let data = err.fileHandleForReading.readDataToEndOfFile()
    let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    throw SenderSpoofError.failedToSignHelper(detail ?? "codesign exited \(task.terminationStatus)")
  }
}

public struct HelperPreparationOptions {
  public var isolateHelperBundleID: Bool
  public var baseBundleID: String?
  public var baseDirectories: [URL]
  public var fileManager: FileManager
  public var signer: (URL, String) throws -> Void

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

  public static func defaultBaseDirectories(fileManager: FileManager = .default) -> [URL] {
    [
      fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/claude-notify/sender", isDirectory: true),
      URL(fileURLWithPath: "/tmp/claude-notify/sender", isDirectory: true)
    ]
  }
}

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
