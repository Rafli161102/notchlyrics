import Foundation

enum DisplayMode: String, Codable, CaseIterable {
    case touchBar
    case notch
    case both
    case hidden

    /// Keep existing users on the original Touch Bar output until they choose notch output.
    static let defaultMode: DisplayMode = .touchBar

    var showsTouchBar: Bool {
        self == .touchBar || self == .both
    }

    var showsNotch: Bool {
        self == .notch || self == .both
    }

    var displayName: String {
        switch self {
        case .touchBar: return "Touch Bar"
        case .notch: return "Notch"
        case .both: return "Touch Bar + Notch"
        case .hidden: return "Sembunyikan"
        }
    }
}
