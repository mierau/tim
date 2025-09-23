import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct DocumentLoadResult {
  let buffer: [String]
  let filePath: String?
  let initialCursor: (line: Int, column: Int)?
}

enum DocumentLoaderError: Error {
  case userFacing(String)

  var message: String {
    switch self {
    case .userFacing(let value):
      return value
    }
  }
}

enum DocumentLoader {
  static func fromFile(path rawPath: String, lineNumber: Int?) throws -> DocumentLoadResult {
    let expandedPath = (rawPath as NSString).expandingTildeInPath
    let fileURL = URL(fileURLWithPath: expandedPath)
    let fileManager = FileManager.default

    if fileManager.fileExists(atPath: expandedPath) {
      do {
        let data = try Data(contentsOf: fileURL)
        let content = try makeTextContent(from: data)
        let buffer = makeBuffer(from: content)
        let cursor = initialCursor(for: lineNumber, buffer: buffer)
        return DocumentLoadResult(buffer: buffer, filePath: expandedPath, initialCursor: cursor)
      } catch let error as DocumentDataError {
        throw DocumentLoaderError.userFacing(error.messageForFile(path: expandedPath))
      } catch {
        throw DocumentLoaderError.userFacing("Failed to open file: \(expandedPath) (\(error))")
      }
    } else {
      let buffer = [""]
      let cursor = initialCursor(for: lineNumber, buffer: buffer)
      return DocumentLoadResult(buffer: buffer, filePath: expandedPath, initialCursor: cursor)
    }
  }

  static func fromStandardInput(lineNumber: Int?) throws -> DocumentLoadResult {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    do {
      let content = try makeTextContent(from: data)
      let buffer = makeBuffer(from: content)
      let cursor = initialCursor(for: lineNumber, buffer: buffer)
      return DocumentLoadResult(buffer: buffer, filePath: nil, initialCursor: cursor)
    } catch let error as DocumentDataError {
      throw DocumentLoaderError.userFacing(error.messageForStandardInput())
    } catch {
      throw DocumentLoaderError.userFacing("Failed to read from standard input (\(error))")
    }
  }

  static func fromRemote(url: URL, lineNumber: Int?) throws -> DocumentLoadResult {
    let (data, response, error) = URLSession.shared.syncRequest(with: url)

    if let error {
      throw DocumentLoaderError.userFacing("Failed to fetch \(url.absoluteString): \(error.localizedDescription)")
    }

    if let http = response as? HTTPURLResponse,
      !(200...299).contains(http.statusCode)
    {
      throw DocumentLoaderError.userFacing(
        "Server responded with status \(http.statusCode) for \(url.absoluteString)")
    }

    guard let data else {
      throw DocumentLoaderError.userFacing("No data received from \(url.absoluteString)")
    }

    do {
      let content = try makeTextContent(from: data)
      let buffer = makeBuffer(from: content)
      let cursor = initialCursor(for: lineNumber, buffer: buffer)
      let savePath = derivedSavePath(for: url)
      return DocumentLoadResult(buffer: buffer, filePath: savePath, initialCursor: cursor)
    } catch let error as DocumentDataError {
      throw DocumentLoaderError.userFacing(error.messageForFile(path: url.absoluteString))
    } catch {
      throw DocumentLoaderError.userFacing(
        "Failed to decode remote content from \(url.absoluteString): \(error)")
    }
  }

  static func fromWikipedia(title: String) throws -> DocumentLoadResult {
    do {
      let article = try fetchWikipediaArticle(title: title)
      let sanitized = sanitizeContent(article.extract)
      let buffer = makeBuffer(from: sanitized)
      let cursor = initialCursor(for: nil, buffer: buffer)
      let cwd = FileManager.default.currentDirectoryPath
      let suggestedFilename = wikipediaSuggestedFilename(for: article.title)
      let savePath = (cwd as NSString).appendingPathComponent(suggestedFilename)
      return DocumentLoadResult(buffer: buffer, filePath: savePath, initialCursor: cursor)
    } catch let error as WikipediaError {
      throw DocumentLoaderError.userFacing(error.localizedDescription)
    } catch {
      throw DocumentLoaderError.userFacing(
        "Failed to load Wikipedia article '\(title)': \(error)")
    }
  }

  // MARK: - Helpers

  private static func makeTextContent(from data: Data) throws -> String {
    guard !dataLooksBinary(data) else { throw DocumentDataError.binary }
    guard let content = String(data: data, encoding: .utf8) else {
      throw DocumentDataError.notUTF8
    }
    return sanitizeContent(content)
  }

  private static func makeBuffer(from content: String) -> [String] {
    let normalized = content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return lines.isEmpty ? [""] : lines
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

  private static func sanitizeContent(_ text: String) -> String {
    var result = String()
    result.reserveCapacity(text.count)
    var skipNextLineFeed = false

    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x0D:
        result.append("\n")
        skipNextLineFeed = true
      case 0x0A:
        if skipNextLineFeed {
          skipNextLineFeed = false
        } else {
          result.append("\n")
        }
      case 0x09:
        result.append("  ")
        skipNextLineFeed = false
      case 0x2028, 0x2029:
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

  private static func initialCursor(for lineNumber: Int?, buffer: [String]) -> (line: Int, column: Int)? {
    guard let lineNumber else { return nil }
    let zeroBased = max(0, lineNumber - 1)
    let clampedLine = min(zeroBased, max(0, buffer.count - 1))
    return (line: clampedLine, column: 0)
  }
}

private enum DocumentDataError: Error {
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
