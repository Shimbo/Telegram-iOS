import Foundation
#if os(macOS)
    import PostboxMac
    import TelegramApiMac
    import MtProtoKitMac
#else
    import Postbox
    import TelegramApi
    import MtProtoKit
#endif

import SwiftSignalKitMac

extension String: PostboxCoding {
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self, forKey: "s")
    }
    public init(decoder: PostboxDecoder) {
        self = decoder.decodeStringForKey("s", orElse: "")
    }
}
extension Int32: PostboxCoding {
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self, forKey: "i")
    }
    public init(decoder: PostboxDecoder) {
        self = decoder.decodeInt32ForKey("i", orElse: Int32(0))
    }
}

extension PeerGroupId: PostboxCoding, Comparable {
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.rawValue, forKey: "i")
    }
    public init(decoder: PostboxDecoder) {
        self = .group(decoder.decodeInt32ForKey("i", orElse: 0))
    }
    static public func < (lhs: PeerGroupId, rhs: PeerGroupId) -> Bool { return lhs.rawValue < rhs.rawValue }
}

/*extension PeerId: PostboxCoding {
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.toInt64(), forKey: "peerid")
    }
    public init(decoder: PostboxDecoder) {
        self = PeerId(decoder.decodeInt64ForKey("peerid", orElse: 0))
    }
}*/

public final class Circles: Equatable, PostboxCoding, PreferencesEntry {
    public static let baseApiUrl = "https://api.circles.is/"
    public static let baseDevApiUrl = "https://api.dev.randomcoffee.us/"
    public static var defaultConfig:Circles {
        return Circles(botId: PeerId(namespace: 0, id: 871013339))
    }
    
    struct ApiCircle {
        let id: PeerGroupId
        let name: String
        var peers: [PeerId]
        var index: Int
    }

    public static func getSettings(postbox: Postbox) -> Signal<Circles, NoError> {
        return postbox.transaction { transaction -> Circles in
            if let entry = transaction.getPreferencesEntry(key: PreferencesKeys.circlesSettings) as? Circles {
                return entry
            } else {
                return Circles.defaultConfig
            }
        }
    }

    public static func updateSettings(postbox: Postbox, _ f: @escaping(Circles) -> Circles) -> Signal<Void, NoError> {
        return postbox.transaction { transaction in
            return transaction.updatePreferencesEntry(key: PreferencesKeys.circlesSettings) { entry in
                if let entry = entry as? Circles {
                    return f(entry)
                } else {
                    return f(Circles.defaultConfig)
                }
            }
        }
    }
    
