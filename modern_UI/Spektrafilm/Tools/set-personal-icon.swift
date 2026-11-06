#!/usr/bin/env swift
// Apply a local Finder custom icon after installation. The distributable app
// stays clean: this tool is intentionally not called by build-personal.sh.
import AppKit
import CoreFoundation
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("set-personal-icon: \(message)\n".utf8))
    exit(1)
}

func verifySignature(_ app: URL, stage: String) {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["--verify", "--deep", app.path]
    process.standardOutput = output
    process.standardError = output
    do { try process.run() } catch { fail("Cannot run codesign \(stage): \(error)") }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fail("Signature verification failed \(stage):\n" + (String(data: data, encoding: .utf8) ?? "Unknown codesign error"))
    }
}

func hasCustomFinderIcon(_ app: URL) -> Bool {
    // Finder stores its custom-icon flag in the big-endian FinderInfo flags,
    // and the actual icon in an Icon<CR> file. Refuse either, including stale
    // custom-icon data, rather than overwrite a user's unknown replacement.
    let iconFile = app.appendingPathComponent("Icon\r")
    if FileManager.default.fileExists(atPath: iconFile.path)
        || (try? FileManager.default.destinationOfSymbolicLink(atPath: iconFile.path)) != nil {
        return true
    }
    let size = getxattr(app.path, "com.apple.FinderInfo", nil, 0, 0, 0)
    if size < 0 {
        guard errno == ENOATTR else { fail("Cannot inspect the app's Finder metadata: \(String(cString: strerror(errno)))") }
        return false
    }
    guard size > 0 else { return false }
    var bytes = [UInt8](repeating: 0, count: size)
    let count = bytes.withUnsafeMutableBytes {
        getxattr(app.path, "com.apple.FinderInfo", $0.baseAddress, $0.count, 0, 0)
    }
    guard count == size else { fail("Finder metadata changed or could not be read; nothing was modified") }
    return bytes.count >= 10 && (bytes[8] & 0x04) != 0
}

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--help"] || args == ["-h"] {
    print("""
    Usage: swift Tools/set-personal-icon.swift /absolute/path/to/景到.app

    Applies the bundle's Personal.icns as a local Finder custom icon.
    Only com.mrfay.spektralab.personal with PersonalBuild=true is accepted.
    Existing custom icons are refused; no files are overwritten or removed.
    No app is launched, registered, closed, or added to the Dock; no cache is cleared.
    Ordinary deep signature verification must pass before and after the change.
    Finder custom metadata makes codesign --strict reject the customized copy;
    keep the clean build for distribution and reapply only after installation.
    """)
    exit(0)
}
guard args.count == 1, args[0].hasPrefix("/") else {
    fail("Supply exactly one absolute personal .app path; use --help for details")
}

let app = URL(fileURLWithPath: args[0], isDirectory: true).resolvingSymlinksInPath()
var isDirectory: ObjCBool = false
guard app.pathExtension == "app",
      FileManager.default.fileExists(atPath: app.path, isDirectory: &isDirectory),
      isDirectory.boolValue else { fail("The supplied path is not an existing .app directory") }

let info = app.appendingPathComponent("Contents/Info.plist")
guard let data = try? Data(contentsOf: info),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      plist["CFBundleIdentifier"] as? String == "com.mrfay.spektralab.personal",
      let personal = plist["PersonalBuild"] as? NSNumber,
      CFGetTypeID(personal) == CFBooleanGetTypeID(), personal.boolValue else {
    fail("Refusing a bundle without the personal bundle ID and boolean PersonalBuild=true")
}

let source = app.appendingPathComponent("Contents/Resources/Personal.icns").resolvingSymlinksInPath()
guard source.path.hasPrefix(app.path + "/"),
      FileManager.default.fileExists(atPath: source.path),
      let icon = NSImage(contentsOf: source), !icon.representations.isEmpty else {
    fail("The bundle must contain a readable Personal.icns; external icon sources are not accepted")
}
guard FileManager.default.isWritableFile(atPath: app.path) else { fail("The personal app is not writable") }
guard !hasCustomFinderIcon(app) else {
    fail("This app already has custom Finder icon data; refusing to replace it. Use a clean installed personal build")
}

verifySignature(app, stage: "before applying the custom icon")
guard NSWorkspace.shared.setIcon(icon, forFile: app.path, options: []) else {
    fail("Finder did not accept the custom icon; inspect the target before retrying")
}
verifySignature(app, stage: "after applying the custom icon")
guard hasCustomFinderIcon(app) else { fail("Finder reported success but no custom icon metadata was created") }
print("""
Applied the bundled Personal.icns to: \(app.path)
Ordinary deep code-signature verification passed before and after the change.
Finder's custom icon metadata intentionally makes codesign --strict reject this
local copy; the app executable and signed resources were not replaced.
Keep the clean build for distribution. A future app replacement may need this
local customization reapplied. Dock appearance may update on the next launch.
""")
