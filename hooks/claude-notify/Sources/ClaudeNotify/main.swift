import Cocoa
import NotifyCore
@preconcurrency import UserNotifications

/// Prints CLI usage text to standard error.
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

/// Prints an error-prefixed message to standard error.
func warn(_ msg: String) {
  FileHandle.standardError.write(Data("Error: \(msg)\n".utf8))
}

/// Prints a warning-prefixed message to standard error.
func warning(_ msg: String) {
  FileHandle.standardError.write(Data("Warning: \(msg)\n".utf8))
}

/// Emits a fatal error message, cleans runtime state, and terminates.
func die(_ msg: String) -> Never {
  warn(msg)
  removePid()
  exit(1)
}

/// Removes runtime PID state and exits successfully.
func exitClean() -> Never {
  removePid()
  exit(0)
}

/// Parses command-line arguments and exits on parse errors.
func parseArgs() -> NotifyArgs {
  do {
    return try ArgumentParser.parse(Array(CommandLine.arguments.dropFirst()))
  } catch let parseError as ArgParseError {
    switch parseError {
    case .helpRequested:
      usage()
      exit(0)
    case .missingMessage:
      FileHandle.standardError.write(Data("Error: -message is required\n".utf8))
      usage()
      exit(1)
    case .missingValue(let flag):
      die("missing value for \(flag)")
    case .invalidTimeout:
      die("invalid timeout")
    case .invalidSenderMode(let mode):
      die("invalid sender mode: \(mode) (expected auto|off|required)")
    case .unknownFlag(let flag):
      die("unknown flag: \(flag)")
    }
  } catch {
    die("argument parsing failed: \(error.localizedDescription)")
  }
}

// MARK: - PID file management

/// Builds the default PID file path in a user-scoped temporary/cache directory.
func defaultPidPath() -> String {
  let fm = FileManager.default
  let baseDirectory: URL
  if let tmpDir = normalizeOption(ProcessInfo.processInfo.environment["TMPDIR"]) {
    baseDirectory = URL(fileURLWithPath: tmpDir, isDirectory: true)
  } else if let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
    baseDirectory = cacheDir
  } else {
    baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
  }

  return baseDirectory
    .appendingPathComponent("claude-notify", isDirectory: true)
    .appendingPathComponent("claude-notify.pid")
    .path
}

let pidPath = normalizeOption(ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_PID_FILE"])
  ?? defaultPidPath()

nonisolated(unsafe) private let pidPathCString: UnsafeMutablePointer<CChar> = {
  let cString = Array(pidPath.utf8CString)
  let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: cString.count)
  cString.withUnsafeBufferPointer { buffer in
    pointer.initialize(from: buffer.baseAddress!, count: buffer.count)
  }
  return pointer
}()

