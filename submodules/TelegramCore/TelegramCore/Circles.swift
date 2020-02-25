import Foundation
import Postbox
import TelegramApi
import MtProtoKit
import SwiftSignalKit
import SyncCore

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

extension PeerId: PostboxCoding {
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.toInt64(), forKey: "peerid")
    }
    public init(decoder: PostboxDecoder) {
        self = PeerId(decoder.decodeInt64ForKey("peerid", orElse: 0))
    }
}

extension Notification.Name {
    static let brokenConnection = Notification.Name("brokenConnection")
    static let invalidToken = Notification.Name("invalidToken")
    static let serverError = Notification.Name("serverError")
}

public final class Circles: Equatable, PostboxCoding, PreferencesEntry {
    public static let baseApiUrl = "https://api.circles.is/"
    public static let baseDevApiUrl = "https://api.dev.randomcoffee.us/"
    
    public static let botName:String = "@TelefrostConciergeBot"
    public static let botNameDev:String = "@TelefrostDevBot"
    public static var defaultConfig:Circles {
        return Circles()
    }
    
    struct ApiCircle {
        let id: PeerGroupId
        let name: String
        var peers: [PeerId]
        var index: Int
    }
    
    public struct ApiUserInfo: Codable {
        let id: Int64
        let username: String?
        let firstname: String?
        let lastname: String?
        let avatar: String?
    }
    
    struct ApiChatInfo: Codable {
        var id: Int64
        var title: String?
        var users: [ApiUserInfo]
    }
    struct CircleChatApiData: Codable {
        var circle: Int32
        var chat: ApiChatInfo
    }
    struct CircleUserApiData: Codable {
        var circle: Int32
        var user: ApiUserInfo
    }

    public static func getSettings(postbox: Postbox) -> Signal<Circles, NoError> {
        return postbox.transaction { transaction -> Circles in
            return Circles.getSettings(transaction: transaction)
        }
    }
    public static func getSettings(transaction: Transaction) -> Circles {
        if let entry = transaction.getPreferencesEntry(key: PreferencesKeys.circlesSettings) as? Circles {
            return entry
        } else {
            return Circles.defaultConfig
        }
    }

    public static func updateSettings(postbox: Postbox, _ f: @escaping(Circles) -> Circles) -> Signal<Void, NoError> {
        return postbox.transaction { transaction in
            return Circles.updateSettings(transaction: transaction, f)
        }
    }
    public static func updateSettings(transaction: Transaction, _ f: @escaping(Circles) -> Circles) {
        return transaction.updatePreferencesEntry(key: PreferencesKeys.circlesSettings) { old in
            let newValue = Circles.defaultConfig
            if let old = old as? Circles {
                newValue.dev = old.dev
                newValue.botPeerId = old.botPeerId
                newValue.token = old.token
                newValue.remoteInclusions = old.remoteInclusions
                newValue.groupNames = old.groupNames
                newValue.index = old.index
                newValue.currentCircle = old.currentCircle
                newValue.lastCirclePeer = old.lastCirclePeer
            }
            return f(newValue)
        }
    }
    
    public static func settingsView(postbox: Postbox) -> Signal<Circles, NoError> {
        return postbox.preferencesView(keys: [PreferencesKeys.circlesSettings])
        |> mapToSignal { view in
            if let settings = view.values[PreferencesKeys.circlesSettings] as? Circles {
                return .single(settings)
            } else {
                return Circles.getSettings(postbox: postbox)
            }
        }
    }
    
