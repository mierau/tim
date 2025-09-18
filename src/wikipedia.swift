import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

enum WikipediaError: Error, LocalizedError {
  case invalidURL
  case requestFailed(String)
  case noSuchPage(String)
  case emptyExtract(String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Couldn't build the Wikipedia API URL."
    case .requestFailed(let message):
      return message
    case .noSuchPage(let title):
      return "No Wikipedia page found for \"\(title)\"."
    case .emptyExtract(let title):
      return "Found the page for \"\(title)\", but it has no extract."
    }
  }
}

struct WikipediaArticle {
  let title: String
  let extract: String
}

private struct WikipediaResponse: Decodable {
  struct Query: Decodable {
    struct Page: Decodable {
      let pageid: Int?
      let title: String?
      let extract: String?
      let missing: String?
    }

    let pages: [String: Page]
  }

  let query: Query?
}

func fetchWikipediaArticle(title rawTitle: String, language: String = "en") throws -> WikipediaArticle {
  let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  var components = URLComponents()
  components.scheme = "https"
  components.host = "\(language).wikipedia.org"
  components.path = "/w/api.php"
  components.queryItems = [
    URLQueryItem(name: "action", value: "query"),
    URLQueryItem(name: "prop", value: "extracts"),
    URLQueryItem(name: "explaintext", value: "1"),
    URLQueryItem(name: "redirects", value: "1"),
    URLQueryItem(name: "format", value: "json"),
    URLQueryItem(name: "titles", value: title)
  ]

  guard let url = components.url else { throw WikipediaError.invalidURL }

  var request = URLRequest(url: url)
  request.setValue("tim-cli/1.0 (support@example.com)", forHTTPHeaderField: "User-Agent")

  let (data, response, error) = URLSession.shared.syncRequest(with: request)

  if let error {
    throw WikipediaError.requestFailed(error.localizedDescription)
  }

  guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
    throw WikipediaError.requestFailed("Server responded with an unexpected status.")
  }

  guard let data else {
    throw WikipediaError.requestFailed("No data received from Wikipedia.")
  }

  let decoded = try JSONDecoder().decode(WikipediaResponse.self, from: data)
  guard let page = decoded.query?.pages.values.first else { throw WikipediaError.noSuchPage(title) }
  if page.missing != nil { throw WikipediaError.noSuchPage(title) }
  let resolvedTitle = page.title ?? title
  guard let extract = page.extract, !extract.isEmpty else { throw WikipediaError.emptyExtract(resolvedTitle) }
  return WikipediaArticle(title: resolvedTitle, extract: extract)
}

func wikipediaSuggestedFilename(for rawTitle: String) -> String {
  let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  let lowered = trimmed.lowercased()
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
  if slug.isEmpty { slug = "article" }
  return slug + ".txt"
}
