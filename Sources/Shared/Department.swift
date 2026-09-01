import Foundation

/// Abteilungen wie in der PWA (`DEPTS`). IDs nicht ändern.
enum Department: String, CaseIterable, Codable, Identifiable, Sendable {
    case vor
    case obst
    case brot
    case bedienung
    case kuehlung
    case tiefkuehl
    case trocken
    case suess
    case getraenke
    case drogerie
    case sonstiges
    case nach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vor: return "Vor dem Einkauf"
        case .obst: return "Obst & Gemüse"
        case .brot: return "Brot & Backwaren"
        case .bedienung: return "Fleisch, Wurst, Käse"
        case .kuehlung: return "Kühlregal"
        case .tiefkuehl: return "Tiefkühl"
        case .trocken: return "Trockenwaren"
        case .suess: return "Süßwaren & Snacks"
        case .getraenke: return "Getränke"
        case .drogerie: return "Drogerie & Haushalt"
        case .sonstiges: return "Sonstiges"
        case .nach: return "Nach dem Einkauf"
        }
    }

    static func isKnown(_ id: String) -> Bool {
        Department(rawValue: id) != nil
    }

    static func resolved(_ id: String) -> String {
        isKnown(id) ? id : Department.sonstiges.rawValue
    }

    static func title(for id: String) -> String {
        Department(rawValue: id)?.title ?? id
    }
}
