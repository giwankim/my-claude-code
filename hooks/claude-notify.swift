import Cocoa
import UserNotifications

// MARK: - Argument parsing

enum SenderMode: String {
  case auto
  case off
  case required
}

struct Args {
  var title = "Notification"
  var subtitle: String?
  var message: String?
  var sound: String?
  var group: String?
  var execute: String?
  var activate: String?
  var remove: String?
  var senderBundleID: String?
  var senderAppPath: String?
  var originExecPath: String?
  var senderMode: SenderMode = .off
  var spoofedRun = false
  var fallbackRun = false
  var timeout: TimeInterval = 90
}

func usage() {
  let text = """
    Usage: claude-notify [options]
      -title     <string>   Notification title
      -subtitle  <string>   Notification subtitle
      -message   <string>   Notification body (required unless -remove)
      -sound     <string>   Sound name (e.g. "default")
      -group     <string>   Group ID (replaces previous notification in group)
      -execute   <string>   Shell command to run on click
      -activate  <string>   Bundle ID to activate on click
      -remove    <string>   Remove delivered notifications for group and exit
      -sender-bundle-id <id>    Bundle ID to spoof as sender
      -sender-app-path  <path>  Explicit .app path for spoof metadata/icon
      -sender-mode      <mode>  Spoof behavior: auto|off|required
      -origin-exec      <path>  Internal: original executable path for fallback
      -fallback-run             Internal: marks a non-spoof fallback run
      -timeout   <seconds>  Seconds to wait for click (default: 90)
      -help                 Show this help
    """
  FileHandle.standardError.write(Data(text.utf8))
}

func warn(_ msg: String) {
  FileHandle.standardError.write(Data("Error: \(msg)\n".utf8))
}

func warning(_ msg: String) {
  FileHandle.standardError.write(Data("Warning: \(msg)\n".utf8))
}

func die(_ msg: String) -> Never {
  warn(msg)
  removePid()
  exit(1)
}

func exitClean() -> Never {
  removePid()
  exit(0)
}

func parseArgs() -> Args {
  var args = Args()
  var argv = Array(CommandLine.arguments.dropFirst())

  while !argv.isEmpty {
    let flag = argv.removeFirst()
    switch flag {
    case "-help", "--help":
      usage()
      exit(1)
    case "-title":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.title = argv.removeFirst()
    case "-subtitle":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.subtitle = argv.removeFirst()
    case "-message":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.message = argv.removeFirst()
    case "-sound":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.sound = argv.removeFirst()
    case "-group":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.group = argv.removeFirst()
    case "-execute":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.execute = argv.removeFirst()
    case "-activate":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.activate = argv.removeFirst()
    case "-remove":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.remove = argv.removeFirst()
    case "-sender-bundle-id":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.senderBundleID = argv.removeFirst()
    case "-sender-app-path":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.senderAppPath = argv.removeFirst()
    case "-origin-exec":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      args.originExecPath = argv.removeFirst()
    case "-sender-mode":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      let value = argv.removeFirst().lowercased()
      guard let mode = SenderMode(rawValue: value) else {
        die("invalid sender mode: \(value) (expected auto|off|required)")
      }
      args.senderMode = mode
    case "-spoofed-run":
      args.spoofedRun = true
    case "-fallback-run":
      args.fallbackRun = true
    case "-timeout":
      guard !argv.isEmpty else { die("missing value for \(flag)") }
      guard let t = TimeInterval(argv.removeFirst()), t > 0 else { die("invalid timeout") }
      args.timeout = t
    default:
      die("unknown flag: \(flag)")
    }
  }

  if args.remove == nil && args.message == nil {
    FileHandle.standardError.write(Data("Error: -message is required\n".utf8))
    usage()
    exit(1)
  }

  return args
}

// MARK: - PID file management

let pidPath = "/tmp/claude-notify.pid"

func currentExecutableName() -> String {
  let path = normalizeOption(currentExecutablePath())
    ?? normalizeOption(CommandLine.arguments.first)
    ?? "claude-notify"
  return URL(fileURLWithPath: path).lastPathComponent
}

