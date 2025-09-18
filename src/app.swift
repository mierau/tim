import Foundation

#if canImport(Darwin)
  import Darwin
#endif

@main
struct Tim {
  static let version = "0.1.0"

  static func main() {
    #if canImport(Darwin)
      setlocale(LC_CTYPE, "")
    #endif
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty {
      EditorController.run()
      return
    }

    var lineNumber: Int?
    var filePath: String?
    var readFromStdin = false
    var acceptFlags = true

    var index = 0
    while index < args.count {
      let arg = args[index]

      if acceptFlags && (arg == "-h" || arg == "--help") {
        printUsage()
        return
      }

      if acceptFlags && arg == "--version" {
        print("tim version \(version)")
        return
      }

      if acceptFlags && arg == "--" {
        acceptFlags = false
        index += 1
        continue
      }

      if arg == "-" {
        readFromStdin = true
        index += 1
        continue
      }

      if let prefixed = parsePrefixedLineNumber(arg) {
        lineNumber = prefixed
        index += 1
        continue
      }

      if filePath == nil, let parsed = parseFileArgumentWithLine(arg) {
        filePath = parsed.path
        if let line = parsed.line { lineNumber = line }
        index += 1
        continue
      }

      if filePath == nil {
        filePath = arg
        index += 1
        continue
      }

      index += 1
    }

    if readFromStdin && filePath != nil {
      fputs("Cannot combine '-' with a file path\n", stderr)
      exit(1)
    }

    if readFromStdin {
      openFromStandardInput(lineNumber: lineNumber)
      return
    }

    if let path = filePath {
      openFile(at: path, lineNumber: lineNumber)
      return
    }

    // No file provided; open blank buffer (line hint is ignored)
    EditorController.run()
  }

  private static func parsePrefixedLineNumber(_ argument: String) -> Int? {
    guard argument.hasPrefix("+"), argument.count > 1 else { return nil }
    let digits = argument.dropFirst()
    guard digits.allSatisfy({ $0.isNumber }), let value = Int(digits) else { return nil }
    return value
  }

  private static func parseFileArgumentWithLine(_ argument: String) -> (path: String, line: Int?)? {
    guard let range = argument.range(of: ":+", options: [.backwards]) else {
      return (path: argument, line: nil)
    }
    let linePart = argument[range.upperBound...]
    guard !linePart.isEmpty, linePart.allSatisfy({ $0.isNumber }), let line = Int(linePart) else {
      return (path: argument, line: nil)
    }
    let pathPart = argument[..<range.lowerBound]
    guard !pathPart.isEmpty else { return (path: argument, line: line) }
    return (path: String(pathPart), line: line)
  }

  private static func openFile(at rawPath: String, lineNumber: Int?) {
    let expandedPath = (rawPath as NSString).expandingTildeInPath
    let fileURL = URL(fileURLWithPath: expandedPath)
    let fileManager = FileManager.default

    if fileManager.fileExists(atPath: expandedPath) {
      do {
        let data = try Data(contentsOf: fileURL)
        let content = try makeTextContent(from: data)
        let buffer = makeBuffer(from: content)
        let cursor = initialCursor(for: lineNumber, buffer: buffer)
        EditorController.run(initialBuffer: buffer, filePath: expandedPath, initialCursor: cursor)
      } catch let error as DocumentLoadError {
        fputs("\(error.messageForFile(path: expandedPath))\n", stderr)
        exit(1)
      } catch {
        fputs("Failed to open file: \(expandedPath) (\(error))\n", stderr)
        exit(1)
      }
    } else {
      let buffer = [""]
      let cursor = initialCursor(for: lineNumber, buffer: buffer)
      EditorController.run(initialBuffer: buffer, filePath: expandedPath, initialCursor: cursor)
    }
  }

  private static func openFromStandardInput(lineNumber: Int?) {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    do {
      let content = try makeTextContent(from: data)
      let buffer = makeBuffer(from: content)
      let cursor = initialCursor(for: lineNumber, buffer: buffer)
      EditorController.run(initialBuffer: buffer, filePath: nil, initialCursor: cursor)
    } catch let error as DocumentLoadError {
      fputs("\(error.messageForStandardInput())\n", stderr)
      exit(1)
    } catch {
      fputs("Failed to read from standard input (\(error))\n", stderr)
      exit(1)
    }
  }

  private static func makeBuffer(from content: String) -> [String] {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return lines.isEmpty ? [""] : lines
  }

  private static func makeTextContent(from data: Data) throws -> String {
    guard !dataLooksBinary(data) else { throw DocumentLoadError.binary }
    guard let content = String(data: data, encoding: .utf8) else { throw DocumentLoadError.notUTF8 }
    return content
  }

  private static func dataLooksBinary(_ data: Data) -> Bool {
    if data.isEmpty { return false }
    var checked = 0
    var controlCount = 0
    for byte in data.prefix(1024) {
      if byte == 0 { return true }
      if byte < 0x20 && byte != 0x9 && byte != 0xA && byte != 0xD {
        controlCount += 1
      }
      checked += 1
    }
    guard checked > 0 else { return false }
    return Double(controlCount) / Double(checked) > 0.3
  }

  private enum DocumentLoadError: Error {
    case binary
    case notUTF8

    func messageForFile(path: String) -> String {
      switch self {
      case .binary:
        return "\(path) looks like a binary file. tim can only display ASCII or UTF-8 text."
      case .notUTF8:
        return "\(path) is not encoded as ASCII or UTF-8."
      }
    }

    func messageForStandardInput() -> String {
      switch self {
      case .binary:
        return "Standard input looked like binary data. tim can only display ASCII or UTF-8 text."
      case .notUTF8:
        return "Standard input was not valid ASCII or UTF-8 text."
      }
    }
  }

  private static func initialCursor(for lineNumber: Int?, buffer: [String]) -> (line: Int, column: Int)? {
    guard let lineNumber else { return nil }
    let zeroBased = max(0, lineNumber - 1)
    let clampedLine = min(zeroBased, max(0, buffer.count - 1))
    return (line: clampedLine, column: 0)
  }

  private static func printUsage() {
    let usage = """
    Usage:
      tim                       Open an empty buffer
      tim <file>                Open <file>
      tim <file>:+<line>        Open <file> and jump to <line> (1-based)
      tim +<line> <file>        Jump to <line> after loading <file>
      tim -- <file>             Treat following argument as a literal path
      tim -                     Read buffer contents from standard input
      tim --help                Show this help output
      tim --version             Show the current version
    """
    print(usage.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
