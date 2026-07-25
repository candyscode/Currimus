import Foundation

extension Calendar {
    /// The calendar every weekly bucket in the app is measured against.
    ///
    /// `Calendar.current` starts its week on Sunday in en_US and on Saturday
    /// across much of the Arabic-speaking world. The week bars are labelled
    /// M T W T F S S and the store maps Sunday into the last slot, so in any
    /// of those locales the two disagree: "this week" contains the Sunday
    /// *before* the Monday it is drawn to the right of. The chart runs out of
    /// chronological order, and the weekly total covers a different seven days
    /// than the bars underneath it claim.
    ///
    /// Running weeks are Monday-to-Sunday by convention — every training plan
    /// ever written assumes it — so weeks are ISO 8601 here and stop depending
    /// on where the phone thinks it is. Only the week boundary is pinned; the
    /// time zone still comes from the device, and month and year buckets are
    /// left to `Calendar.current` where the user's own calendar matters.
    static let runWeek: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        // .iso8601 already implies both; stated so a later edit cannot quietly
        // inherit them from a locale instead.
        calendar.firstWeekday = 2              // Monday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()
}
