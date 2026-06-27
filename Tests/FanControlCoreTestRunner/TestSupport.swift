import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() {
        throw TestFailure(description: message)
    }
}

func repoRootFromThisFile() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    while url.lastPathComponent != "mlx-chill" && url.path != "/" {
        url.deleteLastPathComponent()
    }
    return url
}
