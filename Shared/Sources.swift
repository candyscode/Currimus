import Foundation

/// The published work this app leans on, in one place.
///
/// Every number Currimus shows is either measured or modelled. The measured
/// ones speak for themselves; the modelled ones are somebody else's research
/// applied to your runs, and a runner deciding what to do on Sunday deserves
/// to know which is which — and to be able to go and read the thing.
///
/// Named and linked, never spelled out as a formula: "after Tanda (2011)" is
/// what a reader can act on, and the exponent is not.
enum Source: CaseIterable {
    case riegel
    case tanda
    case tanaka
    case heiderscheit

    var label: String {
        switch self {
        case .riegel: return "Riegel (1981)"
        case .tanda: return "Tanda (2011)"
        case .tanaka: return "Tanaka et al. (2001)"
        case .heiderscheit: return "Heiderscheit et al. (2011)"
        }
    }

    /// What it is, for the acknowledgements list.
    var what: String {
        switch self {
        case .riegel:
            return String(localized: "Scaling a known race time to another distance — the basis of every race prediction here.")
        case .tanda:
            return String(localized: "Predicting a marathon from the volume and pace of the eight weeks before it.")
        case .tanaka:
            return String(localized: "Estimating maximum heart rate from age, when Apple Health has never seen a hard effort to measure it from.")
        case .heiderscheit:
            return String(localized: "What a five to ten per cent quicker step rate does to the load a knee absorbs — the reason for the cadence hint.")
        }
    }

    var url: String {
        switch self {
        case .riegel: return "https://www.jstor.org/stable/27850389"
        case .tanda: return "https://pubmed.ncbi.nlm.nih.gov/21957197/"
        case .tanaka: return "https://www.sciencedirect.com/science/article/pii/S0735109700010548"
        case .heiderscheit: return "https://pmc.ncbi.nlm.nih.gov/articles/PMC3022995/"
        }
    }

    /// "[Tanda (2011)](https://…)", for inline use in an explanatory line.
    var link: String { "[\(label)](\(url))" }
}
