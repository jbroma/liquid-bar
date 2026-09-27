import Foundation
import LiquidBarCore
import Testing

@Test func runReturnsStdoutOrNilOnFailure() async {
    #expect(await run(["/bin/sh", "-c", "echo hi; echo there"]) == "hi\nthere\n")
    #expect(await run(["/bin/sh", "-c", "echo partial; exit 3"]) == nil)
    #expect(await run(["no-such-command-liquid-bar"]) == nil)
}

@Test func runTerminatesACommandThatOutlivesItsTimeout() async {
    let start = Date()
    #expect(await run(["sleep", "30"], timeout: 0.3) == nil)
    #expect(Date().timeIntervalSince(start) < 2)
}

@Test func aBackgroundJobHoldingStdoutDoesNotHoldTheRun() async {
    let start = Date()
    #expect(await run(["/bin/sh", "-c", "echo done; sleep 30 &"]) == "done\n")
    #expect(Date().timeIntervalSince(start) < 2)
}

@Test func cancellingTheCallerTerminatesTheCommand() async {
    let start = Date()
    let task = Task { await run(["sleep", "30"]) }
    try? await Task.sleep(for: .milliseconds(200))
    task.cancel()
    #expect(await task.value == nil)
    #expect(Date().timeIntervalSince(start) < 2)
}

@Test func largeOutputArrivesWhole() async {
    #expect(await run(["/bin/sh", "-c", "head -c 300000 /dev/zero | tr '\\\\0' a"])?.count == 300_000)
}
