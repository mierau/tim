import Foundation

enum ClipboardError: Error {
  case unsupportedPlatform
  case toolFailure(command: String, status: Int32, stderr: String)
  case unreadablePasteboard
  case toolsUnavailable
}

enum Clipboard {
  private static let pbcopyPath = "/usr/bin/pbcopy"
  private static let pbpastePath = "/usr/bin/pbpaste"

  private static var toolsAvailable: Bool {
    #if os(macOS)
      let fileManager = FileManager.default
      return fileManager.isExecutableFile(atPath: pbcopyPath)
        && fileManager.isExecutableFile(atPath: pbpastePath)
    #else
      return false
    #endif
  }

  static func copy(_ text: String) throws {
    #if os(macOS)
      guard toolsAvailable else { throw ClipboardError.toolsUnavailable }
      let data = Data(text.utf8)
      _ = try runClipboardTool(path: pbcopyPath, input: data)
    #else
      throw ClipboardError.unsupportedPlatform
    #endif
  }

  static func paste() throws -> String? {
    #if os(macOS)
      guard toolsAvailable else { throw ClipboardError.toolsUnavailable }
      let data = try runClipboardTool(path: pbpastePath)
      guard !data.isEmpty else { return "" }
      guard let string = String(data: data, encoding: .utf8) else {
        throw ClipboardError.unreadablePasteboard
      }
      return string
    #else
      throw ClipboardError.unsupportedPlatform
    #endif
  }

  @discardableResult
  private static func runClipboardTool(path: String, input: Data? = nil) throws -> Data {
    #if os(macOS)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = []

      let stdoutPipe = Pipe()
      process.standardOutput = stdoutPipe
      let stderrPipe = Pipe()
      process.standardError = stderrPipe

      if let input {
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        pipe.fileHandleForWriting.write(input)
        pipe.fileHandleForWriting.closeFile()
      } else {
        try process.run()
      }

      process.waitUntilExit()

      let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

      if process.terminationReason != .exit || process.terminationStatus != 0 {
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
        throw ClipboardError.toolFailure(
          command: path, status: process.terminationStatus, stderr: stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
      }

      return stdoutData
    #else
      throw ClipboardError.unsupportedPlatform
    #endif
  }
}
