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
    do {
      let command = try CLI.parse(arguments: args)
      handle(command: command)
    } catch let error as CLI.ParserError {
      fputs("\(errorDescription(for: error))\n", stderr)
      fputs("\n\(CLI.usageText())\n", stderr)
      exit(1)
    } catch {
      fputs("Unexpected error: \(error)\n", stderr)
      exit(1)
    }
  }

  private static func handle(command: CLI.Command) {
    switch command {
    case .showHelp:
      print(CLI.usageText())
    case .showVersion:
      print("tim version \(version)")
    case .open(let input):
      open(input: input)
    }
  }

  private static func open(input: CLI.Input) {
    switch input {
    case .empty:
      EditorController.run()
    case .file(let path, let line):
      performLoad { try DocumentLoader.fromFile(path: path, lineNumber: line) }
    case .standardInput(let line):
      performLoad { try DocumentLoader.fromStandardInput(lineNumber: line) }
    case .remote(let url, let line):
      performLoad { try DocumentLoader.fromRemote(url: url, lineNumber: line) }
    case .wikipedia(let title):
      performLoad { try DocumentLoader.fromWikipedia(title: title) }
    case .rss(let url):
      performLoad { try DocumentLoader.fromRSS(url: url) }
    }
  }
}

private extension Tim {
  static func performLoad(_ block: () throws -> DocumentLoadResult) {
    do {
      let result = try block()
      EditorController.run(
        initialBuffer: result.buffer,
        filePath: result.filePath,
        initialCursor: result.initialCursor)
    } catch let error as DocumentLoaderError {
      fputs("\(error.message)\n", stderr)
      exit(1)
    } catch {
      fputs("Unexpected error: \(error)\n", stderr)
      exit(1)
    }
  }

  static func errorDescription(for error: CLI.ParserError) -> String {
    switch error {
    case .invalidCombination(let message):
      return message
    case .missingArgument(let message):
      return message
    }
  }
}
