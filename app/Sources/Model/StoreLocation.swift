import Foundation

/// Where Oatmeal keeps its database: ~/Library/Application Support/Oatmeal/Oatmeal.store.
///
/// Never SwiftData's default (~/Library/Application Support/default.store): that path is shared by
/// every unsandboxed app that doesn't pick its own, and another app can replace the file.
enum StoreLocation {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Oatmeal", isDirectory: true)
    }
    static var url: URL { folder.appendingPathComponent("Oatmeal.store") }

    static func prepare() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}