func processExecutableName(pid: pid_t) -> String? {
  var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
  let len = proc_name(pid, &buf, UInt32(buf.count))
  guard len > 0 else { return nil }
  let name = String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
  return name.isEmpty ? nil : name
}

func killPrevious() {
  guard let data = try? String(contentsOfFile: pidPath, encoding: .utf8),
        let pid = pid_t(data.trimmingCharacters(in: .whitespacesAndNewlines)),
        pid > 0 else { return }

  guard kill(pid, 0) == 0 else {
    if errno == ESRCH {
      removePid()
    }
    return
  }

  let expectedName = currentExecutableName()
  if let runningName = processExecutableName(pid: pid), runningName != expectedName {
    warning("pid file points to \(runningName) (expected \(expectedName)); skipping prior-process kill")
    removePid()
    return
  }

  kill(pid, SIGTERM)
  // Brief wait for the previous process to clean up.
  usleep(100_000) // 100ms
}

func writePid() {
  try? "\(getpid())".write(toFile: pidPath, atomically: true, encoding: .utf8)
}

func removePid() {
  try? FileManager.default.removeItem(atPath: pidPath)
}

func installSignalHandlers() {
  let handler: @convention(c) (Int32) -> Void = { _ in
    removePid()
    exit(0)
  }
  signal(SIGTERM, handler)
  signal(SIGINT, handler)
}

// MARK: - Notification delegate

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  let args: Args

  init(args: Args) {
    self.args = args
  }

  // Called when user clicks the notification.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    completionHandler()

    if let cmd = args.execute {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/bin/sh")
      task.arguments = ["-c", cmd]
      do {
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
          warning("click execute command exited \(task.terminationStatus)")
        }
      } catch {
        warning("failed to run click execute command: \(error.localizedDescription)")
      }
    }

    if let bundleID = args.activate {
      // Activate target app after command execution so focus lands there.
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      task.arguments = ["-b", bundleID]
      do {
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
          warning("click activate command exited \(task.terminationStatus) for \(bundleID)")
        }
      } catch {
        warning("failed to activate \(bundleID): \(error.localizedDescription)")
      }
    }

    removePid()
    exit(0)
  }

  // Show notifications even when app is foreground.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}

// MARK: - Remove mode

func handleRemove(group: String) -> Never {
  let center = UNUserNotificationCenter.current()
  center.removeDeliveredNotifications(withIdentifiers: [group])
  center.removePendingNotificationRequests(withIdentifiers: [group])
  // Give the center a moment to process.
  usleep(200_000)
  exit(0)
}

// MARK: - Sender spoofing

enum SenderSpoofError: LocalizedError {
  case missingSenderBundleID
  case senderAppNotFound(String)
  case senderAppPathInvalid(String)
  case unreadableSenderInfoPlist(String)
  case missingExecutablePath
  case helperDirectoryUnavailable
  case failedToSignHelper(String)
  case failedToLaunchHelper(String)

  var errorDescription: String? {
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
    case .failedToLaunchHelper(let detail):
      return "failed to launch spoof helper: \(detail)"
    }
  }
}

struct SenderAppInfo {
  let bundleID: String
  let displayName: String
  let appURL: URL
  let iconFile: String?
}

func normalizeOption(_ value: String?) -> String? {
  guard let value = value else { return nil }
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

func senderSpoofEnabled(args: Args) -> Bool {
  args.senderMode != .off && (normalizeOption(args.senderBundleID) != nil || normalizeOption(args.senderAppPath) != nil)
}

func safePathComponent(_ value: String) -> String {
  let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
  let converted = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
  let sanitized = String(converted)
  return sanitized.isEmpty ? "default" : sanitized
}

func safeBundleIDComponent(_ value: String) -> String {
  let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
  let converted = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
  let sanitized = String(converted).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
  return sanitized.isEmpty ? "sender" : sanitized
}

func helperBundleID(for senderBundleID: String) -> String {
  let baseID = normalizeOption(Bundle.main.bundleIdentifier) ?? "com.gwk.claude-notify"
  return "\(baseID).spoof.\(safeBundleIDComponent(senderBundleID))"
}

func useIsolatedHelperBundleID() -> Bool {
  ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID"] == "1"
}

func allowNonIsolatedSpoofRetry() -> Bool {
  ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY"] == "1"
}

func readInfoPlist(appURL: URL) throws -> [String: Any] {
  let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
  guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
    throw SenderSpoofError.unreadableSenderInfoPlist(infoURL.path)
  }
  return dict
}

