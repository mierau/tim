import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Represents a parsed RSS or Atom feed and the set of items it contains.
struct RSSFeed {
  var title: String?
  var feedDescription: String?
  var link: String?
  var items: [RSSItem]
}

/// Captures the metadata and body content for a single feed entry.
struct RSSItem {
  var title: String?
  var link: String?
  var summary: String?
  var content: String?
  var publishedDate: Date?
  var updatedDate: Date?
  var publishedString: String?
  var updatedString: String?
}

/// Errors surfaced while attempting to parse RSS or Atom XML.
enum RSSParserError: Error, LocalizedError {
  case emptyData
  case invalidXML(String)

  var errorDescription: String? {
    switch self {
    case .emptyData:
      return "The feed response was empty."
    case .invalidXML(let reason):
      return "Failed to parse RSS/Atom feed: \(reason)"
    }
  }
}

/// Namespace that exposes helpers for parsing RSS and Atom payloads.
enum RSSParser {
  /// Parses a raw XML data blob into an `RSSFeed` structure.
  /// - Parameter data: The RSS or Atom XML payload to parse.
  /// - Returns: A fully populated `RSSFeed` value with all discovered entries.
  /// - Throws: `RSSParserError` when the payload is empty or malformed.
  static func parse(data: Data) throws -> RSSFeed {
    guard !data.isEmpty else { throw RSSParserError.emptyData }
    let delegate = FeedXMLParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    parser.shouldReportNamespacePrefixes = false
    if !parser.parse() {
      if let error = parser.parserError {
        throw RSSParserError.invalidXML(error.localizedDescription)
      } else {
        throw RSSParserError.invalidXML("Unknown parsing error")
      }
    }
    return delegate.result()
  }
}

/// XMLParser delegate that incrementally builds the feed model.
private final class FeedXMLParser: NSObject, XMLParserDelegate {
  private var feed = RSSFeed(title: nil, feedDescription: nil, link: nil, items: [])
  private var currentItem: RSSItem?
  private var currentElement: String = ""
  private var currentString: String = ""
  private var elementStack: [String] = []

  private let dateParsers = RSSDateParsers()

  /// Produces the accumulated `RSSFeed` once parsing has finished.
  func result() -> RSSFeed {
    feed
  }

  /// Tracks the element stack and captures item-level attributes when a tag opens.
  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes attributeDict: [String: String]
  ) {
    let lowered = elementName.lowercased()
    elementStack.append(lowered)
    currentElement = lowered
    currentString = ""

    if lowered == "item" || lowered == "entry" {
      currentItem = RSSItem()
      return
    }

    if lowered == "link" {
      if var item = currentItem {
        if let href = attributeDict["href"], !href.isEmpty {
          if item.link == nil {
            item.link = href
          }
        } else if let rel = attributeDict["rel"], rel.lowercased() != "alternate" {
          // ignore non-primary link rels
        } else if let href = attributeDict["href"], !href.isEmpty {
          item.link = href
        } else if let url = attributeDict["url"], !url.isEmpty {
          item.link = url
        }
        currentItem = item
      } else {
        if let href = attributeDict["href"], !href.isEmpty {
          feed.link = feed.link ?? href
        }
      }
    }
  }

  /// Appends character data encountered inside the current element.
  func parser(_ parser: XMLParser, foundCharacters string: String) {
    currentString += string
  }

  /// Appends CDATA payloads as UTF-8 decoded text fragments.
  func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
    if let fragment = String(data: CDATABlock, encoding: .utf8) {
      currentString += fragment
    }
  }

  /// Closes the current element, applying captured text to either the feed or the active item.
  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let lowered = elementName.lowercased()
    let value = currentString.trimmingCharacters(in: .whitespacesAndNewlines)

    if var item = currentItem {
      switch lowered {
      case "title":
        if !value.isEmpty { item.title = value }
      case "link":
        if !value.isEmpty && item.link == nil {
          item.link = value
        }
      case "description", "summary":
        if !value.isEmpty { item.summary = value }
      case "content", "content:encoded":
        if !value.isEmpty { item.content = value }
      case "pubdate", "published":
        if !value.isEmpty {
          item.publishedString = value
          if let parsed = dateParsers.parse(value) {
            item.publishedDate = parsed
          }
        }
      case "updated", "lastbuilddate":
        if !value.isEmpty {
          item.updatedString = value
          if let parsed = dateParsers.parse(value) {
            item.updatedDate = parsed
          }
        }
      case "guid":
        if item.link == nil, !value.isEmpty {
          item.link = value
        }
      case "item", "entry":
        break
      default:
        break
      }
      if lowered == "item" || lowered == "entry" {
        feed.items.append(item)
        currentItem = nil
      } else {
        currentItem = item
      }
    } else {
      switch lowered {
      case "title":
        if feed.title == nil && !value.isEmpty { feed.title = value }
      case "description", "subtitle":
        if feed.feedDescription == nil && !value.isEmpty { feed.feedDescription = value }
      case "link":
        if feed.link == nil && !value.isEmpty { feed.link = value }
      default:
        break
      }
    }

    if !elementStack.isEmpty { elementStack.removeLast() }
    currentString = ""
  }
}

/// Utility collection of date formatters commonly used in RSS/Atom feeds.
private struct RSSDateParsers {
  private let isoFormatter: ISO8601DateFormatter
  private let isoBasicFormatter: ISO8601DateFormatter
  private let rfc822Formatter: DateFormatter
  private let rfc822AltFormatter: DateFormatter
  private let rfc822TZFormatter: DateFormatter
  private let rfc822TZNoSecondsFormatter: DateFormatter

  /// Configures the formatter variants required to parse typical feed date strings.
  init() {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    isoFormatter = iso

    let isoBasic = ISO8601DateFormatter()
    isoBasic.formatOptions = [.withInternetDateTime]
    isoBasicFormatter = isoBasic

    let rfc = DateFormatter()
    rfc.locale = Locale(identifier: "en_US_POSIX")
    rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    rfc822Formatter = rfc

    let rfcAlt = DateFormatter()
    rfcAlt.locale = Locale(identifier: "en_US_POSIX")
    rfcAlt.dateFormat = "EEE, dd MMM yyyy HH:mm Z"
    rfc822AltFormatter = rfcAlt

    let rfcTZ = DateFormatter()
    rfcTZ.locale = Locale(identifier: "en_US_POSIX")
    rfcTZ.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    rfc822TZFormatter = rfcTZ

    let rfcTZNoSeconds = DateFormatter()
    rfcTZNoSeconds.locale = Locale(identifier: "en_US_POSIX")
    rfcTZNoSeconds.dateFormat = "EEE, dd MMM yyyy HH:mm zzz"
    rfc822TZNoSecondsFormatter = rfcTZNoSeconds
  }

  /// Attempts to interpret the provided feed timestamp using several known formats.
  /// - Parameter string: The raw date string extracted from the feed.
  /// - Returns: A `Date` if any of the supported formatters succeed, otherwise `nil`.
  func parse(_ string: String) -> Date? {
    if let date = isoFormatter.date(from: string) {
      return date
    }
    if let date = isoBasicFormatter.date(from: string) {
      return date
    }
    if let date = rfc822Formatter.date(from: string) {
      return date
    }
    if let date = rfc822AltFormatter.date(from: string) {
      return date
    }
    if let date = rfc822TZFormatter.date(from: string) {
      return date
    }
    if let date = rfc822TZNoSecondsFormatter.date(from: string) {
      return date
    }
    return nil
  }
}
