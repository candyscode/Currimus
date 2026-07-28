import Foundation
import HealthKit

/// Derives heart-rate zones from whatever Apple Health actually knows about
/// the runner, in order of trustworthiness:
///
/// 1. **Max HR** — measured, not guessed. Health is asked for the highest heart
///    rate of every single day over the past year; the third-highest of those
///    daily peaks becomes the max. Taking the outright highest sample would let
///    one optical-sensor glitch set the ceiling for every zone, and a
///    third-place value across a year is still a genuine hard effort.
///    Without a year of hard efforts it falls back to the Tanaka age formula
///    (208 − 0.7 × age), which is markedly better calibrated than 220 − age.
/// 2. **Resting HR** — Health's own resting figure, averaged over 60 days.
/// 3. **Zones** — with both numbers the split runs on heart-rate *reserve*
///    (Karvonen), which respects that two runners sharing a max but not a
///    resting pulse do not share zones. With only a max it stays on % of max.
enum HeartRateProfile {
    /// Ignore anything outside this — sensor dropouts and stationary artifacts.
    private static let plausibleMax = 120.0...225.0
    /// How far a single day's peak may stand above the next one before it is
    /// treated as a sensor artifact rather than a hard effort.
    ///
    /// This used to reach for the *third*-highest day outright, which is very
    /// robust and reliably lands a few beats under the real ceiling — and a
    /// max heart rate that is a few beats low drags every zone boundary down
    /// with it, which is why Currimus placed runs a zone higher than Apple
    /// Fitness did. Apple takes the highest it has seen; so does this now,
    /// with one guard for the lone spike that nothing else comes near.
    private static let spikeMargin = 12.0

    struct Result: Equatable {
        var maxHR: Int
        var restingHR: Int?
        var derivation: HRDerivation
    }

    static func derive(_ store: HKHealthStore) async -> Result? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        let peak = await measuredPeak(store)
        let resting = await restingHeartRate(store)
        let age = birthAge(store)

        let maxHR: Int
        let derivation: HRDerivation
        if let peak {
            maxHR = peak.bpm
            derivation = HRDerivation(
                maxSource: .measured, maxDate: peak.day, age: age,
                restingHR: resting?.bpm, restingSampleDays: resting?.days
            )
        } else if let age, let estimated = tanaka(age: age) {
            maxHR = estimated
            derivation = HRDerivation(
                maxSource: .age, maxDate: nil, age: age,
                restingHR: resting?.bpm, restingSampleDays: resting?.days
            )
        } else {
            return nil   // nothing to improve on — leave the user's setting alone
        }
        return Result(maxHR: maxHR, restingHR: resting?.bpm, derivation: derivation)
    }

    /// 208 − 0.7 × age (Tanaka et al., 2001).
    static func tanaka(age: Int) -> Int? {
        guard age >= 10, age <= 100 else { return nil }
        return Int((208 - 0.7 * Double(age)).rounded())
    }

    // MARK: - Health queries

    /// The highest believable daily peak of the past year — Apple's rule,
    /// with a guard against a single glitch setting the ceiling.
    private static func measuredPeak(_ store: HKHealthStore) async -> (bpm: Int, day: Date)? {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .year, value: -1, to: end) else { return nil }

        let peaks: [(bpm: Double, day: Date)] = await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(.heartRate),
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .discreteMax,
                anchorDate: Calendar.current.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var found: [(Double, Date)] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let value = stats.maximumQuantity()?.doubleValue(for: unit) {
                        found.append((value, stats.startDate))
                    }
                }
                continuation.resume(returning: found.map { (bpm: $0.0, day: $0.1) })
            }
            store.execute(query)
        }

        let ranked = peaks
            .filter { plausibleMax.contains($0.bpm) }
            .sorted { $0.bpm > $1.bpm }
        // Enough hard days that the top one has something to be judged against.
        guard ranked.count >= 3 else { return nil }
        // A day that stands more than `spikeMargin` above the next two is a
        // reading, not a runner: an optical sensor losing contact reports one
        // wild value, and a genuine ceiling has near-misses under it.
        let pick = ranked[0].bpm - ranked[2].bpm > spikeMargin ? ranked[1] : ranked[0]
        return (Int(pick.bpm.rounded()), pick.day)
    }

    /// Health's own resting heart rate, averaged over the last 60 days.
    private static func restingHeartRate(_ store: HKHealthStore) async -> (bpm: Int, days: Int)? {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -60, to: end) else { return nil }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.restingHeartRate),
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: [.discreteAverage]
            ) { _, stats, _ in
                guard let average = stats?.averageQuantity()?.doubleValue(for: unit),
                      average > 30, average < 120 else {
                    continuation.resume(returning: nil)
                    return
                }
                let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 60
                continuation.resume(returning: (Int(average.rounded()), days))
            }
            store.execute(query)
        }
    }

    private static func birthAge(_ store: HKHealthStore) -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birth = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.dateComponents([.year], from: birth, to: .now).year
    }
}
