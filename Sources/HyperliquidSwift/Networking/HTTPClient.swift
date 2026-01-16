import Foundation

/// HTTP client for Hyperliquid API requests
public actor HTTPClient {
    private let baseURL: String
    private let session: URLSession

    /// Initialize with a base URL
    /// - Parameter baseURL: The API base URL (e.g., mainnet or testnet)
    public init(baseURL: String) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    /// Perform a POST request to the info endpoint
    /// - Parameter payload: The request payload
    /// - Returns: Decoded response
    public func postInfo<T: Decodable>(_ payload: [String: Sendable]) async throws -> T {
        try await post(endpoint: "/info", payload: payload)
    }

    /// Perform a POST request to the info endpoint with raw JSON response
    /// - Parameter payload: The request payload
    /// - Returns: Raw JSON data
    public func postInfoRaw(_ payload: [String: Sendable]) async throws -> Data {
        try await postRaw(endpoint: "/info", payload: payload)
    }

    /// Perform a POST request to the exchange endpoint
    /// - Parameter payload: The request payload
    /// - Returns: Decoded response
    public func postExchange<T: Decodable>(_ payload: [String: Sendable]) async throws -> T {
        try await post(endpoint: "/exchange", payload: payload)
    }

    /// Perform a POST request to the exchange endpoint with raw JSON response
    /// - Parameter payload: The request payload
    /// - Returns: Raw JSON data
    public func postExchangeRaw(_ payload: [String: Sendable]) async throws -> Data {
        try await postRaw(endpoint: "/exchange", payload: payload)
    }

    /// Perform a POST request to the exchange endpoint with pre-serialized JSON data
    /// - Parameter jsonData: Pre-serialized JSON data
    /// - Returns: Raw JSON data
    public func postExchangeRawData(_ jsonData: Data) async throws -> Data {
        try await postRawData(endpoint: "/exchange", jsonData: jsonData)
    }

    /// Perform a POST request and decode the response
    private func post<T: Decodable>(endpoint: String, payload: [String: Sendable]) async throws -> T {
        let data = try await postRaw(endpoint: endpoint, payload: payload)
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HyperliquidError.decodingError(underlying: error)
        }
    }

    /// Perform a POST request and return raw data
    private func postRaw(endpoint: String, payload: [String: Sendable]) async throws -> Data {
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw HyperliquidError.invalidParameter("Failed to serialize payload: \(error)")
        }
        return try await postRawData(endpoint: endpoint, jsonData: jsonData)
    }

    /// Perform a POST request with pre-serialized JSON data and return raw data
    private func postRawData(endpoint: String, jsonData: Data) async throws -> Data {
        guard let url = URL(string: baseURL + endpoint) else {
            throw HyperliquidError.invalidParameter("Invalid URL: \(baseURL + endpoint)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HyperliquidError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HyperliquidError.networkError(underlying: NSError(domain: "HTTPClient", code: -1))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw HyperliquidError.apiError(
                status: "HTTP \(httpResponse.statusCode)",
                response: String(data: data, encoding: .utf8)
            )
        }

        return data
    }
}