/// Ensures the PID parent directory exists with restricted permissions.
func ensurePidDirectoryExists() -> Bool {
  let dir = URL(fileURLWithPath: pidPath).deletingLastPathComponent()
  do {
    try FileManager.default.createDirectory(
      at: dir,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    return true
  } catch {
    warning("failed to create pid directory at \(dir.path): \(error.localizedDescription)")
    return false
  }
}

/// Reads and validates a PID value from the runtime PID file.
func readPidFromFile() -> pid_t? {
  let fd = open(pidPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
  guard fd >= 0 else { return nil }
  defer { close(fd) }

  var buffer = [UInt8](repeating: 0, count: 64)
  let size = read(fd, &buffer, buffer.count)
  guard size > 0 else { return nil }

  guard let text = String(bytes: buffer.prefix(Int(size)), encoding: .utf8) else { return nil }
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard let pid = pid_t(trimmed), pid > 0 else { return nil }
  return pid
}

/// Resolves the current executable path for relaunch and identity checks.
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

  return URL(
    fileURLWithPath: argv0,
    relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ).path
}

/// Resolves the executable basename used for process ownership checks.
func currentExecutableName() -> String {
  let path = normalizeOption(currentExecutablePath())
    ?? normalizeOption(CommandLine.arguments.first)
    ?? "claude-notify"
  return URL(fileURLWithPath: path).lastPathComponent
}

/// Resolves process executable name for a running PID.
func processExecutableName(pid: pid_t) -> String? {
  var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
  let len = proc_name(pid, &buf, UInt32(buf.count))
  guard len > 0 else { return nil }
  let data = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
  guard let name = String(bytes: data, encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines)
  else { return nil }
  return name.isEmpty ? nil : name
}

/// Waits for a PID to disappear from the process table.
func waitForProcessExit(_ pid: pid_t, attempts: Int = 20, intervalUsec: useconds_t = 100_000) -> Bool {
  for _ in 0..<attempts {
    if kill(pid, 0) != 0 {
      return errno == ESRCH
    }
    usleep(intervalUsec)
  }
  return kill(pid, 0) != 0 && errno == ESRCH
}

/// Terminates a prior owned runtime process referenced by the PID file.
func killPrevious() {
  guard let pid = readPidFromFile() else { return }

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

  guard kill(pid, SIGTERM) == 0 else {
    warning("failed to signal prior process \(pid): \(String(cString: strerror(errno)))")
    return
  }

  if waitForProcessExit(pid) {
    removePid()
  } else {
    warning("prior process \(pid) is still running after SIGTERM; keeping existing pid file")
  }
}

/// Creates the runtime PID file with race-resistant filesystem flags.
func writePid() {
  guard ensurePidDirectoryExists() else { return }

  if let existingPID = readPidFromFile() {
    if kill(existingPID, 0) != 0 && errno == ESRCH {
      _ = unlink(pidPath)
    }
  }

  let fd = open(pidPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
  guard fd >= 0 else {
    if errno == EEXIST {
      warning("pid file already exists at \(pidPath)")
    } else {
      warning("failed to create pid file at \(pidPath): \(String(cString: strerror(errno)))")
    }
    return
  }
  defer { close(fd) }

  let payload = Data("\(getpid())\n".utf8)
  let wroteAll = payload.withUnsafeBytes { rawBuffer -> Bool in
    guard let base = rawBuffer.baseAddress else { return false }
    var remaining = rawBuffer.count
    var offset = 0
    while remaining > 0 {
      let written = write(fd, base.advanced(by: offset), remaining)
      if written < 0 {
        if errno == EINTR { continue }
        return false
      }
      if written == 0 {
        return false
      }
      remaining -= written
      offset += written
    }
    return true
  }

  if !wroteAll {
    warning("failed to write pid file at \(pidPath)")
    removePid()
  }
}

/// Removes the runtime PID file if present.
func removePid() {
  _ = unlink(pidPath)
}

/// Removes the runtime PID file using a precomputed C string for signal safety.
func removePidSignalSafe() {
  _ = unlink(pidPathCString)
}

/// Installs termination handlers that clean PID state on exit signals.
func installSignalHandlers() {
  let handler: @convention(c) (Int32) -> Void = { _ in
    removePidSignalSafe()
    _exit(0)
  }
  signal(SIGTERM, handler)
  signal(SIGINT, handler)
}

// MARK: - Notification delegate

/// Handles notification click and presentation callbacks.
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  let args: NotifyArgs

  /// Creates a delegate bound to parsed runtime arguments.
  init(args: NotifyArgs) {
    self.args = args
  }

  /// Handles notification click interactions and optional execute/activate actions.
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
        // Intentional synchronous wait: this short-lived CLI exits immediately after handling actions.
        task.waitUntilExit()
        if task.terminationStatus != 0 {
          warning("click execute command exited \(task.terminationStatus)")
        }
      } catch {
        warning("failed to run click execute command: \(error.localizedDescription)")
      }
    }

    if let bundleID = args.activate {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      task.arguments = ["-b", bundleID]
      do {
        try task.run()
        // Intentional synchronous wait: this short-lived CLI exits immediately after handling actions.
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

  /// Configures foreground presentation options for incoming notifications.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}

// MARK: - Remove mode

/// Removes delivered and pending notifications for a group and exits.
func handleRemove(group: String) -> Never {
  let center = UNUserNotificationCenter.current()
  center.removeDeliveredNotifications(withIdentifiers: [group])
  center.removePendingNotificationRequests(withIdentifiers: [group])
  usleep(200_000)
  exit(0)
}

// MARK: - Sender spoofing runtime helpers

/// Returns whether helper bundle IDs should be isolated per sender.
func useIsolatedHelperBundleID() -> Bool {
  ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID"] == "1"
}

/// Returns whether auto retry without isolation is permitted after spoof failure.
func allowNonIsolatedSpoofRetry() -> Bool {
  let env = ProcessInfo.processInfo.environment
  return env["CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY"] == "1"
    || env["NOTIFY_ALLOW_NONISOLATED_RETRY"] == "1"
}

/// Launches fallback notification flows when spoofed auto mode fails.
func tryAutoFallbackIfNeeded(args: NotifyArgs) {
  guard args.senderMode == .auto, args.spoofedRun, !args.fallbackRun else { return }
  guard let originPath = normalizeOption(args.originExecPath) else {
    warning("sender spoof fallback skipped: missing origin executable path")
    return
  }

  let processArgs = Array(CommandLine.arguments.dropFirst())

  if useIsolatedHelperBundleID() && allowNonIsolatedSpoofRetry() {
    let retryTask = Process()
    retryTask.executableURL = URL(fileURLWithPath: originPath)
    retryTask.arguments = buildRetrySpoofArguments(from: processArgs)
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

  let task = Process()
  task.executableURL = URL(fileURLWithPath: originPath)
  task.arguments = buildFallbackArguments(from: processArgs)
  do {
    try task.run()
    warning("sender spoof failed; launched fallback notification without spoof")
    removePid()
    exit(0)
  } catch {
    warning("sender spoof fallback launch failed: \(error.localizedDescription)")
  }
}

/// Relaunches the prepared helper app and waits for completion.
func relaunchViaSpoofHelper(executableURL: URL) throws -> Int32 {
  let forwardedArgs = buildRelaunchArguments(
    from: Array(CommandLine.arguments.dropFirst()),
    originExecutablePath: currentExecutablePath()
  )

  let helperAppURL = executableURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

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
  try task.run()
  task.waitUntilExit()
  return task.terminationStatus
}

// MARK: - Post notification

/// Requests authorization and posts the notification payload.
func postNotification(args: NotifyArgs, delegate: NotificationDelegate) {
  let center = UNUserNotificationCenter.current()
  center.delegate = delegate

  center.requestAuthorization(options: [.alert, .sound]) { granted, error in
    if !granted {
      if let error {
        warn("notification authorization denied: \(error.localizedDescription)")
      } else {
        warn("notification authorization denied")
      }
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

    let content = UNMutableNotificationContent()
    content.title = args.title
    if let subtitle = args.subtitle {
      content.subtitle = subtitle
    }
    content.body = args.message ?? ""
    if let sound = args.sound {
      content.sound = sound == "default" ? .default : UNNotificationSound(named: UNNotificationSoundName(sound))
    }

    let identifier = args.group ?? UUID().uuidString
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

    center.add(request) { error in
      if let error {
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
    guard let sourceExecutablePath = currentExecutablePath() else {
      throw SenderSpoofError.missingExecutablePath
    }

    let options = HelperPreparationOptions(
      isolateHelperBundleID: useIsolatedHelperBundleID(),
      baseBundleID: Bundle.main.bundleIdentifier
    )
    let helperExecutable = try prepareSpoofHelper(
      sender: sender,
      sourceExecutablePath: sourceExecutablePath,
      options: options
    )
    let status = try relaunchViaSpoofHelper(executableURL: helperExecutable)
    exit(status)
  } catch {
    let message = "sender spoof unavailable: \(error.localizedDescription)"
    if args.senderMode == .required {
      die(message)
    } else {
      warning(message)
    }
  }
}

killPrevious()
writePid()
installSignalHandlers()

let delegate = NotificationDelegate(args: args)
postNotification(args: args, delegate: delegate)

DispatchQueue.main.asyncAfter(deadline: .now() + args.timeout) {
  removePid()
  exit(0)
}

RunLoop.main.run()
