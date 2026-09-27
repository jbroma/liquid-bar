import Foundation

/// A command resolved through PATH, with stderr discarded.
public func makeProcess(_ args: [String]) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    process.standardError = FileHandle.nullDevice
    return process
}

/// Runs a command and returns its stdout, or nil when it fails. Waiting holds no thread. A command still running after
/// `timeout` seconds, or when the calling task is cancelled, is terminated and returns nil.
public func run(_ args: [String], timeout: TimeInterval = 10) async -> String? {
    await ChildProcess(makeProcess(args)).run(timeout: timeout)
}

/// One run of a command. Its stdout arrives through a readability handler and its exit through a termination handler,
/// so no thread blocks on it; whichever of exit, timeout or cancellation comes first ends the run, once.
private final class ChildProcess: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var output = Data()
    private var exited = false
    private var closed = false
    private var done = false
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ process: Process) {
        self.process = process
    }

    func run(timeout: TimeInterval) async -> String? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let started = lock.withLock {
                    if done { return false }
                    self.continuation = continuation
                    return true
                }
                guard started else { return continuation.resume(returning: nil) }
                let out = Pipe()
                process.standardOutput = out
                out.fileHandleForReading.readabilityHandler = { [self] handle in
                    let chunk = handle.availableData
                    lock.withLock {
                        if chunk.isEmpty { closed = true } else { output.append(chunk) }
                    }
                    if chunk.isEmpty { handle.readabilityHandler = nil }
                    finishIfComplete()
                }
                process.terminationHandler = { [self] _ in
                    lock.withLock { exited = true }
                    finishIfComplete()
                    // A job the command left in the background can hold stdout open; take what arrived by then.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in finish(force: true) }
                }
                do { try process.run() } catch { return abort() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in abort() }
            }
        } onCancel: {
            abort()
        }
    }

    private func finishIfComplete() {
        finish(force: false)
    }

    private func finish(force: Bool) {
        let result: (CheckedContinuation<String?, Never>, String?)? = lock.withLock {
            guard let continuation, exited, closed || force else { return nil }
            self.continuation = nil
            done = true
            return (continuation, process.terminationStatus == 0 ? String(decoding: output, as: UTF8.self) : nil)
        }
        result.map { $0.resume(returning: $1) }
    }

    private func abort() {
        let continuation: CheckedContinuation<String?, Never>? = lock.withLock {
            defer { self.continuation = nil; done = true }
            return self.continuation
        }
        if process.isRunning { process.terminate() }
        continuation?.resume(returning: nil)
    }
}
