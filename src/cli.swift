import Foundation

struct CLI {
  enum Command {
    case showHelp
    case showVersion
    case open(Input)
  }

  enum Input {
    case empty
    case file(path: String, line: Int?)
    case standardInput(line: Int?)
    case remote(URL, line: Int?)
    case wikipedia(String)
    case rss(URL)
    case bluesky(String)
  }

  enum ParserError: Error {
    case invalidCombination(String)
    case missingArgument(String)
  }
  
  /// Parses the provided command-line arguments into a concrete `Command`.
  /// - Parameter arguments: The raw argument list excluding the executable name.
  /// - Returns: A `Command` describing the action the user requested.
  /// - Throws: `ParserError` when conflicting or incomplete arguments are supplied.
  static func parse(arguments: [String]) throws -> Command {
    if arguments.isEmpty { return .open(.empty) }

    var lineNumber: Int?
    var filePath: String?
    var remoteURL: URL?
    var readFromStdin = false
    var rssURL: URL?
    var blueskyHandle: String?
    var acceptFlags = true
    var wikipediaTokens: [String] = []

    var index = 0
    while index < arguments.count {
      let arg = arguments[index]

      if acceptFlags && (arg == "-h" || arg == "--help") { return .showHelp }
      if acceptFlags && arg == "--version" { return .showVersion }

      if acceptFlags && (arg == "-w" || arg == "--wikipedia") {
        acceptFlags = false
        wikipediaTokens.removeAll(keepingCapacity: true)
        index += 1
        while index < arguments.count {
          wikipediaTokens.append(arguments[index])
          index += 1
        }
        break
      }

      if acceptFlags && (arg == "-r" || arg == "--rss") {
        index += 1
        guard index < arguments.count else {
          throw ParserError.missingArgument("Expected a URL after \(arg)")
        }
        let raw = arguments[index]
        rssURL = parseURLFromString(raw)
        guard rssURL != nil else {
          throw ParserError.missingArgument("Invalid RSS URL provided")
        }
        index += 1
        acceptFlags = false
        continue
      }

      if acceptFlags && (arg == "-b" || arg == "--bluesky") {
        index += 1
        guard index < arguments.count else {
          throw ParserError.missingArgument("Expected a handle after \(arg)")
        }
        blueskyHandle = arguments[index]
        index += 1
        acceptFlags = false
        continue
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

      if remoteURL == nil, filePath == nil,
        let url = parseURLFromString(arg)
      {
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

    if !wikipediaTokens.isEmpty {
      if filePath != nil || remoteURL != nil || readFromStdin || rssURL != nil {
        throw ParserError.invalidCombination("Cannot combine -w with other input sources")
      }
      let joined = wikipediaTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
      guard !joined.isEmpty else {
        throw ParserError.missingArgument("Expected an article name after -w")
      }
      return .open(.wikipedia(joined))
    }

    if readFromStdin {
      if filePath != nil || rssURL != nil || blueskyHandle != nil {
        throw ParserError.invalidCombination("Cannot combine '-' with other input sources")
      }
      return .open(.standardInput(line: lineNumber))
    }

    if let rss = rssURL {
      if filePath != nil || remoteURL != nil {
        throw ParserError.invalidCombination("Cannot combine -r with other input sources")
      }
      return .open(.rss(rss))
    }

    if let handle = blueskyHandle {
      if filePath != nil || remoteURL != nil || rssURL != nil {
        throw ParserError.invalidCombination("Cannot combine -b with other input sources")
      }
      return .open(.bluesky(handle))
    }

    if let url = remoteURL {
      return .open(.remote(url, line: lineNumber))
    }

    if let path = filePath {
      return .open(.file(path: path, line: lineNumber))
    }

    return .open(.empty)
  }

  /// Returns the human-readable usage text shown for `--help` or parse errors.
  static func usageText() -> String {
    """
    Usage:
      tim                       Open an empty buffer
      tim <file>                Open <file>
      tim <http(s) url>         Download URL into a new buffer (UTF-8 text only)
      tim -w <name>             Open the Wikipedia article matching <name>
      tim -r <url>              Fetch and present the RSS/Atom feed at <url>
      tim -b <handle>           Render the public Bluesky feed for <handle>
      tim <file>:+<line>        Open <file> and jump to <line> (1-based)
      tim +<line> <file>        Jump to <line> after loading <file>
      tim -- <file>             Treat following argument as a literal path
      tim -                     Read buffer contents from standard input
      tim --help                Show this help output
      tim --version             Show the current version
    """.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Converts a `+<line>` argument into a 1-based line number.
  /// - Parameter argument: The string to inspect (e.g. `+42`).
  /// - Returns: The parsed integer if the pattern matches; otherwise `nil`.
  private static func parsePrefixedLineNumber(_ argument: String) -> Int? {
    guard argument.hasPrefix("+"), argument.count > 1 else { return nil }
    let digits = argument.dropFirst()
    guard digits.allSatisfy({ $0.isNumber }), let value = Int(digits) else { return nil }
    return value
  }

  /// Splits a file argument that may include an inline line reference (`path:+<line>`).
  /// - Parameter argument: The raw argument value.
  /// - Returns: A tuple containing the file path and optional line number when the pattern matches.
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

  private static func parseURLFromString(_ argument: String) -> URL? {
    guard let url = URL(string: argument), let scheme = url.scheme?.lowercased() else {
      return nil
    }
    return (scheme == "http" || scheme == "https") ? url : nil
  }
}
