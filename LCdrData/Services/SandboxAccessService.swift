//
//  SandboxAccessService.swift
//  LCdrData
//
//  Created by Dima Skachkov on 02.04.2026.
//

import AppKit
import Foundation

/// Manages sandbox file-access permissions by presenting an NSOpenPanel when
/// the app lacks access to a directory, and tracking which URLs the user has
/// already granted access to during the current session.
@Observable
final class SandboxAccessService {

    /// URLs the user has granted access to during this session.
    private(set) var grantedURLs: Set<URL> = []

    /// Presents an NSOpenPanel pre-navigated to the requested directory so the
    /// user can grant access. Returns the selected URL on success, or nil if
    /// the user cancels.
    ///
    /// - Parameter directoryURL: The directory the app wants to access.
    /// - Returns: The URL the user selected (granting sandbox access), or nil.
    @MainActor
    func requestAccess(to directoryURL: URL) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Grant Access to Folder"
        panel.message = "LCdrData needs permission to access \"\(directoryURL.lastPathComponent)\". "
            + "Select the folder to grant access."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = directoryURL

        let response = await panel.begin()

        guard response == .OK, let selectedURL = panel.url else {
            return nil
        }

        grantedURLs.insert(selectedURL)
        return selectedURL
    }

    /// Checks whether a given POSIX error indicates a sandbox permission denial.
    nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // POSIX permission denied
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 1 { // EPERM
            return true
        }

        // Cocoa file read/write permission errors
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case 257: // NSFileReadNoPermissionError
                return true
            case 513: // NSFileWriteNoPermissionError
                return true
            default:
                break
            }
        }

        // Check underlying error
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isPermissionError(underlying)
        }

        return false
    }
}
