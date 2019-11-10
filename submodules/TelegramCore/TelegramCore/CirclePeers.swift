import Foundation
import Alamofire
import SwiftyJSON

#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
#else
    import Postbox
    import SwiftSignalKit
#endif

func fetchCircles(postbox: Postbox) -> Signal<Void, NoError> {
    return getCirclesSettings(postbox: postbox)
    |> mapToSignal { settings -> Signal<[PeerGroupId: [PeerId]],NoError> in
        if let token = settings?.token {
            return Signal<[PeerGroupId: [PeerId]], NoError> { subscriber in
                
                let urlString = Circles.baseApiUrl+"circles"
                Alamofire.request(urlString).responseJSON { response in
                    if let result = response.result.value {
                        let json = SwiftyJSON.JSON(result)
                        if let firstCircle = json["circles"].arrayValue.first {
                            let peerIds = firstCircle["peers"].arrayValue
                            let peers = (peerIds.map() { PeerId($0.int64Value)})
                            subscriber.putNext([PeerGroupId(rawValue: firstCircle["id"].int32Value) : peers])
                        }
                        
                    }
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        } else {
            return .single([:])
        }
    }
    |> mapToSignal {dict -> Signal<Void, NoError> in
        return postbox.transaction { transaction in
            for group in dict.keys {
                for peer in dict[group]! {
                    transaction.updatePeerChatListInclusion(peer, inclusion: .ifHasMessagesOrOneOf(groupId: group, pinningIndex: nil, minTimestamp: nil))
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
        let urlString = Circles.baseApiUrl+"token"
        Alamofire.request(
            urlString,
            method: .post,
            parameters: ["id": id.id, "token": requestToken],
            encoding: JSONEncoding.default,
            headers: nil
        ).responseJSON { response in
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
    return Signal<PeerId, NoError> { subscriber in
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
    }
}

