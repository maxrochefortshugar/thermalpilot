import Foundation

public struct FanCapability: Equatable, Sendable {
    public let model: String

    public init(model: String) {
        self.model = model
    }
}