func iconCandidates(info: [String: Any]) -> [String] {
  func normalizeIcon(_ name: String) -> String {
    name.contains(".") ? name : "\(name).icns"
  }

  var out: [String] = []

  if let iconFile = info["CFBundleIconFile"] as? String {
    out.append(normalizeIcon(iconFile))
  }

  if let icons = info["CFBundleIcons"] as? [String: Any],
     let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
     let files = primary["CFBundleIconFiles"] as? [String] {
    for item in files.reversed() {
      out.append(normalizeIcon(item))
    }
  }

  var seen = Set<String>()
  return out.filter { seen.insert($0).inserted }
}

func resolveSenderIconFile(appURL: URL, info: [String: Any]) -> String? {
  let fm = FileManager.default
  let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)

  for candidate in iconCandidates(info: info) {
    let candidatePath = resourcesURL.appendingPathComponent(candidate).path
    if fm.fileExists(atPath: candidatePath) {
      return candidate
    }
  }

  guard let files = try? fm.contentsOfDirectory(atPath: resourcesURL.path) else {
    return nil
  }

  return files.sorted().first { $0.lowercased().hasSuffix(".icns") }
}

func resolveSenderAppURL(args: Args) throws -> URL {
  let fm = FileManager.default

  if let path = normalizeOption(args.senderAppPath) {
    let expanded = NSString(string: path).expandingTildeInPath
    var isDir = ObjCBool(false)
    guard fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
      throw SenderSpoofError.senderAppPathInvalid(expanded)
    }
    return URL(fileURLWithPath: expanded, isDirectory: true)
  }

  guard let bundleID = normalizeOption(args.senderBundleID) else {
    throw SenderSpoofError.missingSenderBundleID
  }

  if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
    return url
  }

  let appRoots = [
    URL(fileURLWithPath: "/Applications", isDirectory: true),
    fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
  ]
  for root in appRoots {
    guard let apps = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
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

func resolveSenderAppInfo(args: Args) throws -> SenderAppInfo {
  let appURL = try resolveSenderAppURL(args: args)
  let info = try readInfoPlist(appURL: appURL)

  let bundleID = normalizeOption(args.senderBundleID)
    ?? normalizeOption(info["CFBundleIdentifier"] as? String)
  guard let bundleID = bundleID else {
    throw SenderSpoofError.missingSenderBundleID
  }

  let displayName = normalizeOption(info["CFBundleDisplayName"] as? String)
    ?? normalizeOption(info["CFBundleName"] as? String)
    ?? bundleID

  let iconFile = resolveSenderIconFile(appURL: appURL, info: info)
  return SenderAppInfo(bundleID: bundleID, displayName: displayName, appURL: appURL, iconFile: iconFile)
}

func currentExecutablePath() -> String? {
  if let executablePath = Bundle.main.executablePath {
    return executablePath
  }

  guard let argv0 = CommandLine.arguments.first, !argv0.isEmpty else {
    return nil
  }

  if argv0.hasPrefix("/") {
    return argv0
  }

  return URL(fileURLWithPath: argv0, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).path
}

func writeInfoPlist(_ plist: [String: Any], to url: URL) throws {
  let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
  try data.write(to: url, options: .atomic)
}

func signHelperApp(helperAppURL: URL, identifier: String) throws {
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

func buildFallbackArgumentsFromCurrentProcess() -> [String] {
  let argv = Array(CommandLine.arguments.dropFirst())
  var out: [String] = []
  let flagsWithValues: Set<String> = [
    "-title", "-subtitle", "-message", "-sound", "-group", "-execute",
    "-activate", "-remove", "-timeout", "-sender-mode", "-sender-bundle-id",
    "-sender-app-path", "-origin-exec"
  ]
  var i = 0
  while i < argv.count {
    let flag = argv[i]
    if flag == "-spoofed-run" || flag == "-fallback-run" {
      i += 1
      continue
    }
    if flagsWithValues.contains(flag) {
      if i + 1 < argv.count {
        // Strip sender-specific flags; keep all other user-supplied args.
        if flag != "-sender-mode" && flag != "-sender-bundle-id" && flag != "-sender-app-path" && flag != "-origin-exec" {
          out.append(flag)
          out.append(argv[i + 1])
        }
      }
      i += 2
      continue
    }
    out.append(flag)
    i += 1
  }
  out.append(contentsOf: ["-sender-mode", "off", "-fallback-run"])
  return out
}

func buildRetrySpoofArgumentsFromCurrentProcess() -> [String] {
  let argv = Array(CommandLine.arguments.dropFirst())
  var out: [String] = []
  let flagsWithValues: Set<String> = [
    "-title", "-subtitle", "-message", "-sound", "-group", "-execute",
    "-activate", "-remove", "-timeout", "-sender-mode", "-sender-bundle-id",
    "-sender-app-path", "-origin-exec"
  ]
  var i = 0
  while i < argv.count {
    let flag = argv[i]
    if flag == "-spoofed-run" || flag == "-fallback-run" {
      i += 1
      continue
    }
    if flagsWithValues.contains(flag) {
      if i + 1 < argv.count {
        if flag != "-origin-exec" {
          out.append(flag)
          out.append(argv[i + 1])
        }
      }
      i += 2
      continue
    }
    out.append(flag)
    i += 1
  }
  return out
}

func tryAutoFallbackIfNeeded(args: Args) {
  guard args.senderMode == .auto, args.spoofedRun, !args.fallbackRun else { return }
  guard let originPath = normalizeOption(args.originExecPath) else {
    warning("sender spoof fallback skipped: missing origin executable path")
    return
  }

  if useIsolatedHelperBundleID() && allowNonIsolatedSpoofRetry() {
    let retryTask = Process()
    retryTask.executableURL = URL(fileURLWithPath: originPath)
    retryTask.arguments = buildRetrySpoofArgumentsFromCurrentProcess()
    var env = ProcessInfo.processInfo.environment
    env["CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID"] = "0"
    retryTask.environment = env
    do {
      try retryTask.run()
      warning("sender spoof isolated helper failed; retrying without isolated helper bundle id")
      removePid()
      exit(0)
    } catch {
      warning("isolated helper retry launch failed: \(error.localizedDescription)")
    }
  }

  let fallbackArgs = buildFallbackArgumentsFromCurrentProcess()
  let task = Process()
  task.executableURL = URL(fileURLWithPath: originPath)
  task.arguments = fallbackArgs
  do {
    try task.run()
    warning("sender spoof failed; launched fallback notification without spoof")
    removePid()
    exit(0)
  } catch {
    warning("sender spoof fallback launch failed: \(error.localizedDescription)")
  }
}

func prepareSpoofHelper(sender: SenderAppInfo) throws -> URL {
  let fm = FileManager.default

  guard let sourceExecutable = currentExecutablePath(), fm.isExecutableFile(atPath: sourceExecutable) else {
    throw SenderSpoofError.missingExecutablePath
  }
  let spoofHelperBundleID = useIsolatedHelperBundleID() ? helperBundleID(for: sender.bundleID) : sender.bundleID

  let baseCandidates = [
    fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/claude-notify/sender", isDirectory: true),
    URL(fileURLWithPath: "/tmp/claude-notify/sender", isDirectory: true)
  ]

  var lastError: Error?

  for base in baseCandidates {
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
      try fm.copyItem(atPath: sourceExecutable, toPath: helperExecutable.path)

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
        } else {
          warning("sender icon not found at \(sourceIcon.path); continuing without icon copy")
        }
      } else {
        warning("sender icon not found in app metadata; continuing without icon copy")
      }

      try writeInfoPlist(plist, to: helperInfoPlist)
      try? "APPL????".write(to: helperPkgInfo, atomically: true, encoding: .utf8)
      try signHelperApp(helperAppURL: helperApp, identifier: spoofHelperBundleID)
      return helperExecutable
    } catch {
      lastError = error
      continue
    }
  }

  if let lastError = lastError {
    throw lastError
  }
  throw SenderSpoofError.helperDirectoryUnavailable
}

