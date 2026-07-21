import XCTest
import SwiftUI

/// Unit tests for the analytics that power the iPhone screens: race
/// prediction, records, classification, grade-adjusted pace, trends, and the
/// watch ↔ phone sync codecs. No stubs — every feature is exercised end-to-end.
final class RunAnalyticsTests: XCTestCase {

    // MARK: Riegel prediction

    func testRiegelMatchesKnownExponent() {
        // 10K in 2992 s → marathon (42.195 km) with exponent 1.06.
        let t = RunAnalytics.riegel(knownTime: 2992, knownKm: 10, targetKm: 42.195)
        let expected = 2992 * pow(42.195 / 10, 1.06)
        XCTAssertEqual(t, expected, accuracy: 0.5)
        // A marathon must take longer than 4.2× the 10K time.
        XCTAssertGreaterThan(t, 2992 * 4.2)
    }

    func testRiegelIsMonotonicInDistance() {
        let half = RunAnalytics.riegel(knownTime: 2992, knownKm: 10, targetKm: 21.0975)
        let full = RunAnalytics.riegel(knownTime: 2992, knownKm: 10, targetKm: 42.195)
        XCTAssertLessThan(half, full)
    }

    func testPredictionUsesTenKPRAndFlagsUnderTraining() {
        // A 10K PR but no long runs → under-trained marathon estimate.
        let pr = Run(date: .now, name: "10K", distanceKm: 10, duration: 2992, avgHR: 170,
                     splits: Array(repeating: 299.2, count: 10))
        let race = Race(name: "M", distance: .marathon,
                        date: Calendar.current.date(byAdding: .day, value: 42, to: .now)!,
                        goalTime: 14340)
        let prediction = RunAnalytics.predict(race: race, runs: [pr])
        XCTAssertNotNil(prediction)
        XCTAssertEqual(prediction?.basisLabel, "10K PR")
        XCTAssertTrue(prediction?.underTrained ?? false)
        XCTAssertGreaterThan(prediction?.time ?? 0, 3 * 3600) // > 3h
    }

    // MARK: Records

    func testFastestWindowFindsBestConsecutiveKm() {
        // Splits with a fast 5-km stretch in the middle.
        let splits: [TimeInterval] = [340, 340, 300, 300, 300, 300, 300, 340, 340]
        let run = Run(date: .now, name: "r", distanceKm: 9, duration: splits.reduce(0,+),
                      avgHR: 150, splits: splits)
        XCTAssertEqual(try XCTUnwrap(RunAnalytics.fastestWindow(km: 5, runs: [run])), 1500, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(RunAnalytics.fastestWindow(km: 1, runs: [run])), 300, accuracy: 0.1)
        XCTAssertNil(RunAnalytics.fastestWindow(km: 12, runs: [run]))
    }

    func testPersonalBestsIncludeHalfFromLongEffort() {
        let long = Run(date: .now, name: "long", distanceKm: 22, duration: 22 * 330,
                       avgHR: 150, splits: Array(repeating: 330, count: 22))
        let prs = RunAnalytics.personalBests(runs: [long])
        XCTAssertNotNil(prs[21.0975])
        XCTAssertEqual(prs[21.0975]!, 330 * 21.0975, accuracy: 1)
        XCTAssertNil(prs[42.195]) // no marathon-length effort
    }

    // MARK: Classification

    func testClassificationCoversEachType() {
        let long = Run(date: .now, name: "l", distanceKm: 20, duration: 20*350, avgHR: 148,
                       splits: Array(repeating: 350, count: 20),
                       zoneSeconds: [1, 60, 20, 1, 0])
        XCTAssertEqual(long.classification, .long)

        let tempo = Run(date: .now, name: "t", distanceKm: 10, duration: 10*318, avgHR: 165,
                        splits: Array(repeating: 318, count: 10),
                        zoneSeconds: [40, 120, 300, 440, 80])
        XCTAssertEqual(tempo.classification, .tempo)

        let intervals = Run(date: .now, name: "i", distanceKm: 9, duration: 9*300, avgHR: 168,
                            splits: [334, 270, 334, 270, 334, 270, 334, 270, 300],
                            zoneSeconds: [40, 120, 200, 340, 240])
        XCTAssertEqual(intervals.classification, .intervals)

        let easy = Run(date: .now, name: "e", distanceKm: 8, duration: 8*360, avgHR: 140,
                       splits: Array(repeating: 360, count: 8),
                       zoneSeconds: [200, 1800, 700, 60, 0])
        XCTAssertEqual(easy.classification, .easy)

        var trail = easy; trail.type = .trail
        XCTAssertEqual(trail.classification, .trail)
    }

    // MARK: Grade-adjusted pace

