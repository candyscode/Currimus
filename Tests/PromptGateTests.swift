import XCTest

/// The location-prompt wait, tested without a CLLocationManager.
///
/// The watch app once stalled on "Checking Health…" because the run start
/// awaited a continuation that the answer never resumed — only a 10 s timeout
/// did, and when the app was suspended, not even that. `PromptGate` is the
/// extracted resume-or-timeout logic; these guard the two failure modes it can
/// have: never resuming (a hang) and resuming twice (a checked-continuation
/// trap).
@MainActor
final class PromptGateTests: XCTestCase {

    /// The answer resolves the wait immediately, not at the timeout — the exact
    /// behaviour whose absence caused the stall.
    func testSignalResolvesImmediatelyNotAtTimeout() async {
        let gate = PromptGate()
        Task { @MainActor in gate.signal() }
        let start = Date()
        await gate.wait(timeout: .seconds(30))   // would hang 30 s if the signal were ignored
        XCTAssertLessThan(Date().timeIntervalSince(start), 1, "the wait did not resume on the answer")
    }

    /// With nothing to answer, the fallback still resolves the wait — it never
    /// hangs forever.
    func testTimeoutResolvesWhenNothingSignals() async {
        let gate = PromptGate()
        let start = Date()
        await gate.wait(timeout: .milliseconds(80))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(elapsed, 0.05, "resolved before the timeout could have elapsed")
        XCTAssertLessThan(elapsed, 3, "the fallback timeout did not fire")
    }

    /// The answer and the timeout can race; the second resolve must be a no-op,
    /// not a double-resume of the continuation (which traps).
    func testDoubleSignalIsSafe() async {
        let gate = PromptGate()
        Task { @MainActor in gate.signal(); gate.signal() }
        await gate.wait(timeout: .seconds(30))
        gate.signal()   // and again after it has already resolved
    }

    /// An answer that arrives before the wait even parks is still honoured.
    func testSignalBeforeWaitDoesNotHang() async {
        let gate = PromptGate()
        gate.signal()
        await gate.wait(timeout: .seconds(30))   // already resolved → returns at once
    }
}