func relaunchViaSpoofHelper(executableURL: URL) throws -> Int32 {
  var forwardedArgs = Array(CommandLine.arguments.dropFirst())
  forwardedArgs.removeAll(where: { $0 == "-spoofed-run" })
  forwardedArgs.removeAll(where: { $0 == "-fallback-run" })
  forwardedArgs.removeAll(where: { $0 == "-origin-exec" })
  forwardedArgs.append("-spoofed-run")
  if let origin = currentExecutablePath() {
    forwardedArgs.append(contentsOf: ["-origin-exec", origin])
  }

  let helperAppURL = executableURL
    .deletingLastPathComponent() // MacOS
    .deletingLastPathComponent() // Contents
    .deletingLastPathComponent() // *.app

  if let marker = ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_TEST_RELAUNCH_MARKER"] {
    let line = "open \(helperAppURL.path)\n"
    try? line.write(toFile: marker, atomically: true, encoding: .utf8)
  }
  if ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_TEST_SKIP_RELAUNCH"] == "1" {
    return 0
  }

  let task = Process()
  task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
  task.arguments = ["-n", "-W", helperAppURL.path, "--args"] + forwardedArgs
  do {
    try task.run()
  } catch {
    throw SenderSpoofError.failedToLaunchHelper(error.localizedDescription)
  }
  task.waitUntilExit()
  return task.terminationStatus
}

