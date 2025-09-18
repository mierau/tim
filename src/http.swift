import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension URLSession {
  func syncRequest(with url: URL) -> (Data?, URLResponse?, Error?) {
    let semaphore = DispatchSemaphore(value: 0)
    var resultData: Data?
    var resultResponse: URLResponse?
    var resultError: Error?

    let task = dataTask(with: url) { data, response, error in
      resultData = data
      resultResponse = response
      resultError = error
      semaphore.signal()
    }

    task.resume()
    semaphore.wait()
    return (resultData, resultResponse, resultError)
  }

  func syncRequest(with request: URLRequest) -> (Data?, URLResponse?, Error?) {
    let semaphore = DispatchSemaphore(value: 0)
    var resultData: Data?
    var resultResponse: URLResponse?
    var resultError: Error?

    let task = dataTask(with: request) { data, response, error in
      resultData = data
      resultResponse = response
      resultError = error
      semaphore.signal()
    }

    task.resume()
    semaphore.wait()
    return (resultData, resultResponse, resultError)
  }
}
