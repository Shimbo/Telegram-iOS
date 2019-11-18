import Foundation
#if os(macOS)
    import PostboxMac
#else
    import Postbox
#endif

extension String: PostboxCoding {
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self, forKey: "s")
    }
    public init(decoder: PostboxDecoder) {
        self = decoder.decodeStringForKey("s", orElse: "")
    }
}

extension PeerGroupId: PostboxCoding {
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.rawValue, forKey: "i")
    }
    public init(decoder: PostboxDecoder) {
        self = .group(decoder.decodeInt32ForKey("i", orElse: 0))
    }
}

public final class Circles: Equatable, PostboxCoding, PreferencesEntry {
    public static let baseApiUrl = "https://api.dev.randomcoffee.us/"
    public func isEqual(to: PreferencesEntry) -> Bool {
        if let to = to as? Circles {
            return self == to
        } else {
            return false
        }
    }
    
    public var token: String?
    public let botId: PeerId
    public var groupNames: Dictionary<PeerGroupId, String> = [:]
    
    
    public init(botId: PeerId) {
        self.botId = botId
    }
    
    public init(decoder: PostboxDecoder) {
        self.token = decoder.decodeOptionalStringForKey("ct")
        self.botId = PeerId(decoder.decodeInt64ForKey("bi", orElse: 1234))
        
        self.groupNames = decoder.decodeObjectDictionaryForKey(
            "gn",
            keyDecoder: {
                PeerGroupId(rawValue: $0.decodeInt32ForKey("k", orElse: 0))    
            }
        )
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        if let token = self.token {
            encoder.encodeString(token, forKey: "ct")
        } else {
            encoder.encodeNil(forKey: "ct")
        }
        encoder.encodeInt64(self.botId.toInt64(), forKey: "bi")
        encoder.encodeObjectDictionary(self.groupNames , forKey: "gn", keyEncoder: {
            $1.encodeInt32($0.rawValue, forKey: "k")
        })
    }
    
    public static func == (lhs: Circles, rhs: Circles) -> Bool {
        return lhs.token == rhs.token
    }
}
