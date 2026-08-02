import Foundation
#if os(watchOS) || os(iOS)
import CoreMotion
#endif

/// The watch's barometric altimeter.
///
/// Why this exists at all: elevation used to be read off the GPS fix, and GPS
/// altitude is the worst number a phone or watch produces. Its error is two to
/// three times the horizontal one and it wanders while standing still — so a
/// climb summed from it comes out two to three hundred metres high on a
/// thousand-metre day, which is exactly what a field test against Apple Fitness
/// showed (CUR-40).
///
/// Apple Fitness does not use it either. Every Apple Watch since Series 3 has a
/// barometer, and `CMAltimeter` is the way to it. Asking for the same signal is
/// the only way "the same as Apple Fitness" can mean anything: there is no API
/// that hands over their number, so the honest approximation is their input
/// plus a filter that does not invent height (`RunMetrics.ingestAltitude`).
///
/// **Two tiers, because two generations of hardware.**
///
/// - *Absolute* altitude (`isAbsoluteAltitudeAvailable`) is metres above sea
///   level, sensor-fused against GPS and weather models. It needs the always-on
///   altimeter: Series 6 and later, SE 2, Ultra. Every watch that runs
///   watchOS 11 has one, so today this is the path every run takes.
/// - *Relative* altitude is metres since the updates began, from the plain
///   barometer — Series 3 and later. It measures the *differences* climb is
///   made of just as well; what it cannot say is how high above the sea the
///   runner started. `RunSession` seeds that from the first GPS fix and shifts
///   the whole series onto it, which costs the climb figure nothing because a
///   uniform shift leaves every difference alone.
///
/// The second tier exists because the deployment target is not a fixed thing:
/// CUR-11 proposes watchOS 10, which brings back Series 4 and 5 — a barometer,
/// no always-on altimeter. Without this they would silently drop to GPS
/// altitude and inherit the whole over-count this ticket removed.
///
/// A watch with no barometer at all (Series 1 and 2, and the simulator) reports
/// `isAvailable == false`, and the run falls back to the GPS altitude it always
/// used.
///
/// The state is written on the main actor only. `CMAltimeter` calls back on the
/// queue it is handed, and the reading is unpacked into a plain `Double` there
/// before the hop, so nothing non-`Sendable` crosses.
@MainActor
final class BarometricAltimeter {

    /// Latest reading (m); nil until the first one lands. Above sea level when
    /// `isRelative` is false, and relative to the start of the run when it is.
    private(set) var altitude: Double?

    /// Whether `altitude` still needs a baseline to mean anything absolute.
    private(set) var isRelative = false

    #if os(watchOS) || os(iOS)
    private var altimeter: CMAltimeter?

    static var providesAbsoluteAltitude: Bool { CMAltimeter.isAbsoluteAltitudeAvailable() }
    static var isAvailable: Bool {
        CMAltimeter.isAbsoluteAltitudeAvailable() || CMAltimeter.isRelativeAltitudeAvailable()
    }

    /// Starts the updates. Idempotent, and silent when there is no barometer —
    /// the caller checks `altitude` for a reading rather than being told.
    func start() {
        guard Self.isAvailable, altimeter == nil else { return }
        let altimeter = CMAltimeter()
        self.altimeter = altimeter
        if Self.providesAbsoluteAltitude {
            isRelative = false
            altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let meters = Self.unpack(data?.altitude, error) else { return }
                Task { @MainActor in self?.altitude = meters }
            }
        } else {
            isRelative = true
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let meters = Self.unpack(data?.relativeAltitude.doubleValue, error) else { return }
                Task { @MainActor in self?.altitude = meters }
            }
        }
    }

    /// Values out before the hop: `CMAltitudeData` is a class and does not
    /// cross an actor boundary.
    private nonisolated static func unpack(_ meters: Double?, _ error: Error?) -> Double? {
        if let error {
            Log.session.error("altimeter failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return meters
    }

    func stop() {
        altimeter?.stopAbsoluteAltitudeUpdates()
        altimeter?.stopRelativeAltitudeUpdates()
        altimeter = nil
    }
    #else
    static var providesAbsoluteAltitude: Bool { false }
    static var isAvailable: Bool { false }
    func start() {}
    func stop() {}
    #endif

    /// Test seam: hand the altimeter a reading without a barometer under it.
    func debugRecord(_ meters: Double, isRelative: Bool = false) {
        altitude = meters
        self.isRelative = isRelative
    }
}
