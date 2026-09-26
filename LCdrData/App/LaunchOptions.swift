import Foundation

/// Command-line options used by automated runs and other deterministic launches.
package struct LaunchOptions: Sendable, Equatable {
    package let leftPath: String?
    package let rightPath: String?
    package let noSavedState: Bool
    /// UI tests pass this so a multi-file copy stays running long enough to watch.
    package let operationItemDelayMilliseconds: Int?
    /// Overrides `operations.max-active` for a launch. UI tests use it to fill the allowance with two copies.
    package let operationMaxActive: Int?

    package var hasPanelOverrides: Bool {
        leftPath != nil || rightPath != nil
    }

    package init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        var leftPath: String?
        var rightPath: String?
        var noSavedState = false
        var operationItemDelayMilliseconds: Int?
        var operationMaxActive: Int?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--no-saved-state":
                noSavedState = true
            case "--operation-item-delay-ms":
                if let value = Self.integerArgument(in: arguments, at: index) {
                    operationItemDelayMilliseconds = value
                    index += 1
                }
            case "--operation-max-active":
                if let value = Self.integerArgument(in: arguments, at: index), value >= 1 {
                    operationMaxActive = value
                    index += 1
                }
            case "--left", "--right":
                guard index + 1 < arguments.count else {
                    index += 1
                    continue
                }
                let path = arguments[index + 1]
                guard !path.hasPrefix("--") else {
                    index += 1
                    continue
                }
                if arguments[index] == "--left" {
                    leftPath = path
                } else {
                    rightPath = path
                }
                index += 1
            default:
                break
            }
            index += 1
        }

        self.leftPath = leftPath
        self.rightPath = rightPath
        self.noSavedState = noSavedState
        self.operationItemDelayMilliseconds = operationItemDelayMilliseconds
        self.operationMaxActive = operationMaxActive
    }

    private static func integerArgument(in arguments: [String], at index: Int) -> Int? {
        guard index + 1 < arguments.count else { return nil }
        let raw = arguments[index + 1]
        guard !raw.hasPrefix("--") else { return nil }
        return Int(raw)
    }
}
