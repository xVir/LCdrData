import Foundation

/// Command-line options used by automated runs and other deterministic launches.
package struct LaunchOptions: Sendable, Equatable {
    package let leftPath: String?
    package let rightPath: String?
    package let noSavedState: Bool

    package var hasPanelOverrides: Bool {
        leftPath != nil || rightPath != nil
    }

    package init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        var leftPath: String?
        var rightPath: String?
        var noSavedState = false
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--no-saved-state":
                noSavedState = true
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
    }
}