    public static func settingsView(postbox: Postbox) -> Signal<Circles, NoError> {
        return postbox.preferencesView(keys: [PreferencesKeys.circlesSettings])
        |> map { view -> Circles in
            if let settings = view.values[PreferencesKeys.circlesSettings] as? Circles {
                return settings
            } else {
                return Circles.defaultConfig
            }
        } |> distinctUntilChanged
    }
    public static func fetchBotId() -> Signal<PeerId, NoError> {
        /*return Signal<PeerId, NoError> { subscriber in
            let urlString = Circles.baseApiUrl+"bot_id"
            Alamofire.request(urlString).responseJSON { response in
                if let error = response.error {
                    //subscriber.putError(error)
                } else {
                    if let result = response.result.value {
                        let json = SwiftyJSON.JSON(result)
                        subscriber.putNext(PeerId(json["id"].int64Value))
                    }
                }
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }*/
        return .single(PeerId(namespace: 0, id: 871013339))
    }
    public static func fetchToken(postbox: Postbox, id: PeerId, requestToken: String = "") -> Signal<String?, NoError> {
        return Circles.getSettings(postbox: postbox)
        |> mapToSignal { settings in
            return Signal<String?, NoError> { subscriber in
                let urlString = settings.url+"login/"+String(id.id)
                
                let url = URL(string: urlString)!
                var request = URLRequest(url: url)
                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                    guard let data = data,
                        let response = response as? HTTPURLResponse,
                        error == nil else {
                            subscriber.putNext(nil)
                            subscriber.putCompletion()
                            return
                        }
                    guard (200 ... 299) ~= response.statusCode else {
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                        return
                    }

                    if case let .dictionary(json) = JSON(data: data) {
                        if case let .string(token) = json["token"] {
                            subscriber.putNext(token)
                        }
                    } else {
                        subscriber.putNext(nil)
                    }
                    subscriber.putCompletion()
                }
                task.resume()
                return EmptyDisposable
            }
        }
    }
    
    public static func fetch(postbox: Postbox, userId: PeerId) -> Signal<Void, NoError> {
        return Circles.getSettings(postbox: postbox)
        |> mapToSignal { settings -> Signal<[ApiCircle],NoError> in
            if let token = settings.token {
                return Signal<[ApiCircle], NoError> { subscriber in
                    let urlString = settings.url
                    let url = URL(string: urlString)!
                    var request = URLRequest(url: url)
                    request.setValue(token, forHTTPHeaderField: "Authorization")
                    let task = URLSession.shared.dataTask(with: request) {data, response, error in
                        guard let data = data,
                            let response = response as? HTTPURLResponse,
                            error == nil else {
                                subscriber.putNext([])
                                subscriber.putCompletion()
                                return
                            }
                        guard (200 ... 299) ~= response.statusCode else {
                            subscriber.putNext([])
                            subscriber.putCompletion()
                            return
                        }
                        var apiCircles:[ApiCircle] = []
                        if case let .dictionary(json) = JSON(data: data) {
                            if case let .array(circles) = json["circles"] {
                                for (index, circle) in circles.enumerated() {
                                    if case let .dictionary(circle) = circle {
                                        if case let .number(id) = circle["id"],
                                            case let .string(name) = circle["name"],
                                            case let .array(peers) = circle["peers"],
                                            case let .array(members) = circle["members"] {
                                            
                                            apiCircles.append(ApiCircle(
                                                id: PeerGroupId(rawValue: Int32(id)),
                                                name: name,
                                                peers: (peers+members).compactMap { p -> PeerId? in
                                                    if case let .number(id) = p {
                                                        return parseBotApiPeerId(Int64(id))
                                                    } else {
                                                        return nil
                                                    }
                                                },
                                                index: index
                                            ))
                                        }
                                    }
                                }
                            }
                        }
                        for (c1idx, c1) in apiCircles.sorted(by: { $0.index < $1.index}).enumerated() {
                            for p1 in c1.peers {
                                for var (c2idx, c2) in apiCircles.enumerated() {
                                    if c1.id != c2.id && c1idx < c2idx {
                                        if let idx = apiCircles[c2idx].peers.firstIndex(of: p1) {
                                            apiCircles[c2idx].peers.remove(at: idx)
                                        }
                                    }
                                }
                            }
                        }

                        subscriber.putNext(apiCircles)
                        subscriber.putCompletion()
                    }
                    task.resume()
                    return EmptyDisposable
                }
            } else {
                return .single([])
            }
        } |> mapToSignal { circles in
            return Circles.updateSettings(postbox: postbox) { old in
                let newValue = Circles.defaultConfig
                newValue.dev = old.dev
                newValue.botId = old.botId
                newValue.token = old.token
                newValue.groupNames = [:]
                newValue.localInclusions = old.localInclusions
                newValue.remoteInclusions = [:]
                newValue.index = [:]
                for c in circles {
                    newValue.index[c.id] = Int32(c.index)
                    newValue.groupNames[c.id] = c.name
                    for peer in c.peers {
                        if peer != userId {
                            newValue.remoteInclusions[peer] = c.id
                            
                        }
                    }
                }
                return newValue
            }
        }
    }
    
    public static func updateCirclesInclusions(postbox: Postbox) -> Signal<Void, NoError> {
        return Circles.getSettings(postbox: postbox) |> mapToSignal { settings in
            return postbox.transaction { transaction in
                for (peer, group) in settings.inclusions {
                    transaction.updatePeerChatListInclusion(
                        peer,
                        inclusion: .ifHasMessagesOrOneOf(
                            groupId: group,
                            pinningIndex: nil,
                            minTimestamp: nil
                        )
                    )
                }
            }
        }
    }
    
    public static func collectGroupPeers(postbox: Postbox, network: Network, peerId: PeerId) -> Signal<(PeerId,[PeerId]), NoError> {
        return postbox.transaction { transaction -> Signal<Api.messages.ChatFull, MTRpcError>? in
            switch peerId.namespace {
            case Namespaces.Peer.CloudGroup:
                if let peer = transaction.getPeer(peerId){
                    return network.request(Api.functions.messages.getFullChat(chatId: peerId.id))
                } else {
                    return nil
                }
            default:
                return nil
            }
        } |> mapToSignal { request in
            if let request = request {
                return request |> retryRequest |> map { result in
                    switch result {
                    case let .chatFull(chatFull, chats, users):
                        return (peerId, users.map { TelegramUser(user: $0).id })
                    }
                }
            } else {
                return .single((peerId, []))
            }
        }
    }
    
    public static func collectCirclePeers(postbox: Postbox, network: Network, circleId: PeerGroupId, members: [PeerId]) -> Signal<(PeerGroupId, [PeerId:[PeerId]]), NoError> {
        let chats = members.filter { $0.namespace == Namespaces.Peer.CloudGroup }
        return combineLatest(queue: Queue(), chats.map { collectGroupPeers(postbox: postbox, network: network, peerId: $0) })
        |> map { (circleId, $0.reduce(into: [PeerId:[PeerId]]()) { $0[$1.0] = $1.1 }) }
    }
        
    public static func collectPeers(postbox: Postbox, network: Network) -> Signal<[PeerGroupId: [PeerId: [PeerId]]], NoError> {
        return Circles.getSettings(postbox: postbox)
        |> mapToSignal { settings in
            return combineLatest(settings.groupNames.keys.map { circleId in
                return collectCirclePeers(
                    postbox: postbox,
                    network: network,
                    circleId: circleId,
                    members: settings.remoteInclusions.keys.filter { settings.remoteInclusions[$0] == circleId }
                )
            })
        } |> map { $0.reduce(into: [PeerGroupId: [PeerId: [PeerId]]]()) { $0[$1.0] = $1.1 } }
    }
        
    public static func sendMembers(postbox: Postbox, network: Network, userId: PeerId) -> Signal<Void, NoError> {
        struct Connection: Codable {
            var chat: Int64
            var members: [Int64]
        }
        struct CollectedCircle: Codable {
            var circle: Int32
            var connections: [Connection]
        }
        return Circles.getSettings(postbox: postbox)
        |> mapToSignal { settings in
            if let token = settings.token {
                return Circles.collectPeers(postbox: postbox, network: network)
                |> mapToSignal { collected in
                    return Signal<[CollectedCircle], NoError> { subscriber in
                        let apiArray = collected.keys.map { circleId in
                            return CollectedCircle(
                                circle: circleId.rawValue,
                                connections: collected[circleId]!.keys.map { Connection(
                                    chat: $0.botApiId,
                                    members: collected[circleId]![$0]!.map { $0.botApiId }
                                )}
                            )
                        }
                        subscriber.putNext(apiArray)
                        let jsonData = try! JSONEncoder().encode(apiArray)
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        
                        let urlString = settings.url
                        let url = URL(string: urlString)!
                        var request = URLRequest(url: url)
                        request.setValue(token, forHTTPHeaderField: "Authorization")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpMethod = "POST"
                        request.httpBody = jsonData
                        
                        let task = URLSession.shared.dataTask(with: request) { data, response, error in
                            guard let data = data,
                                let response = response as? HTTPURLResponse,
                                error == nil else {
                                    subscriber.putCompletion()
                                    return
                                }
                            guard (200 ... 299) ~= response.statusCode else {
                                subscriber.putCompletion()
                                return
                            }
                            subscriber.putCompletion()
                        }
                        task.resume()
                        return EmptyDisposable
                    }
                } |> mapToSignal { circles in
                    return Circles.updateSettings(postbox: postbox) { old in
                        let newValue = Circles.defaultConfig
                        newValue.dev = old.dev
                        newValue.botId = old.botId
                        newValue.token = old.token
                        newValue.groupNames = old.groupNames
                        newValue.localInclusions = old.localInclusions
                        newValue.remoteInclusions = old.remoteInclusions
                        newValue.index = old.index
                        for circle in circles {
                            for connection in circle.connections {
                                for peer in connection.members {
                                    let peerId = parseBotApiPeerId(peer)
                                    if peerId != userId {
                                        newValue.remoteInclusions[peerId] = PeerGroupId(rawValue: circle.circle)
                                    }
                                }
                            }
                        }
                        return newValue
                    }
                }
            } else {
                return .single(Void())
            }
        }
    }
    
    public func isEqual(to: PreferencesEntry) -> Bool {
        if let to = to as? Circles {
            return self == to
        } else {
            return false
        }
    }
    
    public var token: String?
    public var botId: PeerId
    public var groupNames: Dictionary<PeerGroupId, String> = [:]
    public var remoteInclusions: Dictionary<PeerId, PeerGroupId> = [:]
    public var localInclusions: Dictionary<PeerId, PeerGroupId> = [:]
    public var dev: Bool
    public var index: Dictionary<PeerGroupId, Int32> = [:]
    
    public var inclusions: Dictionary<PeerId, PeerGroupId> {
        return self.remoteInclusions.merging(self.localInclusions) { $1 }
    }
    public var url:String {
        return self.dev ? Circles.baseDevApiUrl : Circles.baseApiUrl
    }
    
    
    public init(botId: PeerId, dev: Bool = false) {
        self.botId = botId
        self.dev = dev
    }
    
    public init(decoder: PostboxDecoder) {
        self.dev = decoder.decodeBoolForKey("d", orElse: false)
        self.token = decoder.decodeOptionalStringForKey("ct")
        self.botId = PeerId(decoder.decodeInt64ForKey("bi", orElse: 1234))
        
        self.index = decoder.decodeObjectDictionaryForKey(
            "i",
            keyDecoder: {
                PeerGroupId(rawValue: $0.decodeInt32ForKey("k", orElse: 0))
            }
        )
        self.groupNames = decoder.decodeObjectDictionaryForKey(
            "gn",
            keyDecoder: {
                PeerGroupId(rawValue: $0.decodeInt32ForKey("k", orElse: 0))    
            }
        )
        self.localInclusions = decoder.decodeObjectDictionaryForKey(
            "li",
            keyDecoder: {
                PeerId($0.decodeInt64ForKey("k", orElse: 0))
            }
        )
        self.remoteInclusions = decoder.decodeObjectDictionaryForKey(
            "ri",
            keyDecoder: {
                PeerId($0.decodeInt64ForKey("k", orElse: 0))
            }
        )
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeBool(self.dev, forKey: "d")
        if let token = self.token {
            encoder.encodeString(token, forKey: "ct")
        } else {
            encoder.encodeNil(forKey: "ct")
        }
        encoder.encodeInt64(self.botId.toInt64(), forKey: "bi")
        encoder.encodeObjectDictionary(self.groupNames , forKey: "gn", keyEncoder: {
            $1.encodeInt32($0.rawValue, forKey: "k")
        })
        encoder.encodeObjectDictionary(self.index , forKey: "i", keyEncoder: {
            $1.encodeInt32($0.rawValue, forKey: "k")
        })
        encoder.encodeObjectDictionary(self.localInclusions , forKey: "li", keyEncoder: {
            $1.encodeInt64($0.toInt64(), forKey: "k")
        })
        encoder.encodeObjectDictionary(self.remoteInclusions , forKey: "ri", keyEncoder: {
            $1.encodeInt64($0.toInt64(), forKey: "k")
        })
    }
    
    public static func == (lhs: Circles, rhs: Circles) -> Bool {
        return lhs.token == rhs.token && lhs.dev == rhs.dev && lhs.groupNames == rhs.groupNames && lhs.localInclusions == rhs.localInclusions && lhs.remoteInclusions == rhs.remoteInclusions && lhs.index == rhs.index
    }
}

func parseBotApiPeerId(_ apiId: Int64) -> PeerId {
    if  apiId > 0 {
        return PeerId(namespace: Namespaces.Peer.CloudUser, id: Int32(apiId))
    } else {
        let trillion:Int64 = 1000000000000
        if -apiId < trillion {
            return PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id(-apiId))
        } else {
            return PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id(-apiId-trillion))
        }
    }
}

extension PeerId {
    public var botApiId: Int64 {
        switch namespace {
        case Namespaces.Peer.CloudGroup: return -Int64(id)
        case Namespaces.Peer.CloudChannel:
            let trillion:Int64 = 1000000000000
            return -(trillion+Int64(id))
        default: return Int64(id)
        }
    }
}