    func testGradeAdjustedPaceIsFasterUphill() {
        let flat = Run(date: .now, name: "f", distanceKm: 10, duration: 3000, avgHR: 150,
                       climbMeters: 0, descentMeters: 0)
        let hilly = Run(date: .now, name: "h", distanceKm: 10, duration: 3000, avgHR: 150,
                        climbMeters: 400, descentMeters: 400)
        // Same raw time, but the hilly run's flat-equivalent pace is faster.
        XCTAssertLessThan(RunAnalytics.gradeAdjustedPace(hilly),
                          RunAnalytics.gradeAdjustedPace(flat))
    }

    // MARK: Trends

    func testWeeklyAvgPaceExcludesTrail() {
        let road = Run(date: .now, name: "road", distanceKm: 10, duration: 3000, avgHR: 150,
                       splits: Array(repeating: 300, count: 10))
        var trail = road; trail.type = .trail; trail.duration = 4500
        let series = RunAnalytics.weeklyAvgPace(runs: [road, trail], weeks: 1, roadOnly: true)
        XCTAssertEqual(series.last!!, 300, accuracy: 0.5) // trail excluded
    }

    // MARK: Sync codecs

    func testWatchSettingsRoundTrips() throws {
        let s = WatchSettings(pacerTargetSecPerKm: 315, pacerDefaultDistanceKm: 10,
                              kilometerAlert: true, countdownEnabled: false,
                              maxHR: 188, zoneBounds: [114, 132, 151, 170])
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(WatchSettings.self, from: data)
        XCTAssertEqual(s, back)
    }

    func testRunDecodesLegacyJSONWithoutNewFields() throws {
        // A run encoded before altitudeSamples/route existed must still decode.
        let legacy = """
        {"id":"\(UUID().uuidString)","date":0,"type":"quick","name":"Old",
         "distanceKm":10,"duration":3000,"avgHR":150,"splits":[],"zoneSeconds":[0,0,0,0,0]}
        """.data(using: .utf8)!
        let run = try JSONDecoder().decode(Run.self, from: legacy)
        XCTAssertEqual(run.distanceKm, 10)
        XCTAssertNil(run.altitudeSamples)
        XCTAssertNil(run.route)
        // Every field added later must be optional, or old logs stop decoding.
        XCTAssertFalse(run.isImported)
    }

    func testRunRoundTripsWithRouteAndAltitude() throws {
        let run = Run(date: .now, name: "r", distanceKm: 5, duration: 1500, avgHR: 150,
                      altitudeSamples: [100, 110, 105],
                      route: [Coordinate(lat: 48.0, lon: 7.8, elevation: 100, t: 0)])
        let data = try JSONEncoder().encode(run)
        let back = try JSONDecoder().decode(Run.self, from: data)
        XCTAssertEqual(back.route?.count, 1)
        XCTAssertEqual(back.altitudeSamples?.count, 3)
    }

    // MARK: Race

    func testRaceRequiredPaceAndDays() {
        let date = Calendar.current.date(byAdding: .day, value: 10, to: Calendar.current.startOfDay(for: .now))!
        let race = Race(name: "M", distance: .marathon, date: date, goalTime: 14340)
        XCTAssertEqual(race.daysUntil(), 10)
        XCTAssertEqual(race.requiredPace, 14340 / 42.195, accuracy: 0.01)
    }
    // MARK: Heart-rate zones

    func testZonesFallBackToPercentOfMaxWithoutRestingHR() {
        let zones = HRZones(maxHR: 190)
        // The design's ladder at max 190.
        XCTAssertEqual(zones.bounds, [115, 133, 152, 171])
        XCTAssertFalse(zones.usesReserve)
    }

    func testZonesUseHeartRateReserveWhenRestingIsKnown() {
        let zones = HRZones(maxHR: 190, restingHR: 50)
        // Karvonen: 50 + 140 x [0.6, 0.7, 0.8, 0.9]
        XCTAssertEqual(zones.bounds, [134, 148, 162, 176])
        XCTAssertTrue(zones.usesReserve)
        // Reserve zones sit higher than the plain share of max — that is the
        // whole point, and it must not silently invert.
        XCTAssertGreaterThan(zones.bounds[0], HRZones(maxHR: 190).bounds[0])
    }

    func testTwoRunnersSharingMaxButNotRestingGetDifferentZones() {
        let fit = HRZones(maxHR: 190, restingHR: 42)
        let unfit = HRZones(maxHR: 190, restingHR: 68)
        XCTAssertNotEqual(fit.bounds, unfit.bounds)
        XCTAssertLessThan(fit.bounds[0], unfit.bounds[0])
    }

    func testManualOverridesBeatEveryDerivation() {
        var zones = HRZones(maxHR: 190, restingHR: 50)
        zones.overrides = [120, 140, 160, 175]
        XCTAssertEqual(zones.bounds, [120, 140, 160, 175])
        XCTAssertFalse(zones.usesReserve)
    }

    func testImplausibleRestingHRIsIgnoredRatherThanTrusted() {
        // A resting pulse at or above max would produce nonsense boundaries.
        XCTAssertEqual(HRZones(maxHR: 190, restingHR: 200).bounds, HRZones(maxHR: 190).bounds)
        XCTAssertEqual(HRZones(maxHR: 190, restingHR: 10).bounds, HRZones(maxHR: 190).bounds)
    }

