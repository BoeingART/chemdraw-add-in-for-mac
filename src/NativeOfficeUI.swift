// SPDX-License-Identifier: Apache-2.0
import Foundation
import Network
import Security

struct PanelResponse {
    let status: Int
    let body: Data
    let type: String
    init(_ status:Int, _ object:[String:Any]) {
        self.status = status; self.body = (try? JSONSerialization.data(withJSONObject:object)) ?? Data("{}".utf8); self.type = "application/json"
    }
    init(_ body:Data, type:String) { self.status = 200; self.body = body; self.type = type }
    var wire: Data {
        Data("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n".utf8) + body
    }
}
class PanelRouter {
    let root: URL, token: String
    var port: UInt16 = 17524
    var ready: () -> Bool = { true }
    var editing: () -> Bool = { false }
    var activity: () -> [String:Any] = { [:] }
    var edit: (String) throws -> Void = { _ in }
    var paste: (String) throws -> Void = { _ in }
    init(root:URL) { self.root = root; self.token = UUID().uuidString+UUID().uuidString }
    func response(method:String, target:String, headers:[String:String], body:Data) -> PanelResponse {
        guard let host = headers["host"], ["localhost:\(port)","127.0.0.1:\(port)"].contains(host) else { return PanelResponse(403,["error":"Invalid local host"]) }
        if method == "GET" {
            let path = String(target.split(separator:"?",maxSplits:1).first ?? "")
            if path == "/api/status" { return PanelResponse(200,["ready":ready(),"editing":editing(),"activity":activity()]) }
            let routes = ["/":"taskpane.html","/taskpane.html":"taskpane.html","/help":"taskpane.html","/taskpane.js":"taskpane.js","/style.css":"style.css","/icon-16.png":"icon-16.png","/icon-32.png":"icon-32.png","/icon-80.png":"icon-80.png"]
            guard let name = routes[path], var data = try? Data(contentsOf:root.appendingPathComponent("office/addin/"+name)) else { return PanelResponse(404,["error":"Not found"]) }
            if name.hasSuffix(".html") { data = Data(String(decoding:data,as:UTF8.self).replacingOccurrences(of:"__CFM_TOKEN__",with:token).utf8) }
            let type = name.hasSuffix(".html") ? "text/html; charset=utf-8" : name.hasSuffix(".js") ? "text/javascript; charset=utf-8" : name.hasSuffix(".css") ? "text/css" : "image/png"
            return PanelResponse(data,type:type)
        }
        guard method == "POST" && ["/api/edit","/api/paste"].contains(target), (headers["origin"] ?? "https://localhost:\(port)") == "https://localhost:\(port)", headers["x-chemoffice-token"] == token else {
            return PanelResponse(403,["error":"Open this action from the ChemOffice Add-ins for Mac panel"])
        }
        do {
            try require(ready(),"Open ChemOffice Add-ins for Mac → 完成安装 to finish permissions and start the paste helper.")
            try require(!body.isEmpty && body.count <= 128,"Invalid request")
            let object = try JSONSerialization.jsonObject(with:body) as? [String:Any]
            guard let host = object?["host"] as? String, ["word","powerpoint"].contains(host) else { throw ChemOfficeError("Select a drawing in Word or PowerPoint") }
            if target == "/api/paste" { try paste(host); return PanelResponse(200,["pasted":true]) }
            try edit(host); return PanelResponse(200,["opened":true])
        } catch { return PanelResponse(400,["error":error.localizedDescription]) }
    }
}
class NativeOfficeServer {
    let router: PanelRouter
    let listener: NWListener
    let queue = DispatchQueue(label:"ChemOffice HTTPS",attributes:.concurrent)
    private let lock = NSLock()
    private var connections = [ObjectIdentifier:NWConnection]()
    init(root:URL, port:UInt16 = 17524) throws {
        router = PanelRouter(root:root)
        let tls = NativePaths.work(root:root).appendingPathComponent("tls")
        let cert = try command("/usr/bin/openssl",["x509","-in",tls.appendingPathComponent("localhost.pem").path,"-outform","DER"])
        let key = try command("/usr/bin/openssl",["rsa","-in",tls.appendingPathComponent("localhost-key.pem").path,"-outform","DER"])
        guard let certificate = SecCertificateCreateWithData(nil,cert as CFData),
              let privateKey = SecKeyCreateWithData(key as CFData,[kSecAttrKeyType:kSecAttrKeyTypeRSA,kSecAttrKeyClass:kSecAttrKeyClassPrivate] as CFDictionary,nil),
              let identity = SecIdentityCreate(nil,certificate,privateKey), let local = sec_identity_create(identity) else { throw ChemOfficeError("Cannot load localhost TLS identity") }
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions,.TLSv12)
        sec_protocol_options_set_local_identity(options.securityProtocolOptions,local)
        let parameters = NWParameters(tls:options,tcp:NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!)
        listener = try NWListener(using:parameters)
    }
    func start() throws {
        let ready = DispatchSemaphore(value:0)
        var failure: NWError?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): failure = error; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue:queue)
        try require(ready.wait(timeout:.now()+10) == .success,"Local HTTPS listener timed out")
        if let failure { throw failure }
        guard let port = listener.port?.rawValue else { throw ChemOfficeError("Local HTTPS listener has no port") }
        router.port = port
    }
    private func accept(_ connection:NWConnection) {
        lock.lock(); connections[ObjectIdentifier(connection)] = connection; lock.unlock()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed = state, let connection { self?.remove(connection) }
            if case .cancelled = state, let connection { self?.remove(connection) }
        }
        connection.start(queue:queue)
        queue.asyncAfter(deadline:.now()+120) { [weak connection] in connection?.cancel() }
        receive(connection,buffer:Data())
    }
    private func remove(_ connection:NWConnection) { lock.lock(); connections.removeValue(forKey:ObjectIdentifier(connection)); lock.unlock() }
    private func send(_ response:PanelResponse, _ connection:NWConnection) {
        connection.send(content:response.wire,completion:.contentProcessed { _ in connection.cancel() })
    }
    private func receive(_ connection:NWConnection, buffer:Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:16384) { [weak self] data,_,complete,error in
            guard let self else { return }
            let next = buffer + (data ?? Data())
            guard next.count <= 16512 else { self.send(PanelResponse(400,["error":"Request too large"]),connection); return }
            if let boundary = next.range(of:Data("\r\n\r\n".utf8)) {
                let lines = String(decoding:next[..<boundary.lowerBound],as:UTF8.self).components(separatedBy:"\r\n")
                let request = lines[0].split(separator:" ")
                guard request.count == 3 else { self.send(PanelResponse(400,["error":"Invalid HTTP request"]),connection); return }
                var headers = [String:String]()
                for line in lines.dropFirst() {
                    let pair = line.split(separator:":",maxSplits:1,omittingEmptySubsequences:false)
                    guard pair.count == 2 else { self.send(PanelResponse(400,["error":"Invalid HTTP header"]),connection); return }
                    let name = pair[0].lowercased()
                    guard headers[name] == nil else { self.send(PanelResponse(400,["error":"Duplicate HTTP header"]),connection); return }
                    headers[name] = pair[1].trimmingCharacters(in:.whitespaces)
                }
                guard headers["transfer-encoding"] == nil, let length = Int(headers["content-length"] ?? "0"), (0...128).contains(length) else {
                    self.send(PanelResponse(400,["error":"Invalid request size"]),connection); return
                }
                let body = next.subdata(in:boundary.upperBound..<next.count)
                if body.count >= length {
                    guard body.count == length else { self.send(PanelResponse(400,["error":"Invalid HTTP body"]),connection); return }
                    self.send(self.router.response(method:String(request[0]),target:String(request[1]),headers:headers,body:body),connection); return
                }
            }
            if complete || error != nil { connection.cancel() } else { self.receive(connection,buffer:next) }
        }
    }
    func stop() {
        listener.cancel(); lock.lock(); let active = Array(connections.values); connections.removeAll(); lock.unlock()
        active.forEach { $0.cancel() }
    }
    deinit { stop() }
}
