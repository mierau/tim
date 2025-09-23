import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Errors that may occur while fetching or decoding Bluesky content.
enum BlueskyError: Error, LocalizedError {
  case invalidHandle
  case requestFailed(String)
  case emptyFeed
  case decodeFailed

  var errorDescription: String? {
    switch self {
    case .invalidHandle:
      return "Please provide a valid Bluesky handle (e.g. dustin.bsky.social)."
    case .requestFailed(let reason):
      return reason
    case .emptyFeed:
      return "That Bluesky feed did not contain any posts yet."
    case .decodeFailed:
      return "Bluesky responded with data we couldn't understand."
    }
  }
}

/// A sanitized representation of a Bluesky post suitable for display.
struct BlueskyPost {
  /// The text content authored in the post.
  let text: String
  /// The creation timestamp if Bluesky supplied one.
  let createdAt: Date?
  /// The canonical public permalink for this post when available.
  let url: URL?
  /// The post author's canonical handle.
  let authorHandle: String
  /// The post author's display name, if set.
  let authorDisplayName: String?
  /// Additional metadata describing how the post appeared in the feed.
  let context: PostContext

  /// Describes why a post shows up in the feed (original, repost, etc.).
  enum PostContext {
    case original
    case repost(byDisplayName: String?, handle: String?)
  }
}

/// Metadata for a Bluesky author's feed plus the posts to render.
struct BlueskyFeed {
  /// The author handle the feed was fetched for.
  let handle: String
  /// The preferred display name if Bluesky supplied one.
  let displayName: String?
  /// The ordered posts to display newest-first as returned by the API.
  let posts: [BlueskyPost]
}

/// Convenience helpers for working with the Bluesky public API.
enum BlueskyAPI {
  /// Fetches the most recent posts authored by the supplied handle.
  /// - Parameters:
  ///   - rawHandle: The user-supplied handle, URL, or DID string.
  ///   - limit: Maximum number of timeline entries to retrieve (1...100).
  /// - Returns: A normalized `BlueskyFeed` ready for rendering.
  static func fetchFeed(rawHandle: String, limit: Int = 30) throws -> BlueskyFeed {
    let actor = try normalizeHandle(rawHandle)
    let boundedLimit = max(1, min(limit, 100))

    var components = URLComponents()
    components.scheme = "https"
    components.host = "public.api.bsky.app"
    components.path = "/xrpc/app.bsky.feed.getAuthorFeed"
    components.queryItems = [
      URLQueryItem(name: "actor", value: actor),
      URLQueryItem(name: "limit", value: String(boundedLimit))
    ]

    guard let url = components.url else {
      throw BlueskyError.invalidHandle
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response, error) = URLSession.shared.syncRequest(with: request)

    if let error {
      throw BlueskyError.requestFailed(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw BlueskyError.requestFailed("Bluesky returned an unexpected response.")
    }

    guard (200...299).contains(http.statusCode) else {
      throw BlueskyError.requestFailed("Bluesky responded with status \(http.statusCode).")
    }

    guard let data else {
      throw BlueskyError.requestFailed("Bluesky returned an empty response body.")
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .useDefaultKeys

    guard let feedResponse = try? decoder.decode(AuthorFeedResponse.self, from: data) else {
      throw BlueskyError.decodeFailed
    }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var posts: [BlueskyPost] = []
    posts.reserveCapacity(feedResponse.feed.count)

    for item in feedResponse.feed {
      guard let record = item.post.record,
        let text = record.text?.trimmingCharacters(in: .whitespacesAndNewlines),
        !text.isEmpty
      else { continue }

      let createdAt: Date?
      if let timestamp = record.createdAt {
        createdAt = isoFormatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
      } else {
        createdAt = nil
      }

      let permalink = permalink(for: item.post.uri, authorHandle: item.post.author.handle)
      let context: BlueskyPost.PostContext
      if let reason = item.reason, reason.type == "app.bsky.feed.defs#reasonRepost" {
        context = .repost(byDisplayName: reason.by?.displayName, handle: reason.by?.handle)
      } else {
        context = .original
      }

      posts.append(
        BlueskyPost(
          text: text,
          createdAt: createdAt,
          url: permalink,
          authorHandle: item.post.author.handle,
          authorDisplayName: item.post.author.displayName,
          context: context))
    }

    guard !posts.isEmpty else { throw BlueskyError.emptyFeed }

    let feedHandle = feedResponse.feed.first?.post.author.handle ?? actor
    let feedDisplayName = feedResponse.feed.first?.post.author.displayName

    return BlueskyFeed(handle: feedHandle, displayName: feedDisplayName, posts: posts)
  }

  // MARK: - Normalization Helpers

  /// Cleans up a user-supplied handle or profile URL to the canonical actor string.
  /// - Parameter raw: The raw string provided on the command line.
  /// - Returns: A normalized handle or DID accepted by the Bluesky API.
  private static func normalizeHandle(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw BlueskyError.invalidHandle }

    if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
      guard let url = URL(string: trimmed) else { throw BlueskyError.invalidHandle }
      return try handleFromURL(url)
    }

    if trimmed.hasPrefix("@") {
      let stripped = String(trimmed.dropFirst())
      guard isValidHandle(stripped) else { throw BlueskyError.invalidHandle }
      return stripped.lowercased()
    }

    if trimmed.hasPrefix("did:") {
      return trimmed
    }

    guard isValidHandle(trimmed) else { throw BlueskyError.invalidHandle }
    return trimmed.lowercased()
  }

