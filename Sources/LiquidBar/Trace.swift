import AppKit

/// With `LIQUIDBAR_TRACE=<file>` set, appends timestamped hover and expansion events to that file.
private let traceHandle: FileHandle? = ProcessInfo.processInfo.environment["LIQUIDBAR_TRACE"].flatMap { path in
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}

func trace(_ message: @autoclosure () -> String) {
    guard let traceHandle else { return }
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    let pointer = NSEvent.mouseLocation
    let line = String(format: "%.3f p=(%.0f,%.0f) ", Date().timeIntervalSince1970, pointer.x, top - pointer.y) + message() + "\n"
    traceHandle.write(Data(line.utf8))
}
