import Foundation
#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
#else
    import Postbox
    import SwiftSignalKit
#endif

func fetchCirclePeers(postbox: Postbox) -> Signal<Void, NoError> {
    return getCirclesToken(postbox: postbox)
    |> mapToSignal { token -> Signal<[PeerId],NoError> in
        return Signal<[PeerId], NoError> { subscriber in
            subscriber.putNext([PeerId(137145876)])
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
    |> mapToSignal {peers -> Signal<Void, NoError> in
        return postbox.transaction { transaction in
            for id in peers {
                transaction.updatePeerChatListInclusion(id, inclusion: .ifHasMessagesOrOneOf(groupId: Namespaces.PeerGroup.circles, pinningIndex: nil, minTimestamp: nil))
            }
        }
    }
}

public func getCirclesToken(postbox: Postbox) -> Signal<String?, NoError> {
    return postbox.transaction { transaction -> String? in
        var token:String?
        if let circles = transaction.getPreferencesEntry(key: PreferencesKeys.circles) as? Circles {
            token = circles.token
        }
        return token
    }
}

public func setCirclesToken(token: String?, postbox: Postbox) -> Signal<Void, NoError> {
    postbox.transaction { transaction in
        return transaction.setPreferencesEntry(key: PreferencesKeys.circles, value: Circles(token: token))
    } |> mapToSignal {
        return fetchCirclePeers(postbox: postbox)
    }
}