// MARK: - Post notification

func postNotification(args: Args, delegate: NotificationDelegate) {
  let center = UNUserNotificationCenter.current()
  center.delegate = delegate

  center.requestAuthorization(options: [.alert, .sound]) { granted, error in
    if !granted {
      if let error = error {
        warn("notification authorization denied: \(error.localizedDescription)")
      } else {
        warn("notification authorization denied")
      }
      // For spoofed auto mode, fall back immediately. Otherwise keep going and
      // still attempt post, since some setups deliver despite denied status.
      if args.senderMode == .auto && args.spoofedRun && !args.fallbackRun {
        tryAutoFallbackIfNeeded(args: args)
        return
      }
    }

    if ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR"] == "1" {
      warn("failed to post notification: forced test failure")
      tryAutoFallbackIfNeeded(args: args)
      return
    }

    // Try to post regardless — some configurations still deliver.
    let content = UNMutableNotificationContent()
    content.title = args.title
    if let subtitle = args.subtitle {
      content.subtitle = subtitle
    }
    content.body = args.message!
    if let sound = args.sound {
      content.sound = sound == "default" ? .default : UNNotificationSound(named: UNNotificationSoundName(sound))
    }

    let identifier = args.group ?? UUID().uuidString
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

    center.add(request) { error in
      if let error = error {
        warn("failed to post notification: \(error.localizedDescription)")
        tryAutoFallbackIfNeeded(args: args)
      }
    }
  }
}

// MARK: - Main

let args = parseArgs()

if let group = args.remove {
  handleRemove(group: group)
}

if senderSpoofEnabled(args: args) && !args.spoofedRun {
  do {
    let sender = try resolveSenderAppInfo(args: args)
    let helperExecutable = try prepareSpoofHelper(sender: sender)
    let status = try relaunchViaSpoofHelper(executableURL: helperExecutable)
    exit(status)
  } catch {
    let message = "sender spoof unavailable: \(error.localizedDescription)"
    switch args.senderMode {
    case .required:
      die(message)
    case .auto:
      warning(message)
    case .off:
      break
    }
  }
}

killPrevious()
writePid()
installSignalHandlers()

let delegate = NotificationDelegate(args: args)
postNotification(args: args, delegate: delegate)

// Timeout: exit after N seconds if no click.
DispatchQueue.main.asyncAfter(deadline: .now() + args.timeout) {
  removePid()
  exit(0)
}

RunLoop.main.run()
