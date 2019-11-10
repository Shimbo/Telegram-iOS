import Foundation
#if os(macOS)
    import PostboxMac
#else
    import Postbox
#endif

public final class Circles: Equatable, PostboxCoding, PreferencesEntry {
    public static let baseApiUrl = "https://my-json-server.typicode.com/michaelenco/fakeapi/"
    public func isEqual(to: PreferencesEntry) -> Bool {
        if let to = to as? Circles {
            return self == to
        } else {
            return false
        }
    }
    
    public var token: String?
    public let botId: PeerId
    
    public init(botId: PeerId) {
        self.botId = botId
    }
    
    public init(decoder: PostboxDecoder) {
        self.token = decoder.decodeOptionalStringForKey("ct")
        self.botId = PeerId(decoder.decodeInt64ForKey("bi", orElse: 1234))
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        if let token = self.token {
            encoder.encodeString(token, forKey: "ct")
        } else {
            encoder.encodeNil(forKey: "ct")
        }
        encoder.encodeInt64(self.botId.toInt64(), forKey: "bi")
    }
    
    public static func == (lhs: Circles, rhs: Circles) -> Bool {
        return lhs.token == rhs.token
    }
}