    public static func fetch(postbox: Postbox, userId: PeerId) -> Signal<Void, NoError> {
        return Circles.getSettings(postbox: postbox)
        |> mapToSignal { settings -> Signal<Void,NoError> in
            if let token = settings.token {
                let signal = Signal<[ApiCircle]?, NoError> { subscriber in
                    let urlString = settings.url+"tgfork"
                    let url = URL(string: urlString)!
                    var request = URLRequest(url: url)
                    request.setValue(token, forHTTPHeaderField: "Authorization")
                    let task = URLSession.shared.dataTask(with: request) {data, response, error in
                        guard let data = data,
                            let response = response as? HTTPURLResponse,
                            error == nil else {
                                NotificationCenter.default.post(name: .brokenConnection, object: nil)
                                subscriber.putNext(nil)
                                subscriber.putCompletion()
                                return
                            }
                        guard (200 ... 299) ~= response.statusCode else {
                            if response.statusCode == 401 {
                                NotificationCenter.default.post(name: .invalidToken, object: nil)
                            } else {
                                NotificationCenter.default.post(name: .serverError, object: nil)
                            }
                            subscriber.putNext(nil)
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
                return signal |> mapToSignal { circles in
                    if let circles = circles {
                        return Circles.updateSettings(postbox: postbox) { entry in
                            entry.groupNames = [:]
                            entry.remoteInclusions = [:]
                            entry.index = [:]
                            for c in circles {
                                entry.index[c.id] = Int32(c.index)
                                entry.groupNames[c.id] = c.name
                                for peer in c.peers {
                                    if peer != userId {
                                        entry.remoteInclusions[peer] = c.id
                                    }
                                }
                            }
                            return entry
                        }
                    } else {
                        return .single(Void())
                    }
                }
            } else {
                NotificationCenter.default.post(name: .invalidToken, object: nil)
                return .single(Void())
            }
        }
    }
    
    public static func updateCirclesInclusions(postbox: Postbox) -> Signal<Void, NoError> {
        return Circles.getSettings(postbox: postbox) |> mapToSignal { settings in
            return postbox.transaction { transaction in
                for (peer, group) in settings.inclusions {
                    if let localPeer = transaction.getPeer(peer) {
                        let currentInclusion = transaction.getPeerChatListInclusion(peer)
                        switch currentInclusion {
                        case .notIncluded:
                            switch localPeer.id.namespace {
                            case Namespaces.Peer.CloudGroup:
                                if let chat = localPeer as? TelegramGroup {
                                    if chat.flags.contains(.deactivated) {
                                        print("group is deactivated, so it wasnt added to circle:")
                                        print(peer)
                                    } else {
                                        switch chat.membership {
                                            case .Member:
                                                transaction.updatePeerChatListInclusion(
                                                    localPeer.id,
                                                    inclusion: .ifHasMessagesOrOneOf(
                                                        groupId: group,
                                                        pinningIndex: nil,
                                                        minTimestamp: 0
                                                    )
                                                )
                                            default:
                                                print("user isnt group member, so group wasnt added to circle:")
                                                print(peer)
                                        }
                                    }
                                }
                            case Namespaces.Peer.CloudChannel:
                                if let channel = localPeer as? TelegramChannel {
                                    switch channel.participationStatus {
                                        case .member:
                                            transaction.updatePeerChatListInclusion(
                                                localPeer.id,
                                                inclusion: .ifHasMessagesOrOneOf(
                                                    groupId: group,
                                                    pinningIndex: nil,
                                                    minTimestamp: 0
                                                )
                                            )
                                        default:
                                            print("user isnt group member, so group wasnt added to circle:")
                                            print(peer)
                                    }
                                }
                            case Namespaces.Peer.CloudUser:
                                if transaction.getTopPeerMessageId(peerId: localPeer.id, namespace: Namespaces.Message.Cloud) != nil {
                                    transaction.updatePeerChatListInclusion(
                                        localPeer.id,
                                        inclusion: .ifHasMessagesOrOneOf(
                                            groupId: group,
                                            pinningIndex: nil,
                                            minTimestamp: 0
                                        )
                                    )
                                }
                                
                            default:
                                transaction.updatePeerChatListInclusion(
                                    localPeer.id,
                                    inclusion: .ifHasMessagesOrOneOf(
                                        groupId: group,
                                        pinningIndex: nil,
                                        minTimestamp: 0
                                    )
                                )
                            }
                        default:
                            transaction.updatePeerChatListInclusion(
                                localPeer.id,
                                inclusion: .ifHasMessagesOrOneOf(
                                    groupId: group,
                                    pinningIndex: nil,
                                    minTimestamp: 0
                                )
                            )
                        }
                    }
                }
            } |> mapToSignal {
                return postbox.transaction { transaction in
                    for group in settings.groupNames.keys {
                        transaction.recalculateChatListGroupStats(groupId: group)
                    }
                    transaction.recalculateChatListGroupStats(groupId: .root)
                }
            }
        }
    }
    
    public static func requestToken(postbox: Postbox, account: Account) -> Signal<Void, NoError> {
        return Circles.getSettings(postbox: postbox) |> mapToSignal { settings in
            var peerSignal:Signal<PeerId?, NoError>
            if let botId = settings.botPeerId {
                peerSignal = .single(botId)
            } else {
                peerSignal = resolvePeerByName(account: account, name: settings.botName)
                |> mapToSignal { peerId -> Signal<Peer?, NoError> in
                    if let peerId = peerId {
                        return postbox.loadedPeerWithId(peerId) |> map {Optional($0)}
                    } else {
                        return .single(nil)
                    }
                } |> mapToSignal { peer in
                    if let peer = peer {
                        settings.botPeerId = peer.id
                        return Circles.updateSettings(postbox: postbox) { entry in
                            let newValue = Circles.defaultConfig
                            newValue.dev = entry.dev
                            newValue.botPeerId = peer.id
                            return newValue
                        } |> map { peer.id }
                    } else {
                        return .single(nil)
                    }
                }
            }
            
            return peerSignal |> mapToSignal { peerId in
                if let peerId = peerId {
                    return standaloneSendMessage(account: account, peerId: peerId, text: "/start api", attributes: [], media: nil, replyToMessageId: nil) |> `catch` {_ in return .complete()} |> map {_ in return Void()}
                } else {
                    return .single(Void())
                }
            }
        }
    }
    
    public static func updateCircles(postbox: Postbox, network: Network, accountPeerId: PeerId) -> Signal<Void, NoError> {
        return Circles.fetch(postbox: postbox, userId: accountPeerId) |> mapToSignal {
            return Circles.updateCirclesInclusions(postbox: postbox)
        } |> mapToSignal {
            return Circles.sendMembers(postbox: postbox, network: network, userId: accountPeerId)
        } |> mapToSignal {
            return Circles.updateCirclesInclusions(postbox: postbox)
        }
    }
    
    public static func collectGroupPeers(postbox: Postbox, network: Network, peerId: PeerId) -> Signal<(PeerId,[PeerId]), NoError> {
        return network.request(Api.functions.messages.getFullChat(chatId: peerId.id))
        |> retryRequest
        |> map { result in
            switch result {
            case let .chatFull(chatFull, chats, users):
                return (peerId, users.map { TelegramUser(user: $0).id })
            }
        } |> `catch` { error in
            return .single((peerId, []))
        }
    }
    
    public static func getApiUserInfo(postbox: Postbox, peerId: PeerId) -> Signal<ApiUserInfo?, NoError> {
        return postbox.transaction { transaction in
            return transaction.getPeer(peerId)
        } |> map { peer in
            if let peer = peer as? TelegramUser {
                let image = peer.smallProfileImage
                if let image = image {
                    let dimensions = image.dimensions
                    let data = image.resource
                }
                return ApiUserInfo(id: peerId.botApiId, username: peer.username, firstname: peer.firstName, lastname: peer.lastName, avatar: nil)
            } else {
                return nil
            }
        }
    }
    
    public static func sendCircleInclusionData(postbox: Postbox, data: Data) -> Signal<Void, NoError> {
        return Circles.getSettings(postbox: postbox)
        |> mapToSignal { settings in
            if let token = settings.token {
                return Signal<Void, NoError> { subscriber in
                    let jsonString = String(data: data, encoding: .utf8)!
                    
                    let urlString = settings.url+"tgfork/connection"
                    let url = URL(string: urlString)!
                    var request = URLRequest(url: url)
                    request.setValue(token, forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpMethod = "POST"
                    request.httpBody = data
                    
                    let task = URLSession.shared.dataTask(with: request) { data, response, error in
                        guard let data = data,
                            let response = response as? HTTPURLResponse,
                            error == nil else {
                                subscriber.putNext(Void())
                                subscriber.putCompletion()
                                return
                        }
                        guard (200 ... 299) ~= response.statusCode else {
                            subscriber.putNext(Void())
                            subscriber.putCompletion()
                            return
                        }
                        subscriber.putNext(Void())
                        subscriber.putCompletion()
                    }
                    task.resume()
                    subscriber.putNext(Void())
                    subscriber.putCompletion()
                    return EmptyDisposable
                }
            } else {
                return .single(Void())
            }
        }
    }
    
    static func getChatApiData(postbox: Postbox, network: Network, peerId: PeerId) -> Signal<ApiChatInfo?, NoError> {
        return postbox.transaction { transaction in
            return transaction.getPeer(peerId)
        } |> mapToSignal { peer in
            if let peer = peer {
                var title: String?
                var id = peerId.botApiId
                
                var participantSignal: Signal<[PeerId], NoError>
                
                if let group = peer as? TelegramGroup {
                    title = group.title
                    participantSignal = Circles.collectGroupPeers(postbox: postbox, network: network, peerId: peerId)
                    |> map { info in
                        let (_, members) = info
                        return members
                    }
                } else if let channel = peer as? TelegramChannel {
                    title = channel.title
                    participantSignal = Circles.collectChannelPeers(postbox: postbox, network: network, peerId: peerId)
                    |> map { info in
                        let (_, members) = info
                        return members
                    }
                } else {
                    participantSignal = .single([])
                }
                
                
                return participantSignal
                |> mapToSignal { members in
                    return combineLatest(members.map({ Circles.getApiUserInfo(postbox: postbox, peerId: $0) }))
                    |> map { participantsInfo in
                        return ApiChatInfo(
                            id: id,
                            title: title,
                            users: participantsInfo.compactMap { $0 }
                        )
                    }
                }
            } else {
                return .single(nil)
            }
        }
    }
    
    public static func addToCircle(postbox: Postbox, network: Network, peerId: PeerId, groupId: PeerGroupId, userId: PeerId) -> Signal<Void, NoError> {
        if peerId.namespace == Namespaces.Peer.CloudUser {
            return Circles.getApiUserInfo(postbox: postbox, peerId: peerId)
            |> mapToSignal { info in
                if let info = info {
                    let data = try! JSONEncoder().encode(CircleUserApiData(
                        circle: groupId.rawValue,
                        user: info
                    ))
                    return sendCircleInclusionData(postbox: postbox, data: data)
                    |> mapToSignal {
                        return Circles.updateSettings(postbox: postbox) { entry in
                            entry.remoteInclusions[peerId] = groupId
                            return entry
                        }
                    } |> mapToSignal {
                        return Circles.updateCirclesInclusions(postbox: postbox)
                    }
                } else {
                    return .single(Void())
                }
            }
        } else if peerId.namespace == Namespaces.Peer.CloudChannel || peerId.namespace == Namespaces.Peer.CloudGroup {
            return Circles.getChatApiData(postbox: postbox, network: network, peerId: peerId)
            |> mapToSignal { info in
                if let info = info {
                    let data = try! JSONEncoder().encode(CircleChatApiData(
                        circle: groupId.rawValue,
                        chat: info
                    ))
                    return sendCircleInclusionData(postbox: postbox, data: data)
                    |> mapToSignal {
                        return Circles.updateSettings(postbox: postbox) { entry in
                            entry.remoteInclusions[peerId] = groupId
                            for member in info.users {
                                let pId = parseBotApiPeerId(member.id)
                                if pId != userId {
                                    entry.remoteInclusions[pId] = groupId
                                }
                            }
                            return entry
                        }
                    } |> mapToSignal {
                        return Circles.updateCirclesInclusions(postbox: postbox)
                    }
                } else {
                    return .single(Void())
                }
            }
        }
        return .single(Void())
    }
    
    public static func collectChannelPeers(postbox: Postbox, network: Network, peerId: PeerId) -> Signal<(PeerId,[PeerId]), NoError> {
        switch peerId.namespace {
        case Namespaces.Peer.CloudChannel:
            return postbox.transaction { transaction -> Api.InputChannel? in
                if let peer = transaction.getPeer(peerId), let channel = apiInputChannel(peer) {
                    return channel
                } else {
                    return nil
                }
            } |> mapToSignal { channel in
                if let channel = channel {
                    return network.request(Api.functions.channels.getParticipants(channel: channel, filter: .channelParticipantsRecent, offset: 0, limit: 0, hash: 0))
                    |> map { result -> (PeerId,[PeerId]) in
                        switch result {
                        case let .channelParticipants(_, _, users):
                            return (peerId, users.map { TelegramUser(user: $0).id })
                        case .channelParticipantsNotModified:
                            return (peerId, [])
                        }
                    } |> `catch` { error in
                        return .single((peerId, []))
                    }
                } else {
                    return .single((peerId, []))
                }
            }
        default:
            break
        }
        return .single((peerId, []))
    }
    
    public static func collectCirclePeers(postbox: Postbox, network: Network, circleId: PeerGroupId, members: [PeerId]) -> Signal<(PeerGroupId, [PeerId:[PeerId]]), NoError> {
        let chats = members.filter { $0.namespace == Namespaces.Peer.CloudGroup }
        let channels = members.filter { $0.namespace == Namespaces.Peer.CloudChannel }
        
        let chatSignals:[Signal<(PeerId,[PeerId]), NoError>] = chats.map { collectGroupPeers(postbox: postbox, network: network, peerId: $0) }
        let channelSignals:[Signal<(PeerId,[PeerId]), NoError>] = channels.map { collectChannelPeers(postbox: postbox, network: network, peerId: $0) }
        return combineLatest(queue: Queue(), chatSignals + channelSignals)
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
                        
                        let urlString = settings.url+"tgfork/connections"
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
                    return Circles.updateSettings(postbox: postbox) { entry in
                        let sortedCircles = circles.sorted(by: { lhs, rhs in
                            let li = entry.index[PeerGroupId(rawValue: lhs.circle)] ?? 0
                            let ri = entry.index[PeerGroupId(rawValue: rhs.circle)] ?? 0
                            return li < ri
                        })
                        for circle in sortedCircles {
                            for connection in circle.connections {
                                for peer in connection.members {
                                    let peerId = parseBotApiPeerId(peer)
                                    if peerId != userId && entry.remoteInclusions[peerId] == nil {
                                        entry.remoteInclusions[peerId] = PeerGroupId(rawValue: circle.circle)
                                    }
                                }
                            }
                        }
                        return entry
                    }
                }
            } else {
                return .single(Void())
            }
        }
    }
    
    public static func handleMessages(postbox: Postbox, network: Network, accountPeerId: PeerId, messages: [Api.Message]) -> Signal<Void, NoError> {
        return Circles.getSettings(postbox: postbox)
        |> mapToSignal { settings in
            if let botId = settings.botPeerId {
                for message in messages {
                    if let token = settings.getTokenFromMessage(message: message) {
                        return Circles.updateSettings(postbox: postbox) { entry in
                            entry.token = token
                            return entry
                        } |> mapToSignal {
                            return postbox.transaction { transaction in
                                return transaction.getPeer(botId)
                            }
                        } |> mapToSignal { peer -> Signal<Api.messages.Messages, NoError> in
                            if let peer = peer, let inputPeer = apiInputPeer(peer) {
                                return network.request(Api.functions.messages.getHistory(peer: inputPeer, offsetId: 0, offsetDate: 0, addOffset: 0, limit: 2, maxId: Int32.max, minId: 0, hash: 0)) |> retryRequest
                            } else {
                                return .complete()
                            }
                        } |> mapToSignal {result -> Signal<Void,NoError> in
                            let messages: [Api.Message]
                            var messagesToRemove:[MessageId] = []
                            
                            switch result {
                            case let .messages(apiMessages, _, _):
                                messages = apiMessages
                            case let .channelMessages(_, _, _, apiMessages, _, _):
                                messages = apiMessages
                            case let .messagesSlice(_, _, _, apiMessages, _, _):
                                messages = apiMessages
                            case .messagesNotModified:
                                messages = []
                            }
                            
                            for message in messages {
                                if let storeMessage = StoreMessage(apiMessage: message), case let .Id(messageId) = storeMessage.id {
                                    if storeMessage.text == "/start api" || settings.getTokenFromMessage(message: message) != nil {
                                        messagesToRemove.append(messageId)
                                    }
                                }
                            }
                            return deleteMessagesInteractively(postbox: postbox, messageIds: messagesToRemove, type: .forEveryone, deleteAllInGroup: false)
                        } |> mapToSignal {
                            return Circles.updateCircles(postbox: postbox, network: network, accountPeerId: accountPeerId)
                        }
                    } else if case let .message(_,_,fromId,_,_,_,_,_,_,_,_,_,_,_,_,_,_) = message, fromId == botId.id {
                        return Circles.updateCircles(postbox: postbox, network: network, accountPeerId: accountPeerId)
                    }
                }
            }
            return .single(Void())
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
    public var groupNames: Dictionary<PeerGroupId, String> = [:]
    public var remoteInclusions: Dictionary<PeerId, PeerGroupId> = [:]
    public var dev: Bool
    public var index: Dictionary<PeerGroupId, Int32> = [:]
    public var lastCirclePeer: Dictionary<PeerGroupId, PeerId> = [:]
    public var currentCircle = PeerGroupId(rawValue: 0)
    
    public var botPeerId: PeerId?
    
    public var inclusions: Dictionary<PeerId, PeerGroupId> {
        return self.remoteInclusions
    }
    public var url:String {
        return self.dev ? Circles.baseDevApiUrl : Circles.baseApiUrl
    }
    public var botName:String {
        return self.dev ? Circles.botNameDev : Circles.botName
    }
    public var sortedCircles:[PeerGroupId] {
        return self.groupNames.keys.sorted { lhs, rhs in
            var li:Int32 = 0
            var ri:Int32 = 0
            if let index = self.index[lhs] {
                li = index
            }
            if let index = self.index[rhs] {
                ri = index
            }
            return li < ri
        }
    }
    
    
    public init(dev: Bool = false) {
        self.dev = dev
    }
    
    public init(decoder: PostboxDecoder) {
        self.dev = decoder.decodeBoolForKey("d", orElse: false)
        self.token = decoder.decodeOptionalStringForKey("ct")
        self.botPeerId = PeerId(decoder.decodeInt64ForKey("bpi", orElse: 0))
        
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
        self.remoteInclusions = decoder.decodeObjectDictionaryForKey(
            "ri",
            keyDecoder: {
                PeerId($0.decodeInt64ForKey("k", orElse: 0))
            }
        )
        self.currentCircle = PeerGroupId(rawValue: decoder.decodeInt32ForKey("cc", orElse: 0))
        self.lastCirclePeer = decoder.decodeObjectDictionaryForKey(
            "lcp",
            keyDecoder: {
                PeerGroupId(rawValue: $0.decodeInt32ForKey("k", orElse: 0))
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
        if let botPeerId = self.botPeerId {
            encoder.encodeInt64(botPeerId.toInt64(), forKey: "bpi")
        } else {
            encoder.encodeNil(forKey: "bpi")
        }
        
        encoder.encodeObjectDictionary(self.groupNames , forKey: "gn", keyEncoder: {
            $1.encodeInt32($0.rawValue, forKey: "k")
        })
        encoder.encodeObjectDictionary(self.index , forKey: "i", keyEncoder: {
            $1.encodeInt32($0.rawValue, forKey: "k")
        })
        encoder.encodeObjectDictionary(self.remoteInclusions , forKey: "ri", keyEncoder: {
            $1.encodeInt64($0.toInt64(), forKey: "k")
        })
        
        encoder.encodeInt32(currentCircle.rawValue, forKey: "cc")
        encoder.encodeObjectDictionary(self.lastCirclePeer , forKey: "lcp", keyEncoder: {
            $1.encodeInt32($0.rawValue, forKey: "k")
        })
    }
    
    public func getTokenFromMessage(message: Api.Message) -> String? {
        if let botId = self.botPeerId {
            if case let .message(_,id,fromId,apiPeer,_,viaBotId,replyToMsgId,date,text,_,_,_,_,_,_,_,_) = message {
                if text.range(of: "^[0-9a-zA-Z._-]{100,}$", options: .regularExpression) != nil && fromId == botId.id {
                    return text
                }
            }
        }
        return nil
    }
    
    public static func == (lhs: Circles, rhs: Circles) -> Bool {
        return lhs.token == rhs.token && lhs.dev == rhs.dev && lhs.groupNames == rhs.groupNames && lhs.remoteInclusions == rhs.remoteInclusions && lhs.index == rhs.index && lhs.lastCirclePeer == rhs.lastCirclePeer && lhs.currentCircle == rhs.currentCircle
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
