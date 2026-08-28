import AppKit

/// Opens Terminal and puts a command on the clipboard so the user can paste-and-run
/// it. We copy rather than auto-execute to avoid an Automation (TCC) permission
/// prompt — the user just presses ⌘V ↩.
enum TerminalHelper {
    static func openTerminalWithCommandOnClipboard(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Terminal"]
        try? proc.run()
    }
}