  /// Attempts to extract the actor identifier from a Bluesky profile URL.
  /// - Parameter url: The profile URL the user supplied.
  /// - Returns: A valid handle or DID associated with the profile.
  private static func handleFromURL(_ url: URL) throws -> String {
    guard let host = url.host?.lowercased() else { throw BlueskyError.invalidHandle }
    guard host.contains("bsky.app") else { throw BlueskyError.invalidHandle }
    let components = url.pathComponents.filter { $0 != "/" }
    guard components.count >= 2, components[0] == "profile" else {
      throw BlueskyError.invalidHandle
    }
    let actor = components[1]
    if actor.hasPrefix("did:") { return actor }
    guard isValidHandle(actor) else { throw BlueskyError.invalidHandle }
    return actor.lowercased()
  }

  /// Returns true when the supplied handle uses the allowed ATProto charset.
  private static func isValidHandle(_ handle: String) -> Bool {
    let pattern = "^[a-zA-Z0-9.-]{1,253}$"
    return handle.range(of: pattern, options: [.regularExpression]) != nil
  }

  /// Builds the public permalink for a post from its AT URI.
  private static func permalink(for uri: String, authorHandle: String) -> URL? {
    guard uri.hasPrefix("at://") else { return nil }
    let components = uri.split(separator: "/")
    guard components.count >= 4 else { return nil }
    let rkey = components.last.map(String.init) ?? ""
    var profileComponent = authorHandle
    if profileComponent.isEmpty {
      profileComponent = String(components[2])
    }
    var urlComponents = URLComponents()
    urlComponents.scheme = "https"
    urlComponents.host = "bsky.app"
    urlComponents.path = "/profile/\(profileComponent)/post/\(rkey)"
    return urlComponents.url
  }

  /// User agent string used for Bluesky requests.
  private static let userAgent = "tim-cli/1.0 (+https://github.com/mierau/tim)"

  // MARK: - Response Models

  private struct AuthorFeedResponse: Decodable {
    let feed: [FeedItem]

    struct FeedItem: Decodable {
      let post: Post
      let reason: Reason?
    }

    struct Post: Decodable {
      let uri: String
      let author: Author
      let record: Record?
    }

    struct Author: Decodable {
      let handle: String
      let displayName: String?
    }

    struct Record: Decodable {
      let text: String?
      let createdAt: String?
    }

    struct Reason: Decodable {
      let type: String
      let by: ReasonAuthor?

      enum CodingKeys: String, CodingKey {
        case type = "$type"
        case by
      }
    }

    struct ReasonAuthor: Decodable {
      let handle: String?
      let displayName: String?
    }
  }
}
