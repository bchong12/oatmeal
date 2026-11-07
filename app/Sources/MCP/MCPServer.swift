import Foundation
import Network

/// A local MCP server ("Streamable HTTP" transport, JSON responses only) so
/// agents on this Mac can read and plan the user's day in Oatmeal.
///
/// Listens on 127.0.0.1:29985 only. POST /mcp takes JSON-RPC (single message or
/// batch) and answers with `application/json`. Requests carrying a non-local
/// Origin header are refused (DNS rebinding protection).
@MainActor
final class MCPServer: ObservableObject {
    static let shared = MCPServer()
    static let port: UInt16 = 29985
    static let protocolVersion = "2025-03-26"

    @Published private(set) var isRunning = false
    /// The `clientInfo.name` of the most recent client that initialized.
    @Published private(set) var lastClient: String?

    var url: String { "http://127.0.0.1:\(Self.port)/mcp" }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.oatmeal.mcp")
    private let tools = MCPTools()

    private init() {}

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.acceptLocalOnly = true
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [queue] conn in
                MCPConnection(conn, queue: queue).start()
            }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.listener === l else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        print("[MCP] listening on \(self.url)")
                    case .failed(let err):
                        print("[MCP] listener failed: \(err)")
                        self.stop()
                    case .cancelled:
                        self.isRunning = false
                    default: break
                    }
                }
            }
            listener = l
            l.start(queue: queue)
        } catch {
            print("[MCP] couldn't start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: HTTP routing

    fileprivate func handle(_ req: HTTPRequest) -> HTTPResponse {
        if let origin = req.headers["origin"], !Self.isLocalOrigin(origin) {
            return .json(403, ["jsonrpc": "2.0", "id": NSNull(),
                               "error": ["code": -32000, "message": "Forbidden: non-local Origin \(origin)"]])
        }
        let path = req.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? req.path
        guard path == "/mcp" || path == "/mcp/" else {
            return HTTPResponse(status: 404, headers: ["Content-Type": "text/plain"], body: Data("Not found. MCP lives at /mcp".utf8))
        }
        switch req.method {
        case "POST": break
        case "OPTIONS":
            return HTTPResponse(status: 204, headers: ["Allow": "POST, DELETE, OPTIONS"], body: Data())
        case "DELETE":
            return HTTPResponse(status: 200, headers: [:], body: Data())   // sessions are stateless here
        default:
            return HTTPResponse(status: 405, headers: ["Allow": "POST, DELETE", "Content-Type": "text/plain"],
                                body: Data("Method not allowed. Oatmeal doesn't offer an SSE stream; POST JSON-RPC to /mcp.".utf8))
        }

        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: req.body, options: [.fragmentsAllowed]) }
        catch { return .json(400, Self.errorObject(id: NSNull(), code: -32700, message: "Parse error")) }

        var sessionID: String?
        if let batch = parsed as? [Any] {
            guard !batch.isEmpty else { return .json(400, Self.errorObject(id: NSNull(), code: -32600, message: "Empty batch")) }
            let replies = batch.compactMap { dispatch($0, sessionID: &sessionID) }
            if replies.isEmpty { return HTTPResponse(status: 202, headers: [:], body: Data()) }
            return .json(200, replies, extra: sessionID.map { ["Mcp-Session-Id": $0] } ?? [:])
        }
        guard let reply = dispatch(parsed, sessionID: &sessionID) else {
            return HTTPResponse(status: 202, headers: [:], body: Data())
        }
        return .json(200, reply, extra: sessionID.map { ["Mcp-Session-Id": $0] } ?? [:])
    }

    /// Handles one JSON-RPC message. Returns nil for notifications and client responses.
    private func dispatch(_ message: Any, sessionID: inout String?) -> [String: Any]? {
        guard let msg = message as? [String: Any] else {
            return Self.errorObject(id: NSNull(), code: -32600, message: "Invalid request")
        }
        let id = msg["id"]
        guard let method = msg["method"] as? String else {
            return id == nil ? Self.errorObject(id: NSNull(), code: -32600, message: "Invalid request") : nil
        }
        guard let id, !(id is NSNull) else { return nil }   // notification: nothing to say back
        let params = msg["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            if let info = params["clientInfo"] as? [String: Any], let name = info["name"] as? String {
                lastClient = name
            }
            sessionID = UUID().uuidString
            let requested = params["protocolVersion"] as? String
            let supported = ["2025-03-26", "2025-06-18", "2024-11-05"]
            return Self.result(id: id, [
                "protocolVersion": requested.flatMap { supported.contains($0) ? $0 : nil } ?? Self.protocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "oatmeal", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"],
                "instructions": Self.instructions,
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": MCPTools.definitions])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return Self.errorObject(id: id, code: -32602, message: "tools/call needs a tool name")
            }
            guard MCPTools.names.contains(name) else {
                return Self.errorObject(id: id, code: -32602, message: "Unknown tool: \(name)")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            return Self.result(id: id, tools.call(name, args))
        default:
            return Self.errorObject(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: Helpers

    nonisolated static func isLocalOrigin(_ origin: String) -> Bool {
        if origin == "null" { return false }
        guard let comps = URLComponents(string: origin), let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = comps.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    private static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func errorObject(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    static let instructions = """
    Oatmeal is the user's meeting notepad and dictation app for Mac. It holds:
    - Meetings: notes Oatmeal recorded on this Mac (mic + call audio, no bot), with title, attendees, summary, \
    action items, Granola-style notes, the user's own typed notes and a timestamped transcript (You = the user, \
    Them = the call). Meetings can be filed in folders.
    - Dictations: text the user spoke with Oatmeal Flow (hold right Option) and dropped into other apps.
    Tips: `list_meetings` with a `query` finds the call where something came up; `get_meeting` reads it in full. \
    `update_meeting` saves a cleaned-up transcript, title, notes, summary and action items back; it never \
    changes the user's own notes. Dates are local time.
    """
}

// MARK: - HTTP plumbing

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]   // lowercased names
    var body: Data
}

struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    static func json(_ status: Int, _ object: Any, extra: [String: String] = [:]) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8)
        var h = ["Content-Type": "application/json"]
        h.merge(extra) { $1 }
        return HTTPResponse(status: status, headers: h, body: data)
    }

    func serialized(keepAlive: Bool) -> Data {
        let reasons = [200: "OK", 202: "Accepted", 204: "No Content", 400: "Bad Request", 403: "Forbidden",
                       404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large", 500: "Internal Server Error"]
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "Status")\r\n"
        var h = headers
        h["Content-Length"] = "\(body.count)"
        h["Connection"] = keepAlive ? "keep-alive" : "close"
        h["Cache-Control"] = "no-store"
        for (k, v) in h.sorted(by: { $0.key < $1.key }) { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

/// One TCP connection: reads HTTP/1.1 requests (Content-Length bodies), hands
/// them to the server on the main actor, writes the reply. Supports keep-alive.
private final class MCPConnection: @unchecked Sendable {
    private let conn: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private static let maxBody = 8 * 1024 * 1024

    init(_ conn: NWConnection, queue: DispatchQueue) {
        self.conn = conn
        self.queue = queue
    }

    func start() {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.conn.stateUpdateHandler = nil
            default: break
            }
        }
        conn.start(queue: queue)
        receive()
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty { buffer.append(data) }
            if processBuffer() { return }
            if isComplete || error != nil { conn.cancel(); return }
            receive()
        }
    }

    /// Tries to parse a full request out of the buffer. Returns true when it took
    /// over (a request is being handled or the connection was closed).
    private func processBuffer() -> Bool {
        let sep = Data("\r\n\r\n".utf8)
        guard let headEnd = buffer.range(of: sep) else {
            if buffer.count > 64 * 1024 { reply(HTTPResponse(status: 400, headers: [:], body: Data()), keepAlive: false) ; return true }
            return false
        }
        let headText = String(decoding: buffer[buffer.startIndex..<headEnd.lowerBound], as: UTF8.self)
        var lines = headText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else {
            reply(HTTPResponse(status: 400, headers: [:], body: Data()), keepAlive: false); return true
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        if length > Self.maxBody {
            reply(HTTPResponse(status: 413, headers: [:], body: Data()), keepAlive: false); return true
        }
        let bodyStart = headEnd.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return false }
        let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
        buffer = Data(buffer[(bodyStart + length)...])

        let request = HTTPRequest(method: String(requestLine[0]).uppercased(), path: String(requestLine[1]),
                                  headers: headers, body: body)
        let version = requestLine.count > 2 ? String(requestLine[2]) : "HTTP/1.1"
        let connHeader = headers["connection"]?.lowercased() ?? ""
        let keepAlive = version == "HTTP/1.1" ? connHeader != "close" : connHeader == "keep-alive"
        Task { @MainActor in
            let response = MCPServer.shared.handle(request)
            self.queue.async { self.reply(response, keepAlive: keepAlive) }
        }
        return true
    }

    private func reply(_ response: HTTPResponse, keepAlive: Bool) {
        conn.send(content: response.serialized(keepAlive: keepAlive), completion: .contentProcessed { [self] _ in
            if keepAlive {
                if !processBuffer() { receive() }
            } else {
                conn.cancel()
            }
        })
    }
}
