import Foundation
#if os(macOS)
    import PostboxMac
#else
    import Postbox
#endif

public final class Circles: Equatable, PostboxCoding, PreferencesEntry {
    public func isEqual(to: PreferencesEntry) -> Bool {
        if let to = to as? Circles {
            return self == to
        } else {
            return false
        }
    }
    
    public let token: String?
    
    public init(token: String?) {
        self.token = token
    }
    
    public init(decoder: PostboxDecoder) {
        self.token = decoder.decodeOptionalStringForKey("circles_token")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        if let token = self.token {
            encoder.encodeString(token, forKey: "circles_token")
        } else {
            encoder.encodeNil(forKey: "circles_token")
        }
    }
    
    public static func == (lhs: Circles, rhs: Circles) -> Bool {
        return lhs.token == rhs.token
    }
}
