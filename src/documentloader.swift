import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct DocumentLoadResult {
  let buffer: [String]
  let filePath: String?
  let initialCursor: (line: Int, column: Int)?
  let markDirty: Bool
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
  /// Prepares a document from a local filesystem path.
  /// - Parameters:
  ///   - path: The user-supplied path (tilde may be expanded).
  ///   - lineNumber: Optional 1-based line hint for the resulting cursor.
  /// - Returns: A `DocumentLoadResult` containing the buffer and metadata.
  /// - Throws: `DocumentLoaderError` describing user-facing failures.
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
        return DocumentLoadResult(buffer: buffer, filePath: expandedPath, initialCursor: cursor, markDirty: false)
      } catch let error as DocumentDataError {
        throw DocumentLoaderError.userFacing(error.messageForFile(path: expandedPath))
      } catch {
        throw DocumentLoaderError.userFacing("Failed to open file: \(expandedPath) (\(error))")
      }
    } else {
      let buffer = [""]
      let cursor = initialCursor(for: lineNumber, buffer: buffer)
      return DocumentLoadResult(buffer: buffer, filePath: expandedPath, initialCursor: cursor, markDirty: true)
    }
  }

  /// Reads all stdin data and converts it into a document buffer.
  /// - Parameter lineNumber: Optional 1-based line hint for the resulting cursor.
  /// - Returns: A prepared `DocumentLoadResult` without a backing file path.
  /// - Throws: `DocumentLoaderError` on decoding issues.
  static func fromStandardInput(lineNumber: Int?) throws -> DocumentLoadResult {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    do {
      let content = try makeTextContent(from: data)
      let buffer = makeBuffer(from: content)
      let cursor = initialCursor(for: lineNumber, buffer: buffer)
      return DocumentLoadResult(buffer: buffer, filePath: nil, initialCursor: cursor, markDirty: true)
    } catch let error as DocumentDataError {
      throw DocumentLoaderError.userFacing(error.messageForStandardInput())
    } catch {
      throw DocumentLoaderError.userFacing("Failed to read from standard input (\(error))")
    }
  }

  /// Downloads text content from `url` and stores a suggested filename.
  /// - Parameters:
  ///   - url: The remote resource to fetch (HTTP/S only).
  ///   - lineNumber: Optional 1-based line hint for the resulting cursor.
  /// - Returns: A `DocumentLoadResult` containing the fetched buffer and save path.
  /// - Throws: `DocumentLoaderError` when the request fails or the data is unsuitable.
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
      return DocumentLoadResult(buffer: buffer, filePath: savePath, initialCursor: cursor, markDirty: true)
    } catch let error as DocumentDataError {
      throw DocumentLoaderError.userFacing(error.messageForFile(path: url.absoluteString))
    } catch {
      throw DocumentLoaderError.userFacing(
        "Failed to decode remote content from \(url.absoluteString): \(error)")
    }
  }

  /// Fetches a Wikipedia extract and formats it as a plain-text buffer.
  /// - Parameter title: The human-readable article title (whitespace trimmed internally).
  /// - Returns: A `DocumentLoadResult` with a suggested `.txt` filename.
  /// - Throws: `DocumentLoaderError` wrapping `WikipediaError` messages.
  static func fromWikipedia(title: String) throws -> DocumentLoadResult {
    do {
      let article = try fetchWikipediaArticle(title: title)
      let sanitized = sanitizeContent(article.extract)
      let buffer = makeBuffer(from: sanitized)
      let cursor = initialCursor(for: nil, buffer: buffer)
      let cwd = FileManager.default.currentDirectoryPath
      let suggestedFilename = wikipediaSuggestedFilename(for: article.title)
      let savePath = (cwd as NSString).appendingPathComponent(suggestedFilename)
      return DocumentLoadResult(buffer: buffer, filePath: savePath, initialCursor: cursor, markDirty: true)
    } catch let error as WikipediaError {
      throw DocumentLoaderError.userFacing(error.localizedDescription)
    } catch {
      throw DocumentLoaderError.userFacing(
        "Failed to load Wikipedia article '\(title)': \(error)")
    }
  }

  /// Downloads and formats an RSS/Atom feed into a readable text buffer.
  /// - Parameter url: The feed URL to fetch.
  /// - Returns: `DocumentLoadResult` containing the rendered feed and suggested filename.
  /// - Throws: `DocumentLoaderError` when the request fails, parsing fails, or the feed is empty.
  static func fromRSS(url: URL, visited: Set<URL> = []) throws -> DocumentLoadResult {
    var visited = visited
    if visited.contains(url) {
      throw DocumentLoaderError.userFacing("Encountered circular RSS reference for \(url.absoluteString)")
    }
    visited.insert(url)
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
      let feed = try RSSParser.parse(data: data)
      if feed.items.isEmpty {
        if let html = String(data: data, encoding: .utf8),
          let discovered = discoverFeedURL(in: html, baseURL: url),
          !visited.contains(discovered)
        {
          return try fromRSS(url: discovered, visited: visited)
        }
        throw DocumentLoaderError.userFacing("Feed '\(url.absoluteString)' contained no entries.")
      }
      let rendered = renderFeed(feed: feed, sourceURL: url)
      let buffer = makeBuffer(from: rendered)
      let cursor = initialCursor(for: nil, buffer: buffer)
      let suggested = rssSuggestedFilename(title: feed.title, url: url)
      let cwd = FileManager.default.currentDirectoryPath
      let savePath = (cwd as NSString).appendingPathComponent(suggested)
      return DocumentLoadResult(buffer: buffer, filePath: savePath, initialCursor: cursor, markDirty: true)
    } catch let error as DocumentLoaderError {
      throw error
    } catch let error as RSSParserError {
      switch error {
      case .invalidXML:
        if let html = String(data: data, encoding: .utf8),
          let discovered = discoverFeedURL(in: html, baseURL: url),
          !visited.contains(discovered)
        {
          return try fromRSS(url: discovered, visited: visited)
        }
        throw DocumentLoaderError.userFacing(error.localizedDescription)
      default:
        throw DocumentLoaderError.userFacing(error.localizedDescription)
      }
    } catch {
      if let html = String(data: data, encoding: .utf8),
        let discovered = discoverFeedURL(in: html, baseURL: url),
        !visited.contains(discovered)
      {
        return try fromRSS(url: discovered, visited: visited)
      }
      throw DocumentLoaderError.userFacing("Failed to parse RSS feed: \(error)")
    }
  }

  /// Renders the public feed for a Bluesky handle into a text buffer.
  /// - Parameter handle: The handle, DID, or profile URL supplied by the user.
  /// - Returns: `DocumentLoadResult` containing the author's posts and a save suggestion.
  /// - Throws: `DocumentLoaderError` wrapping any Bluesky-specific failures.
  static func fromBluesky(handle: String) throws -> DocumentLoadResult {
    do {
      let feed = try BlueskyAPI.fetchFeed(rawHandle: handle)
      var lines: [String] = []

      if let display = feed.displayName, !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append(sanitizeContent(display))
      }
      lines.append("@\(feed.handle)")
      lines.append(contentsOf: Array(repeating: "", count: 4))

      var isFirstPost = true
      for post in feed.posts {
        if isFirstPost {
          isFirstPost = false
        } else {
          lines.append(contentsOf: Array(repeating: "", count: 4))
        }

        let authorDisplay = post.authorDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !authorDisplay.isEmpty {
          lines.append("\(sanitizeContent(authorDisplay)) (@\(post.authorHandle))")
        } else {
          lines.append("@\(post.authorHandle)")
        }

        if let created = post.createdAt {
          lines.append(formatDateWithOrdinal(created))
        }

        switch post.context {
        case .original:
          break
        case .repost(let byDisplayName, let handle):
          var descriptor = "Reposted by "
          if let byDisplay = byDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !byDisplay.isEmpty {
            descriptor += sanitizeContent(byDisplay)
            if let handle, !handle.isEmpty {
              descriptor += " (@\(handle))"
            }
          } else if let handle, !handle.isEmpty {
            descriptor += "@\(handle)"
          } else {
            descriptor += "@\(feed.handle)"
          }
          lines.append(descriptor)
        }

        let sanitizedBody = sanitizeContent(post.text)
        let paragraphs = sanitizedBody
          .split(whereSeparator: { $0 == "\n" })
          .map(String.init)
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty }

        if !paragraphs.isEmpty {
          lines.append("")
          for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 { lines.append("") }
            lines.append(paragraph)
          }
        }

      }

      let rendered = lines.joined(separator: "\n")
      let buffer = makeBuffer(from: rendered)
      let cursor = initialCursor(for: nil, buffer: buffer)
      let suggested = blueskySuggestedFilename(handle: feed.handle)
      let cwd = FileManager.default.currentDirectoryPath
      let savePath = (cwd as NSString).appendingPathComponent(suggested)
      return DocumentLoadResult(buffer: buffer, filePath: savePath, initialCursor: cursor, markDirty: true)
    } catch let error as BlueskyError {
      throw DocumentLoaderError.userFacing(error.localizedDescription)
    } catch let error as DocumentLoaderError {
      throw error
    } catch {
      throw DocumentLoaderError.userFacing("Failed to load Bluesky feed: \(error.localizedDescription)")
    }
  }

  // MARK: - Helpers

  /// Converts raw bytes into sanitized UTF-8 text.
  /// - Parameter data: The raw file or response payload.
  /// - Returns: A normalized string (always using `\n` newlines and sanitized control chars).
  /// - Throws: `DocumentDataError` if the data appears binary or not UTF-8.
  private static func makeTextContent(from data: Data) throws -> String {
    guard !dataLooksBinary(data) else { throw DocumentDataError.binary }
    guard let content = String(data: data, encoding: .utf8) else {
      throw DocumentDataError.notUTF8
    }
    return sanitizeContent(content)
  }

  /// Splits the provided text into logical lines, preserving empty trailing lines.
  /// - Parameter content: Sanitized editor text.
  /// - Returns: An array of lines (never empty; at least one empty string).
  private static func makeBuffer(from content: String) -> [String] {
    let normalized = content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return lines.isEmpty ? [""] : lines
  }

  /// Heuristically detects binary data by sampling the first kilobyte for control bytes.
  /// - Parameter data: The raw blob to inspect.
  /// - Returns: `true` when the sample suggests the content is binary.
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

  /// Builds a filesystem-friendly save path for downloaded content.
  /// - Parameter url: The source URL whose last path component is used.
  /// - Returns: A path under the current working directory.
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

  /// Normalizes control characters and newline variants into editor-friendly text.
  /// - Parameter text: The raw text prior to sanitization.
  /// - Returns: A string containing only `\n` newlines and visible spacing for control chars.
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

    return result.replacingOccurrences(of: "\u{200C}", with: "")
  }

  /// Translates a 1-based line hint into a clamped buffer coordinate.
  /// - Parameters:
  ///   - lineNumber: The optional user-specified line (1-based).
  ///   - buffer: The target buffer to clamp against.
  /// - Returns: A cursor tuple or `nil` when no hint was provided.
  private static func initialCursor(for lineNumber: Int?, buffer: [String]) -> (line: Int, column: Int)? {
    guard let lineNumber else { return nil }
    let zeroBased = max(0, lineNumber - 1)
    let clampedLine = min(zeroBased, max(0, buffer.count - 1))
    return (line: clampedLine, column: 0)
  }

  private static func rssSuggestedFilename(title: String?, url: URL) -> String {
    let base: String
    if let title, !title.isEmpty {
      base = title
    } else if let host = url.host, !host.isEmpty {
      base = host
    } else {
      base = "feed"
    }
    let lowered = base.lowercased()
    var slug = ""
    slug.reserveCapacity(lowered.count)
    for scalar in lowered.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        slug.append(Character(scalar))
      } else if scalar == " " || scalar == "-" || scalar == "_" {
        slug.append("_")
      }
    }
    while slug.contains("__") { slug = slug.replacingOccurrences(of: "__", with: "_") }
    slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    if slug.isEmpty { slug = "feed" }
    return slug + ".txt"
  }

  private static func blueskySuggestedFilename(handle: String) -> String {
    let lowered = handle.lowercased()
    var slug = ""
    slug.reserveCapacity(lowered.count)
    for scalar in lowered.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        slug.append(Character(scalar))
      } else if scalar == "." || scalar == "-" || scalar == "_" {
        slug.append("_")
      }
    }
    while slug.contains("__") { slug = slug.replacingOccurrences(of: "__", with: "_") }
    slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    if slug.isEmpty { slug = "bluesky" }
    return slug + ".txt"
  }

  private static func renderFeed(feed: RSSFeed, sourceURL: URL) -> String {
    var lines: [String] = []
    let rawTitle = feed.title?.isEmpty == false ? feed.title! : sourceURL.absoluteString
    let feedTitle = sanitizeContent(rawTitle)
    lines.append(feedTitle)
    let displayURL = cleanDisplayURL(from: sourceURL)
    if !displayURL.isEmpty { lines.append(displayURL) }
    lines.append(contentsOf: Array(repeating: "", count: 4))

    var isFirstItem = true

    for item in feed.items {
      if isFirstItem {
        isFirstItem = false
      } else {
        lines.append(contentsOf: Array(repeating: "", count: 4))
      }
      if let title = item.title, !title.isEmpty {
        lines.append(title)
        lines.append(String(repeating: "=", count: title.count))
      }
      if let date = item.publishedDate ?? item.updatedDate {
        lines.append(formatDateWithOrdinal(date))
      } else if let raw = item.publishedString ?? item.updatedString, !raw.isEmpty {
        lines.append(raw)
      }
      let bodyText = item.summary ?? item.content
      if let body = bodyText, !body.isEmpty {
        let plain = sanitizeContent(htmlToPlainText(body))
        let paragraphs = plain
          .components(separatedBy: CharacterSet.newlines)
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty }
        if !paragraphs.isEmpty {
          lines.append("")
          var previousWasBullet = false
          for (index, paragraph) in paragraphs.enumerated() {
            let isBullet = paragraph.hasPrefix("• ")
            if index > 0 && !(previousWasBullet && isBullet) {
              lines.append("")
            }
            lines.append(paragraph)
            previousWasBullet = isBullet
          }
        }
      }
    }

    return lines.joined(separator: "\n")
  }

  private static func htmlToPlainText(_ string: String) -> String {
    guard !string.isEmpty else { return string }
    var text = string

    // Render HTML lists as bullet lines before other transformations.
    text = rewriteLists(text)

    // Convert common break tags into newlines before stripping remaining tags.
    text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: #"(?i)</p>"#, with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: #"(?i)</div>"#, with: "\n", options: .regularExpression)

    // Replace anchor tags with "text (host)" pattern before stripping other tags.
    text = rewriteAnchors(text)

    // Remove residual HTML tags.
    text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)

    // Decode HTML entities.
    text = decodeHTMLEntities(text)

    // Normalize whitespace and trim.
    text = text.replacingOccurrences(of: #"[ \t\u{00A0}]{2,}"#, with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: "\u{00A0}", with: " ")

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func decodeHTMLEntities(_ string: String) -> String {
    let decoded: String
    if let cfString = CFXMLCreateStringByUnescapingEntities(nil, string as CFString, nil) {
      decoded = cfString as String
    } else {
      decoded = string
    }
    var cleaned = decoded
    cleaned = cleaned.replacingOccurrences(of: "\u{200C}", with: "")
    cleaned = cleaned.replacingOccurrences(of: "&zwnj;", with: "", options: [.caseInsensitive], range: nil)
    cleaned = cleaned.replacingOccurrences(of: "&#8204;", with: "", options: [.caseInsensitive], range: nil)
    return cleaned
  }

  private static func rewriteAnchors(_ html: String) -> String {
    var result = html
    let pattern = #"<a\s+[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.+?)</a>"#
    let regex: NSRegularExpression
    do {
      regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    } catch {
      return html
    }

    while true {
      guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count)) else {
        break
      }

      let hrefRange = match.range(at: 1)
      let textRange = match.range(at: 2)

      guard let href = substring(result, range: hrefRange) else { break }
      let rawText = substring(result, range: textRange) ?? ""
      let strippedText = sanitizeContent(stripHTML(rawText)).trimmingCharacters(in: .whitespacesAndNewlines)

      var cleanedURL = href.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
      if cleanedURL.hasSuffix("/") { cleanedURL.removeLast() }
      let replacement = strippedText.isEmpty ? cleanedURL : "\(strippedText) (\(cleanedURL))"

      let fullRange = match.range(at: 0)
      guard let swiftRange = Range(fullRange, in: result) else { break }
      result.replaceSubrange(swiftRange, with: replacement)
    }

    return result
  }

  private static func stripHTML(_ string: String) -> String {
    return string.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
  }

  private static func substring(_ string: String, range: NSRange) -> String? {
    guard let swiftRange = Range(range, in: string) else { return nil }
    return String(string[swiftRange])
  }

  private static func cleanDisplayURL(from url: URL) -> String {
    let host = url.host ?? ""
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if host.isEmpty { return path }
    if path.isEmpty { return host }
    return host + "/" + path
  }

  private static func rewriteLists(_ html: String) -> String {
    var result = html
    let listPattern = #"<(ul|ol)[^>]*>(.*?)</\1>"#
    let itemPattern = #"<li[^>]*>(.*?)</li>"#

    guard let listRegex = try? NSRegularExpression(pattern: listPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
      let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    else {
      return html
    }

    while true {
      guard let match = listRegex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count)) else {
        break
      }

      guard let listRange = Range(match.range(at: 0), in: result) else { break }
      let listSubstring = String(result[listRange])
      let items = itemRegex.matches(in: listSubstring, options: [], range: NSRange(location: 0, length: listSubstring.utf16.count))

      var bullets: [String] = []
      for itemMatch in items {
        guard let itemRange = Range(itemMatch.range(at: 1), in: listSubstring) else { continue }
        let itemHTML = String(listSubstring[itemRange])
        let text = decodeHTMLEntities(stripHTML(itemHTML)).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { continue }
        bullets.append("• \(text)")
      }

      let replacement = bullets.isEmpty ? "" : "\n" + bullets.joined(separator: "\n") + "\n"
      result.replaceSubrange(listRange, with: replacement)
    }

    return result
  }

  private static func discoverFeedURL(in html: String, baseURL: URL) -> URL? {
    let pattern = #"<link[^>]+>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }

    let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
    for match in matches {
      guard let range = Range(match.range, in: html) else { continue }
      let tag = String(html[range])
      let attributes = parseLinkAttributes(tag)
      guard let rel = attributes["rel"]?.lowercased(), rel.contains("alternate") else { continue }
      let typeValue = attributes["type"]?.lowercased() ?? ""
      let hrefValue = attributes["href"] ?? ""
      var isFeed = false
      if !(typeValue.isEmpty) {
        if typeValue.contains("rss") || typeValue.contains("atom") || typeValue.contains("xml") {
          isFeed = true
        }
      }
      if !isFeed {
        let hrefLower = hrefValue.lowercased()
        if hrefLower.contains("rss") || hrefLower.contains("atom") || hrefLower.contains("feed") {
          isFeed = true
        }
      }
      guard isFeed else { continue }
      let href = hrefValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !href.isEmpty else { continue }
      if let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL {
        return resolved
      }
    }
    return nil
  }

  private static func parseLinkAttributes(_ tag: String) -> [String: String] {
    var attributes: [String: String] = [:]
    let pattern = #"(\w+)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return attributes
    }
    let range = NSRange(location: 0, length: tag.utf16.count)
    for match in regex.matches(in: tag, options: [], range: range) {
      guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
      let name = tag[nameRange].lowercased()
      let valueRange = (2...4).compactMap { Range(match.range(at: $0), in: tag) }.first
      guard let vr = valueRange else { continue }
      let rawValue = String(tag[vr]).trimmingCharacters(in: .whitespacesAndNewlines)
      attributes[name] = rawValue
    }
    return attributes
  }

  private static func formatDateWithOrdinal(_ date: Date) -> String {
    let calendar = Calendar(identifier: .gregorian)
    let day = calendar.component(.day, from: date)
    let suffix: String
    switch day % 100 {
    case 11, 12, 13:
      suffix = "th"
    default:
      switch day % 10 {
      case 1: suffix = "st"
      case 2: suffix = "nd"
      case 3: suffix = "rd"
      default: suffix = "th"
      }
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMMM d',' yyyy 'at' h:mm a"
    let base = formatter.string(from: date)
    return base.replacingOccurrences(of: "\(day)", with: "\(day)\(suffix)")
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
