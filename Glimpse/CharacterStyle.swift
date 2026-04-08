// Glimpse/CharacterStyle.swift
import Foundation

/// Available character visual styles.
enum CharacterStyle: String, CaseIterable {
    case kawaii = "kawaii"
    case starwars = "starwars"

    var displayName: String {
        switch self {
        case .kawaii: return "Kawaii"
        case .starwars: return "Star Wars"
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
