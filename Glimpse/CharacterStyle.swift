// Glimpse/CharacterStyle.swift
import Foundation

/// Available character visual styles.
enum CharacterStyle: String, CaseIterable {
    case kawaii = "kawaii"
    case starwars = "starwars"
    case demonslayer = "demonslayer"
    case onepiece = "onepiece"
    case dragonball = "dragonball"
    case theoffice = "theoffice"
    case marvel = "marvel"

    var displayName: String {
        switch self {
        case .kawaii: return "Kawaii"
        case .starwars: return "Star Wars"
        case .demonslayer: return "Demon Slayer"
        case .onepiece: return "One Piece"
        case .dragonball: return "Dragon Ball Z"
        case .theoffice: return "The Office"
        case .marvel: return "Marvel"
        }
    }

    // MARK: - UserDefaults Persistence

    private static let key = "characterStyle"

    static var current: CharacterStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let style = CharacterStyle(rawValue: raw) else {
                return .kawaii
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: .characterStyleDidChange, object: newValue)
        }
    }
}

extension Notification.Name {
    static let characterStyleDidChange = Notification.Name("characterStyleDidChange")
}
