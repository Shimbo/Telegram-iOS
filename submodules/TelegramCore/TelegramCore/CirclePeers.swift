import Foundation
import Alamofire
import SwiftyJSON

#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
    import TelegramApiMac
#else
    import Postbox
    import SwiftSignalKit
    import TelegramApi
#endif

struct ApiCircle {
    let id: PeerGroupId
    let name: String
    var peers: [PeerId]
}

func fetchCircles(postbox: Postbox, userId: PeerId) -> Signal<[ApiCircle], NoError> {
    return getCirclesSettings(postbox: postbox)
    |> mapToSignal { settings -> Signal<[ApiCircle],NoError> in
        if let token = settings?.token {
            return Signal<[ApiCircle], NoError> { subscriber in
                let urlString = Circles.baseApiUrl
                Alamofire.request(
                    urlString,
                    headers: ["Authorization": token]
                ).responseJSON { response in
                    if let result = response.result.value {
                        let json = SwiftyJSON.JSON(result)
                        var circles:[ApiCircle] = json["circles"].arrayValue.map { circle in
                            let idArray = circle["peers"].arrayValue + circle["members"].arrayValue
                            let peers:[PeerId] = idArray
                            .map { parseBotApiPeerId($0.int64Value) }
                            .filter { $0 != userId }

                            return ApiCircle(
                                id: PeerGroupId(rawValue: circle["id"].int32Value),
                                name: circle["name"].stringValue,
                                peers: peers
                            )
                        }
                        
                        removePeerDuplicates(&circles)
                        for c1 in circles.sorted(by: { $0.id.rawValue < $1.id.rawValue}) {
                            for p1 in c1.peers {
                                for var c2 in circles {
                                    if c1.id != c2.id {
                                        if let idx = c2.peers.firstIndex(of: p1) {
                                            c2.peers.remove(at: idx)
                                        }
                                    }
                                }
                            }
                        }
                        subscriber.putNext(circles)
                    }
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        } else {
            return .single([])
        }
    } |> mapToSignal { circles in
        return updateCirclesSettings(postbox: postbox) { s in
            for c in circles {
                s?.groupNames[c.id] = c.name
            }
            return s
        } |> map { circles }
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

func removePeerDuplicates(_ circles: inout [ApiCircle]) {
    for c1 in circles.sorted(by: { $0.id.rawValue < $1.id.rawValue}) {
        for p1 in c1.peers {
            for var c2 in circles {
                if c1.id != c2.id {
                    if let idx = c2.peers.firstIndex(of: p1) {
                        c2.peers.remove(at: idx)
                    }
                }
            }
        }
    }
}

func updatePeerCirclesInclusion(postbox: Postbox, circles: [ApiCircle]) -> Signal<Void, NoError> {
    return postbox.transaction { transaction in
        for c in circles {
            for peer in c.peers {
                transaction.updatePeerChatListInclusion(peer, inclusion: .ifHasMessagesOrOneOf(groupId: c.id, pinningIndex: nil, minTimestamp: nil))
            }
        }
    } |> mapToSignal {
        return getCirclesSettings(postbox: postbox)
    } |> mapToSignal { settings -> Signal<Void, NoError> in
        if let settings = settings {
            return postbox.transaction { transaction in
                for p in settings.localInclusions.keys {
                    transaction.updatePeerChatListInclusion(
                        p,
                        inclusion: .ifHasMessagesOrOneOf(
                            groupId: settings.localInclusions[p]!,
                            pinningIndex: nil,
                            minTimestamp: nil
                        )
                    )
                }
            }
        } else {
            return .never()
        }
    }
}

func compromiseContacts(postbox: Postbox, network: Network, circles: [ApiCircle]) -> Signal<Void, NoError> {
    
    var signals:[Signal<(PeerGroupId, [PeerId])?, NoError>] = []
    for circle in circles{
        for peerId in circle.peers {
            switch peerId.namespace {
            case Namespaces.Peer.CloudGroup:
                let signal:Signal<(PeerGroupId, [PeerId])?, NoError> = network.request(Api.functions.messages.getFullChat(chatId: peerId.id))
                |> retryRequest
                |> map { result in
                    switch result {
                    case let .chatFull(_, _, users):
                        return (circle.id, users.map { (TelegramUser(user: $0)).id })
                    }
                }
                signals.append(signal)
            default: break
            }
        }
    }
    
    return combineLatest(queue: Queue(), signals)
    |> map { results -> [(PeerGroupId, [PeerId])] in
        return results.compactMap { $0 }
    } |> mapToSignal { results -> Signal<Void,NoError> in
        var result:[PeerGroupId:[PeerId]] = [:]
        for (circleId, peers) in results {
            if result[circleId] != nil {
                result[circleId]! += peers
            } else {
                result[circleId] = peers
            }
        }
        
        return postbox.transaction { transaction in
            for circleId in result.keys {
                for peerId in result[circleId]! {
                    transaction.updatePeerChatListInclusion(
                        peerId,
                        inclusion: .ifHasMessagesOrOneOf(
                            groupId: circleId,
                            pinningIndex: nil,
                            minTimestamp: nil
                        )
                    )
                }
            }
        }
    }
}

public func getCirclesSettings(postbox: Postbox) -> Signal<Circles?, NoError> {
    return postbox.transaction { transaction -> Circles? in
        return transaction.getPreferencesEntry(key: PreferencesKeys.circles) as? Circles
    }
}

public func updateCirclesSettings(postbox: Postbox, _ f: @escaping(Circles?) -> Circles?) -> Signal<Void, NoError> {
    postbox.transaction { transaction in
        return transaction.updatePreferencesEntry(key: PreferencesKeys.circles) { entry in
            return f(entry as? Circles)
        }
    }
}

public func fetchCirclesToken(id: PeerId, requestToken: String = "") -> Signal<String?, NoError> {
    return Signal<String?, NoError> { subscriber in
        let urlString = Circles.baseApiUrl+"login/"+String(id.id)
        Alamofire.request(urlString).responseJSON { response in
            if let result = response.result.value {
                let json = SwiftyJSON.JSON(result)
                subscriber.putNext(json["token"].stringValue)
            }
            subscriber.putCompletion()
        }
        return EmptyDisposable
    }
}

public func fetchBotId() -> Signal<PeerId, NoError> {
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
    return .single(PeerId(871013339))
}
