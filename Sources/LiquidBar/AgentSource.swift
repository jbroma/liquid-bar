import Foundation
import LiquidBarCore

/// Keeps `model.agents` in step with T3 Code. T3 writes every change to `state.sqlite-wal`, so the source watches that
/// file (and the directory, for when the WAL is created, checkpointed away or replaced) and re-reads 250ms after the
/// last write. No polling: with T3 Code quiet or not installed, nothing runs.
final class AgentSource {
    let model: BarModel
    private let database: URL
    private var watches: [DispatchSourceFileSystemObject] = []
    private var pending: Task<Void, Never>?
    private var loggedError: String?

    init(model: BarModel, database: URL = T3Store.defaultURL) {
        self.model = model
        self.database = database
        rewatch()
    }

    private func rewatch() {
        watches.forEach { $0.cancel() }
        let wal = URL(fileURLWithPath: database.path + "-wal")
        watches = [wal, database.deletingLastPathComponent()].compactMap(watch)
        reload()
    }

    private func watch(_ url: URL) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let isWAL = url.path.hasSuffix("-wal")
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: isWAL ? [.write, .extend, .rename, .delete] : [.write], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            let events = source?.data ?? []
            MainActor.assumeIsolated {
                // The directory changes when the WAL comes or goes; either way the file watch must be re-armed.
                if !isWAL || !events.isDisjoint(with: [.rename, .delete]) { self?.rewatchSoon() } else { self?.reloadSoon() }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func reloadSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    private func rewatchSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            rewatch()
        }
    }

    private func reload() {
        let database = database
        Task {
            let result = await Task.detached { Result { try T3Store.threads(at: database) } }.value
            switch result {
            case .success(let threads):
                loggedError = nil
                model.receive(threads)
            case .failure(let error):
                // A missing database just means T3 Code is not installed; a schema change is worth one line in the log.
                if "\(error)" != loggedError, FileManager.default.fileExists(atPath: database.path) {
                    FileHandle.standardError.write(Data("liquid-bar: T3 Code unavailable: \(error)\n".utf8))
                }
                loggedError = "\(error)"
                model.receive([])
            }
        }
    }
}

/// `liquid-bar agents [db]`: prints what the bar reads from T3 Code, one thread per line, for checking against sqlite3.
func printAgents(_ path: String?) -> Int32 {
    do {
        let threads = try T3Store.threads(at: path.map(URL.init(fileURLWithPath:)) ?? T3Store.defaultURL)
        for thread in threads {
            let fields = [thread.id, thread.project, thread.title, thread.provider.displayName, "\(thread.status)",
                          thread.turn.map { "\($0)" } ?? "-", thread.updatedAt.formatted(.iso8601)]
            print(fields.joined(separator: "\t"))
        }
        return 0
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        return 1
    }
}
