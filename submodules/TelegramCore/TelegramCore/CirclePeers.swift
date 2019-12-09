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







/*func sendContacts(postbox: Postbox, network: Network, circles: [ApiCircle]) -> Signal<Void, NoError> {
    
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
}*/



