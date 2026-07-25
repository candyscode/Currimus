import Foundation

/// A one-shot async wait that resolves on the first of: an explicit `signal()`,
/// or a fallback timeout — and resumes its awaiter exactly once, ever.
///
/// This is the shape of `RunSession`'s location-permission wait, pulled out so
/// the part that actually broke can be unit-tested without a `CLLocationManager`:
/// "resume the moment the runner answers, fall back on a timeout if the prompt
/// never appears, and never hang and never resume twice." The bug it guards
/// against is a run start that answers the prompt yet stalls on "Checking
/// Health…" because nothing resumed the wait.
@MainActor
final class PromptGate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var resolved = false

    /// Suspends until `signal()` fires or `timeout` elapses, whichever is first.
    /// `onStart` runs once the awaiter is parked — present the prompt there, so
    /// an answer that arrives immediately can't be missed.
    func wait(timeout: Duration, onStart: () -> Void = {}) async {
        let fallback = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            self?.signal()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if resolved {
                continuation.resume()          // already signalled before we parked
            } else {
                waiter = continuation
                onStart()
            }
        }
        fallback.cancel()
    }

    /// Resolves the wait. Idempotent: the second and any later call does
    /// nothing, so the answer and the timeout racing can never double-resume a
    /// checked continuation (which would trap).
    func signal() {
        guard !resolved else { return }
        resolved = true
        if let waiter {
            self.waiter = nil
            waiter.resume()
        }
    }
}
