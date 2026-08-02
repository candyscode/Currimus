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
/// barometer, and `CMAltimeter`'s *absolute* altitude is the sensor fusion
/// Apple itself runs on top of it — barometric pressure corrected against GPS
/// and weather models. Asking for the same signal is the only way "the same as
/// Apple Fitness" can mean anything: there is no API that hands over their
/// number, so the honest approximation is their input plus a filter that does
/// not invent height (`RunMetrics.ingestAltitude`).
///
/// Absolute altitude needs watchOS 8 and a Series 6 or newer — the app's floor
/// is watchOS 11, which needs a Series 6 anyway, so on every watch that can run
/// Currimus this is available. `isAvailable` is still asked, and a run on
/// hardware that says no falls back to the GPS altitude it always used.
///
/// The state is written on the main actor only. `CMAltimeter` calls back on the
/// queue it is handed, and the reading is unpacked into plain `Double`s there
/// before the hop, so nothing non-`Sendable` crosses.
@MainActor
final class BarometricAltimeter {

    /// Latest altitude above sea level (m); nil until the first reading lands.
    private(set) var altitude: Double?

    #if os(watchOS) || os(iOS)
    private var altimeter: CMAltimeter?

    static var isAvailable: Bool { CMAltimeter.isAbsoluteAltitudeAvailable() }

    /// Starts the updates. Idempotent, and silent when there is no barometer —
    /// the caller checks `altitude` for a reading rather than being told.
    func start() {
        guard Self.isAvailable, altimeter == nil else { return }
        let altimeter = CMAltimeter()
        self.altimeter = altimeter
        altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, error in
            if let error {
                Log.session.error("altimeter failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let data else { return }
            // The value out first: `CMAbsoluteAltitudeData` is a class and does
            // not cross an actor boundary.
            let meters = data.altitude
            Task { @MainActor in self?.altitude = meters }
        }
    }

    func stop() {
        altimeter?.stopAbsoluteAltitudeUpdates()
        altimeter = nil
    }
    #else
    static var isAvailable: Bool { false }
    func start() {}
    func stop() {}
    #endif

    /// Test seam: hand the altimeter a reading without a barometer under it.
    func debugRecord(_ meters: Double) { altitude = meters }
}
