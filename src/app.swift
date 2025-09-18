import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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
    var remoteURL: URL?
    var readFromStdin = false
    var acceptFlags = true
    var wikipediaTokens: [String] = []

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

      if acceptFlags && (arg == "-w" || arg == "--wikipedia") {
        acceptFlags = false
        wikipediaTokens.removeAll(keepingCapacity: true)
        index += 1
        while index < args.count {
          wikipediaTokens.append(args[index])
          index += 1
        }
        break
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

      if remoteURL == nil, filePath == nil, let url = parseRemoteURL(arg) {
        remoteURL = url
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

    if !wikipediaTokens.isEmpty && (filePath != nil || remoteURL != nil || readFromStdin) {
      fputs("Cannot combine -w with other input sources\n", stderr)
      exit(1)
    }

    if readFromStdin && filePath != nil {
      fputs("Cannot combine '-' with a file path\n", stderr)
      exit(1)
    }

    if readFromStdin {
      openFromStandardInput(lineNumber: lineNumber)
      return
    }

    if !wikipediaTokens.isEmpty {
      let joined = wikipediaTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
      guard !joined.isEmpty else {
        fputs("Expected an article name after -w\n", stderr)
        exit(1)
      }
      openWikipediaArticle(named: joined)
      return
    }

    if let url = remoteURL {
      openRemoteResource(at: url, lineNumber: lineNumber)
      return
    }

    if let path = filePath {
      openFile(at: path, lineNumber: lineNumber)
      return
    }

    // No file provided; open blank buffer (line hint is ignored)
    EditorController.run()
  }

  private static func parseRemoteURL(_ argument: String) -> URL? {
    guard let url = URL(string: argument) else { return nil }
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      return nil
    }
    return url
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
    let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return lines.isEmpty ? [""] : lines
  }

  private static func openRemoteResource(at url: URL, lineNumber: Int?) {
    let (data, response, error) = URLSession.shared.syncRequest(with: url)

    if let error {
      fputs("Failed to fetch \(url.absoluteString): \(error.localizedDescription)\n", stderr)
      exit(1)
    }

    if let http = response as? HTTPURLResponse,
      !(200...299).contains(http.statusCode)
    {
      fputs("Server responded with status \(http.statusCode) for \(url.absoluteString)\n", stderr)
      exit(1)
    }

    guard let data else {
      fputs("No data received from \(url.absoluteString)\n", stderr)
      exit(1)
    }

    do {
      let content = try makeTextContent(from: data)
      let buffer = makeBuffer(from: content)
      let cursor = initialCursor(for: lineNumber, buffer: buffer)
      let savePath = derivedSavePath(for: url)
      EditorController.run(initialBuffer: buffer, filePath: savePath, initialCursor: cursor)
    } catch let error as DocumentLoadError {
      fputs("\(error.messageForFile(path: url.absoluteString))\n", stderr)
      exit(1)
    } catch {
      fputs("Failed to decode remote content from \(url.absoluteString): \(error)\n", stderr)
      exit(1)
    }
  }

  private static func openWikipediaArticle(named title: String) {
    do {
      let article = try fetchWikipediaArticle(title: title)
      let sanitized = sanitizeContent(article.extract)
      let buffer = makeBuffer(from: sanitized)
      let cursor = initialCursor(for: nil, buffer: buffer)
      let suggestedFilename = wikipediaSuggestedFilename(for: article.title)
      let cwd = FileManager.default.currentDirectoryPath
      let savePath = (cwd as NSString).appendingPathComponent(suggestedFilename)
      EditorController.run(initialBuffer: buffer, filePath: savePath, initialCursor: cursor)
    } catch let error as WikipediaError {
      fputs("\(error.localizedDescription)\n", stderr)
      exit(1)
    } catch {
      fputs("Failed to load Wikipedia article '\(title)': \(error)\n", stderr)
      exit(1)
    }
  }

  private static func derivedSavePath(for url: URL) -> String {
    var candidate = url.lastPathComponent
    if let decoded = candidate.removingPercentEncoding { candidate = decoded }
    if candidate.isEmpty || candidate == "/" {
      candidate = "index.html"
    }
    if !candidate.contains(".") {
      candidate += ".html"
    }
    let cwd = FileManager.default.currentDirectoryPath
    let sanitized = candidate.replacingOccurrences(of: "\0", with: "")
    return (cwd as NSString).appendingPathComponent(sanitized)
  }

  private static func makeTextContent(from data: Data) throws -> String {
    guard !dataLooksBinary(data) else { throw DocumentLoadError.binary }
    guard let content = String(data: data, encoding: .utf8) else { throw DocumentLoadError.notUTF8 }
    return sanitizeContent(content)
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
      tim <http(s) url>         Download URL into a new buffer (UTF-8 text only)
      tim -w <name>             Open the Wikipedia article matching <name>
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

private extension Tim {
  static func sanitizeContent(_ text: String) -> String {
    var result = String()
    result.reserveCapacity(text.count)
    var skipNextLineFeed = false

    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x0D:  // Carriage return
        result.append("\n")
        skipNextLineFeed = true
      case 0x0A:  // Line feed
        if skipNextLineFeed {
          skipNextLineFeed = false
        } else {
          result.append("\n")
        }
      case 0x09:  // Horizontal tab
        result.append("  ")
        skipNextLineFeed = false
      case 0x2028, 0x2029:  // Unicode line/paragraph separators
        result.append("\n")
        skipNextLineFeed = false
      default:
        skipNextLineFeed = false
        let category = scalar.properties.generalCategory
        switch category {
        case .control, .format:
          result.append(" ")
        default:
          result.append(String(scalar))
        }
      }
    }

    return result
  }
}