    func testZoneLookupStaysConsistentWithReserveBounds() {
        let zones = HRZones(maxHR: 190, restingHR: 50)
        XCTAssertEqual(zones.zone(for: 100), 1)
        XCTAssertEqual(zones.zone(for: 134), 1)   // upper edge of Z1
        XCTAssertEqual(zones.zone(for: 135), 2)
        XCTAssertEqual(zones.zone(for: 180), 5)
    }

    func testTanakaBeatsTheNaiveAgeFormula() {
        // 208 - 0.7 x 40 = 180, where 220 - age would claim 180 too, but at 25
        // the two diverge and Tanaka is the calibrated one.
        XCTAssertEqual(HeartRateProfile.tanaka(age: 40), 180)
        XCTAssertEqual(HeartRateProfile.tanaka(age: 25), 191)
        XCTAssertNil(HeartRateProfile.tanaka(age: 4))
    }

    func testDerivationExplainsItselfInPlainLanguage() {
        let derivation = HRDerivation(maxSource: .measured, maxDate: .now, age: 38,
                                      restingHR: 52, restingSampleDays: 60)
        XCTAssertTrue(derivation.maxExplanation.contains("Highest heart rate"))
        let text = derivation.zoneExplanation(usesReserve: true)
        XCTAssertTrue(text.contains("52 bpm"))
        XCTAssertTrue(text.contains("60-day"))
    }

    func testWatchSettingsCarryRestingHRAndGPSAccuracy() throws {
        let s = WatchSettings(pacerTargetSecPerKm: 315, pacerDefaultDistanceKm: 10,
                              kilometerAlert: true, countdownEnabled: false,
                              maxHR: 188, zoneBounds: nil,
                              restingHR: 48, gpsAccuracy: .balanced)
        let back = try JSONDecoder().decode(WatchSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.restingHR, 48)
        XCTAssertEqual(back.gpsAccuracy, .balanced)
    }

    func testOlderWatchPayloadWithoutTheNewFieldsStillDecodes() throws {
        let legacy = """
        {"pacerTargetSecPerKm":315,"kilometerAlert":true,"countdownEnabled":true,"maxHR":190}
        """.data(using: .utf8)!
        let back = try JSONDecoder().decode(WatchSettings.self, from: legacy)
        XCTAssertEqual(back.maxHR, 190)
        XCTAssertNil(back.restingHR)
        XCTAssertNil(back.gpsAccuracy)
    }

    func testGPSAccuracyTradesPrecisionForBatteryMonotonically() {
        // Each step down must ask for coarser fixes and fewer of them.
        XCTAssertLessThan(GPSAccuracy.balanced.desiredAccuracy, GPSAccuracy.saving.desiredAccuracy)
        XCTAssertLessThan(GPSAccuracy.high.distanceFilter, GPSAccuracy.balanced.distanceFilter)
        XCTAssertLessThan(GPSAccuracy.balanced.distanceFilter, GPSAccuracy.saving.distanceFilter)
        XCTAssertEqual(GPSAccuracy.high.distanceFilter, 0)
    }

    // MARK: Always-On palette

    private func rgba(_ color: Color) -> [CGFloat] {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
        #else
        return []
        #endif
    }

    func testReducedScreenKeepsTheHeroAtFullContrast() {
        // The system already dims the panel; dimming the largest number again
        // would cost the readable glance the mode exists for.
        XCTAssertEqual(rgba(RunPalette(dimmed: true).hero), rgba(Theme.ink))
        XCTAssertEqual(rgba(RunPalette(dimmed: false).hero), rgba(Theme.ink))
    }

    func testReducedScreenStepsSecondaryInkBack() {
        let live = RunPalette(dimmed: false)
        let dim = RunPalette(dimmed: true)
        // Every supporting colour must get darker, never brighter.
        for (a, b) in [(live.stat, dim.stat), (live.label, dim.label), (live.track, dim.track)] {
            let (bright, dark) = (rgba(a), rgba(b))
            XCTAssertGreaterThan(bright[0], dark[0], "reduced colour must be darker")
        }
    }

    func testReducedSignalDropsToTheDesignsFiftyFivePercent() {
        XCTAssertEqual(rgba(RunPalette(dimmed: true).signal)[3], 0.55, accuracy: 0.01)
        XCTAssertEqual(rgba(RunPalette(dimmed: false).signal)[3], 1.0, accuracy: 0.01)
    }

    func testActiveZoneFillFollowsTheDesignPerState() {
        XCTAssertEqual(RunPalette(dimmed: false).activeZoneFill, 0.30, accuracy: 0.001)
        XCTAssertEqual(RunPalette(dimmed: true).activeZoneFill, 0.28, accuracy: 0.001)
    }
}
