import Cocoa
import NotifyCore
@preconcurrency import UserNotifications

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

func parseArgs() -> NotifyArgs {
  do {
    return try ArgumentParser.parse(Array(CommandLine.arguments.dropFirst()))
  } catch let parseError as ArgParseError {
    switch parseError {
    case .helpRequested:
      usage()
      exit(1)
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

let pidPath = "/tmp/claude-notify.pid"

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
  let data = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
  let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
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
  usleep(100_000)
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
  let args: NotifyArgs

  init(args: NotifyArgs) {
    self.args = args
  }

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
  usleep(200_000)
  exit(0)
}

// MARK: - Sender spoofing runtime helpers

func useIsolatedHelperBundleID() -> Bool {
  ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID"] == "1"
}

func allowNonIsolatedSpoofRetry() -> Bool {
  ProcessInfo.processInfo.environment["CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY"] == "1"
}

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

DispatchQueue.main.asyncAfter(deadline: .now() + args.timeout) {
  removePid()
  exit(0)
}

RunLoop.main.run()
