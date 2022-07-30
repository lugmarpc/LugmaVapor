import Vapor
import Foundation
import JSONValueRX

public protocol Stream {
    associatedtype Request
    associatedtype Extra

    func onOpen(callback: @escaping (Extra) async -> ())
    func onClose(callback: @escaping () async -> ())

    func on<T: Decodable>(signal: String, callback: @escaping (T) async -> ())
    func send<T: Encodable>(event: String, item: T) async throws
}

public struct Nothing: Codable, Error {
    public init(from decoder: Decoder) throws {
    }

    public func encode(to encoder: Encoder) throws {
    }
}

public protocol Transport {
    associatedtype Request
    associatedtype Extra
    associatedtype TStream: Stream where TStream.Extra == Self.Extra, TStream.Request == Self.Request

    func bind<Args: Decodable, Ret: Encodable, Err: Encodable & Error>(method: String, handler callback: @escaping (Request, Args) async throws -> (Result<Ret, Err>))
    func bind(stream: String, handler callback: @escaping (Request, TStream) -> ())
}

public class VaporStream: Stream {
    public typealias Request = Vapor.Request
    public typealias Extra = Dictionary<String, String>

    let socket: WebSocket
    var onOpenCB: ((Dictionary<String, String>) async -> ())?
    var onCloseCB: (() async -> ())?
    var handlers: [String: (JSONValue) async -> ()]

    struct KindedMessageEnc<T: Encodable>: Encodable {
        let type: String
        let content: T
    }
    struct KindedMessageDec<T: Decodable>: Decodable {
        let type: String
        let content: T
    }

    public init(from ws: WebSocket) {
        self.socket = ws
        self.handlers = [:]

        Task {
            do {
                try await ws.onClose.get()
                await self.onCloseCB?()
            } catch { }
        }

        ws.onText { ws, str in // initial
            do {
                let dict = try JSONDecoder().decode(Extra.self, from: str.data(using: .utf8)!)
                await self.onOpenCB?(dict)
                ws.onText { ws, str in // actual callback
                    do {
                        let dict = try JSONDecoder().decode(KindedMessageDec<JSONValue>.self, from: str.data(using: .utf8)!)
                        await self.handlers[dict.type]?(dict.content)
                    } catch {
                        try? await ws.close()   
                    }
                }
            } catch {
                try? await ws.close()
            }
        }
    }

    public func onOpen(callback: @escaping (Dictionary<String, String>) async -> ()) {
        self.onOpenCB = callback
    }

    public func onClose(callback: @escaping () async -> ()) {
        self.onCloseCB = callback
    }

    public func on<T: Decodable>(signal: String, callback: @escaping (T) async -> ()) {
        handlers[signal] = { json in
            do {
                let it: T = try json.decode()
                await callback(it)
            } catch {
                try? await self.socket.close()
            }
        }
    }

    public func send<T: Encodable>(event: String, item: T) async throws {
        let msg = KindedMessageEnc(type: event, content: item)
        do {
            let encoded = try JSONEncoder().encode(msg)
            try await self.socket.send(raw: encoded, opcode: .text)
        } catch {
            try await self.socket.close()
            throw error
        }
    }
}

public struct VaporTransport: Transport {
    public typealias Request = Vapor.Request
    public typealias Extra = Dictionary<String, String>
    public typealias TStream = VaporStream

    let routes: RoutesBuilder

    public init(for builder: RoutesBuilder) {
        self.routes = builder
    }

    public func bind<Args, Ret, Err>(method: String, handler callback: @escaping (Request, Args) async throws -> (Result<Ret, Err>))
        where Args : Decodable
            , Ret : Encodable
            , Err : Encodable, Err : Error
    {
        routes.post(PathComponent(stringLiteral: method)) { req -> Response in
            let item = try req.content.decode(Args.self, using: JSONDecoder())

            switch try await callback(req, item) {
            case .failure(let ret):
                return .init(status: .badRequest, body: .init(data: try JSONEncoder().encode(ret)))
            case .success(let ret):
                return .init(status: .ok, body: .init(data: try JSONEncoder().encode(ret)))
            }
        }
    }
    public func bind(stream: String, handler callback: @escaping (Request, VaporStream) -> ()) {
        routes.webSocket(PathComponent(stringLiteral: stream)) { req, ws in
            callback(req, VaporStream(from: ws))
        }
    }
}

